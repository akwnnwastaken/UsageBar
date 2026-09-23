import Foundation
import UsageBarSync
import UsageBarSyncTransport
import UsageBarPairing

/// The lab-only preference: whether Mobile Sync is on.
///
/// Not a secret, so it lives in UsageBar's own `UserDefaults` domain alongside
/// the provider preferences. It is a new key in a new domain rather than a
/// renamed one: the standalone Mobile Lab host had its own bundle identifier
/// and therefore its own preferences, and nothing migrates across. Someone who
/// had enabled sync in that separate application does not silently get a
/// listener here.
public protocol MobileSyncPreferenceStoring: AnyObject {
    var isMobileSyncEnabled: Bool { get set }
}

public final class MobileSyncUserDefaultsPreferences: MobileSyncPreferenceStoring {
    /// Absent means false, so a first launch after upgrading has Mobile Sync
    /// off and opens nothing. Capability in the binary is not activation.
    static let preferenceKey = "MobileSyncEnabled"
    private let key = MobileSyncUserDefaultsPreferences.preferenceKey
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isMobileSyncEnabled: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

public final class InMemoryMobileSyncPreferences: MobileSyncPreferenceStoring {
    public var isMobileSyncEnabled: Bool
    public init(isMobileSyncEnabled: Bool = false) {
        self.isMobileSyncEnabled = isMobileSyncEnabled
    }
}

/// Owns the Mobile Sync lifecycle: the listener, the pairing session and the
/// paired credential.
///
/// Everything it does is subordinate to UsageBar. Every entry point is
/// non-throwing to its caller or returns a result the caller may ignore,
/// because the menu bar must keep working when the listener cannot bind, the
/// Keychain refuses, Tailscale is down or pairing is impossible. Sync is a
/// feature of this app; it is never a precondition for it.
public final class MobileSyncCoordinator: @unchecked Sendable {
    public enum Status: Equatable {
        /// Not running, by preference.
        case disabled
        /// Enabled, but the listener could not bind. Reported, never fatal.
        case listenerUnavailable
        /// Listening, no phone paired.
        case ready
        /// Listening, a pairing session is open.
        case pairing
        /// Listening, a phone is paired.
        case paired
    }

    public let snapshots: UsageSyncLiveSnapshotStore

    private let authStore: any MobileSyncAuthStoring
    private let preferences: any MobileSyncPreferenceStoring
    private let pairingSessions: MobileSyncPairingSessionStore
    private let port: UInt16
    private let isPermittedInThisProcess: Bool
    private let makeServer: (@escaping @Sendable (UsageSyncTransportRequest) -> UsageSyncTransportResponse) -> UsageSyncLoopbackHTTPServer

    private let lock = NSLock()
    private var server: UsageSyncLoopbackHTTPServer?
    private var listenerFailed = false

    public init(
        snapshots: UsageSyncLiveSnapshotStore = UsageSyncLiveSnapshotStore(),
        authStore: any MobileSyncAuthStoring,
        preferences: any MobileSyncPreferenceStoring,
        pairingSessions: MobileSyncPairingSessionStore = MobileSyncPairingSessionStore(),
        port: UInt16 = MobileSyncIdentity.loopbackPort,
        isPermittedInThisProcess: Bool = MobileSyncIdentity.isEnabledForCurrentProcess,
        makeServer: @escaping (@escaping @Sendable (UsageSyncTransportRequest) -> UsageSyncTransportResponse) -> UsageSyncLoopbackHTTPServer = { handler in
            UsageSyncLoopbackHTTPServer(handler: handler)
        }
    ) {
        self.snapshots = snapshots
        self.authStore = authStore
        self.preferences = preferences
        self.pairingSessions = pairingSessions
        self.port = port
        self.isPermittedInThisProcess = isPermittedInThisProcess
        self.makeServer = makeServer
    }

    // MARK: - Lifecycle

    /// Whether this process may run Mobile Sync at all.
    ///
    /// The lab source tree containing the feature is not permission to run it:
    /// an ordinary UsageBar bundle links this module and must still never open
    /// a listener or hold a mobile credential.
    public var isPermitted: Bool { isPermittedInThisProcess }

