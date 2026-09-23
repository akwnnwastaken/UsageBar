import Foundation
import UsageBarSync

/// The narrow seam Phase 6 will widen.
///
/// Today the only implementation writes into the app sandbox. When widgets
/// arrive they will need the same bytes from a shared App Group container —
/// swapping the implementation behind this protocol is the whole change, and
/// nothing in networking, validation or presentation has to move. The App Group
/// itself is deliberately not created yet; it belongs to the widget checkpoint.
public protocol SnapshotCaching: AnyObject {
    func load() -> UsageSyncSnapshot?
    func store(_ snapshot: UsageSyncSnapshot) throws
    func clear()
}

/// A single validated snapshot on disk, in the app's own container.
///
/// What is cached is exactly what crossed the wire and passed validation:
/// schema-v1 and nothing else. The endpoint host, the bearer token, the
/// Tailscale identity of the caller and any error detail are all absent —
/// there is no field for them, and this type never sees them.
public final class FileSnapshotCache: SnapshotCaching {
    private let url: URL

    /// Exposed so tests can assert that the app and the widget never point at
    /// the same file. Without an App Group they are in separate containers
    /// anyway, but the names differ too, so the separation does not depend on
    /// container layout staying the way it is today.
    public var fileURL: URL { url }

    public init(url: URL) {
        self.url = url
    }

    /// The default location: Application Support, excluded from iCloud/iTunes
    /// backup because it is a re-fetchable cache, not user data.
    public convenience init(fileName: String = "snapshot-v1.json") {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.init(url: base.appendingPathComponent(fileName))
    }

    public func load() -> UsageSyncSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Re-validate on the way in. A file can be truncated by a crash, or
        // edited on a jailbroken device, and a cache is just as untrusted as a
        // network response once it has left the process that wrote it.
        guard let snapshot = try? UsageSyncSerialization.decode(data) else {
            // Corrupt is not fatal: drop it and behave like a first launch.
            clear()
            return nil
        }
        return snapshot
    }

    public func store(_ snapshot: UsageSyncSnapshot) throws {
        // `encode` validates first, so an invalid snapshot never reaches disk.
        let data = try UsageSyncSerialization.encode(snapshot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomic: a half-written cache would be indistinguishable from a
        // truncated one, and would cost the user their last good reading.
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        excludeFromBackup()
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    private func excludeFromBackup() {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(resourceValues)
    }
}

/// In-memory cache for tests and previews.
public final class InMemorySnapshotCache: SnapshotCaching {
    private var snapshot: UsageSyncSnapshot?

    public init(snapshot: UsageSyncSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() -> UsageSyncSnapshot? { snapshot }
    public func store(_ snapshot: UsageSyncSnapshot) throws { self.snapshot = snapshot }
    public func clear() { snapshot = nil }
}
