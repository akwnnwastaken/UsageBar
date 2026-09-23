import Foundation
import Observation
import UsageBarSync

/// The app's single source of truth.
///
/// Holds the connection, the last validated snapshot and the refresh state, and
/// enforces the rule that matters most when the Mac is asleep: **a failed
/// refresh never clears a good snapshot.** The desktop being unreachable is the
/// accepted tradeoff of a direct overlay rather than a relay, so it must read
/// as "this is the last reading" and not as "there is no data".
@MainActor
@Observable
public final class AppSnapshotStore {
    public enum Phase: Equatable {
        case needsConnection
        case ready
    }

    public private(set) var phase: Phase
    public private(set) var snapshot: UsageSyncSnapshot?
    public private(set) var isRefreshing = false
    /// Set when the *most recent* refresh failed. Cleared by a success.
    /// Shown as a small banner beside data that is still displayed.
    public private(set) var lastRefreshFailed = false

    private let store: ConnectionStore
    private let cache: SnapshotCaching
    private let client: SnapshotFetching
    private let surfaces: any UsageSurfaceReloading
    private var connection: UsageSyncConnection?

    public init(
        store: ConnectionStore,
        cache: SnapshotCaching,
        client: SnapshotFetching,
        surfaces: any UsageSurfaceReloading = RecordingSurfaceReloader()
    ) {
        let restored = store.load()
        self.store = store
        self.cache = cache
        self.client = client
        self.surfaces = surfaces
        self.connection = restored
        // Show cached data immediately on launch. The user should never watch a
        // spinner to find out what they already knew last time.
        self.snapshot = cache.load()
        self.phase = restored == nil ? .needsConnection : .ready
    }

    public var isConnected: Bool { connection != nil }

    /// Saves a connection and immediately proves it works.
    ///
    /// The credential is only persisted after a successful fetch, so a typo
    /// cannot leave the app in a state that looks configured but never loads.
    public func connect(host: UsageSyncHost, accessKey: String) async -> Result<Void, Error> {
        let candidate = UsageSyncConnection(host: host, accessKey: accessKey)
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fetched = try await client.fetchSnapshot(using: candidate)
            try store.save(candidate)
            connection = candidate
            try? cache.store(fetched)
            snapshot = fetched
            lastRefreshFailed = false
            phase = .ready
            // Widgets and controls can now read the shared credential; ask
            // them to re-evaluate rather than waiting for the next
            // system-scheduled refresh.
            reloadSurfaces()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// User-initiated foreground refresh. No timer, no background task, no
    /// silent push — Phase 5 fetches only when asked.
    public func refresh() async {
        guard let connection else { return }
        // Concurrent refreshes would race to write the cache for no benefit.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fetched = try await client.fetchSnapshot(using: connection)
            try? cache.store(fetched)
            snapshot = fetched
            lastRefreshFailed = false
            reloadSurfaces()
        } catch let error as SnapshotFetchError where error.revokesStoredCredential {
            // The desktop refused the credential outright: revoked on the Mac,
            // or superseded by a re-pairing. Every other failure leaves the
            // connection alone, but this one is definitive, and continuing to
            // show usage the phone is no longer entitled to would be wrong.
            forgetConnection()
        } catch {
            // Deliberately does not touch `snapshot` or the cache.
            lastRefreshFailed = true
        }
    }

    /// Completes a QR pairing.
    ///
    /// The long-lived key is held in memory and proven before it is persisted:
    /// a credential that cannot actually fetch a snapshot would leave the app
    /// looking configured and permanently failing, which is worse than a
    /// pairing that visibly did not work.
    public func completePairing(_ paired: PairedConnection) async -> Result<Void, Error> {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fetched = try await client.fetchSnapshot(using: paired.connection)
            // Only now does anything reach the keychain.
            try store.save(paired.connection)
            connection = paired.connection
            try? cache.store(fetched)
            snapshot = fetched
            lastRefreshFailed = false
            phase = .ready
            reloadSurfaces()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Removes the credential, the host and the cached snapshot together.
    ///
    /// All three, always: leaving a cached snapshot behind after the user has
    /// disconnected would keep showing their usage to whoever next opens the
    /// app.
    public func forgetConnection() {
        store.clear()
        cache.clear()
        connection = nil
        snapshot = nil
        lastRefreshFailed = false
        phase = .needsConnection
        // Critical for revocation, and deliberately the *last* thing here.
        // Without an App Group the app cannot delete the extension's private
        // cache, so instead the widget and the controls refuse to display an
        // authenticated snapshot once the shared credentials are gone. The
        // credential removal above must therefore already have happened when
        // the surfaces are asked to re-evaluate; reversing that order would ask
        // them to rebuild while the keychain still authorized the old data.
        reloadSurfaces()
    }

    /// Widgets and Control Center controls read the same shared credential and
    /// the same schema-v1 snapshot, so every event that changes either changes
    /// both. Requesting them together keeps that fact in one place.
    private func reloadSurfaces() {
        surfaces.reloadWidgets()
        surfaces.reloadControls()
    }
}
