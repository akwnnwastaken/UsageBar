import Foundation
import UsageBarSync
import UsageBarSyncTransport

/// Holds the latest validated snapshot for the transport to read.
///
/// The desktop builds snapshots on the main queue, where its state lives. The
/// listener answers on background connection queues. This is the only thing
/// between them, and it exists so that a socket handler never reaches into
/// AppKit state and never blocks the main queue — a `DispatchQueue.main.sync`
/// from a connection thread would deadlock the menu bar the first time a
/// request arrived while the app was mid-refresh.
///
/// What crosses is an immutable, already-validated value type. No AppKit
/// object, no provider, no fetcher and no preference reference passes this
/// boundary.
public final class UsageSyncLiveSnapshotStore: UsageSyncSnapshotSource, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: UsageSyncSnapshot?

    public init(initial: UsageSyncSnapshot? = nil) {
        self.snapshot = initial
    }

    /// Replaces the published snapshot.
    ///
    /// Validation happens *before* the lock is taken and before anything is
    /// stored, so a snapshot that would not survive the validator can never
    /// become the one a phone is served. A rejected update leaves the previous
    /// good snapshot exactly where it was: a transient build failure must read
    /// as "last known", never as "no data".
    @discardableResult
    public func publish(_ candidate: UsageSyncSnapshot) -> Bool {
        do {
            try UsageSyncValidator.validate(candidate)
        } catch {
            return false
        }
        lock.lock()
        snapshot = candidate
        lock.unlock()
        return true
    }

    /// Builds and publishes in one step, so a throwing builder cannot leave a
    /// half-built value behind. The previous snapshot survives a failure.
    @discardableResult
    public func publish(building: () throws -> UsageSyncSnapshot) -> Bool {
        guard let candidate = try? building() else { return false }
        return publish(candidate)
    }

    public var latest: UsageSyncSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    public func clear() {
        lock.lock()
        snapshot = nil
        lock.unlock()
    }

    /// The transport's read. Never touches the desktop.
    public func currentSnapshot() throws -> UsageSyncSnapshot {
        guard let snapshot = latest else {
            throw UsageSyncTransportRejection.snapshotUnavailable
        }
        return snapshot
    }
}