    public var isEnabled: Bool { isPermitted && preferences.isMobileSyncEnabled }

    public var isPaired: Bool { authStore.load() != nil }

    public var status: Status {
        guard isEnabled else { return .disabled }
        lock.lock()
        let running = server != nil
        let failed = listenerFailed
        lock.unlock()
        guard running else { return failed ? .listenerUnavailable : .disabled }
        if pairingSessions.isPairing { return .pairing }
        return isPaired ? .paired : .ready
    }

    /// Called at launch. A disabled or non-lab process does nothing at all.
    public func startIfEnabled() {
        guard isEnabled else { return }
        startListener()
    }

    /// Turns Mobile Sync on and persists that choice. Returns whether the
    /// listener actually came up; a caller may show that, but must not depend
    /// on it.
    @discardableResult
    public func enable() -> Bool {
        guard isPermitted else { return false }
        preferences.isMobileSyncEnabled = true
        return startListener()
    }

    /// Turns Mobile Sync off completely: listener down, pairing cancelled,
    /// credential forgotten. Disabling is a revocation, not a pause — leaving a
    /// paired credential behind for a feature the owner has switched off would
    /// be a surprise the next time they switched it on.
    public func disable() {
        preferences.isMobileSyncEnabled = false
        pairingSessions.cancel()
        authStore.clear()
        stopListener()
    }

    @discardableResult
    private func startListener() -> Bool {
        lock.lock()
        if server != nil {
            lock.unlock()
            return true
        }
        lock.unlock()

        let service = MobileSyncService(
            authStore: authStore,
            pairing: pairingSessions,
            source: snapshots
        )
        let created = makeServer { request in service.respond(to: request) }
        do {
            try created.start(port: port)
        } catch {
            // A port already in use, or a sandbox refusing to bind, must not
            // take the app down with it.
            lock.lock()
            listenerFailed = true
            lock.unlock()
            return false
        }
        lock.lock()
        server = created
        listenerFailed = false
        lock.unlock()
        return true
    }

    private func stopListener() {
        lock.lock()
        let existing = server
        server = nil
        listenerFailed = false
        lock.unlock()
        existing?.stop()
    }

    public var boundPort: UInt16? {
        lock.lock()
        defer { lock.unlock() }
        return server?.boundPort
    }

    // MARK: - Pairing

    /// Opens a pairing window and returns what the QR needs.
    ///
    /// Returns nil rather than a partial result when Tailscale is not ready:
    /// a QR naming a host the phone cannot reach is a worse outcome than no QR,
    /// because the failure surfaces on the phone instead of on the Mac where
    /// the owner is standing.
    public func startPairing(host: String, now: Date = Date()) -> UsageBarPairingPayload? {
        guard isEnabled else { return nil }
        let session = pairingSessions.start(now: now)
        guard let payload = try? UsageBarPairingPayload(host: host, pairingCode: session.code) else {
            pairingSessions.cancel()
            return nil
        }
        return payload
    }

    public func pairingSession(now: Date = Date()) -> MobileSyncPairingSession? {
        pairingSessions.current(now: now)
    }

    public func cancelPairing() {
        pairingSessions.cancel()
    }

    /// Forgets the paired phone. The listener stays up so the owner can pair
    /// again without re-enabling the feature.
    public func revokePairedDevice() {
        pairingSessions.cancel()
        authStore.clear()
    }

    // MARK: - Snapshot publication

    /// Publishes desktop state for the transport to serve.
    ///
    /// Non-throwing on purpose. A snapshot that fails to build or validate
    /// leaves the previous one published and is otherwise ignored: the refresh
    /// cycle that called this must not learn about it, let alone be interrupted
    /// by it.
    @discardableResult
    public func publish(
        providers: [MobileSyncLiveSnapshot.ProviderState],
        generatedAt: Date = Date()
    ) -> Bool {
        guard isEnabled else { return false }
        return snapshots.publish {
            try MobileSyncLiveSnapshot.build(from: providers, generatedAt: generatedAt)
        }
    }
}
