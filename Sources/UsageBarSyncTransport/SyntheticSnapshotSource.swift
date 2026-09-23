import Foundation
import UsageBarSync

/// Supplies the snapshot the service serves.
///
/// The prototype is wired to synthetic data only. Nothing in this module
/// reaches into a running UsageBar, reads a provider, or touches the desktop's
/// retained state — Phase 4 proves the *transport*, and doing that with real
/// quota data would put live usage on a network path before the path itself
/// has been reviewed.
public protocol UsageSyncSnapshotSource: Sendable {
    func currentSnapshot() throws -> UsageSyncSnapshot
}

/// A fixed, hand-written schema-v1 snapshot.
///
/// The values are invented. They resemble a plausible reading so the shape is
/// exercised honestly, but they correspond to no real account and no real
/// measurement.
public struct UsageSyncSyntheticSnapshotSource: UsageSyncSnapshotSource {
    public init() {}

    public func currentSnapshot() throws -> UsageSyncSnapshot {
        UsageSyncSyntheticSnapshotSource.fixture
    }

    public static let fixture: UsageSyncSnapshot = {
        let generatedAt = UsageSyncSerialization.date(from: "2026-03-04T09:00:00Z")!
        return UsageSyncSnapshot(
            generatedAt: generatedAt,
            providers: [
                UsageSyncProvider(
                    providerId: "codex",
                    connected: true,
                    collecting: true,
                    measurement: UsageSyncMeasurement(
                        measuredAt: UsageSyncSerialization.date(from: "2026-03-04T09:00:00Z")!,
                        headlineRemainingPercent: 64,
                        headlineWindowId: "five-hour",
                        windows: [
                            UsageSyncWindow(
                                windowId: "five-hour",
                                kind: .fiveHour,
                                durationMinutes: 300,
                                remainingPercent: 64,
                                resetsAt: UsageSyncSerialization.date(from: "2026-03-04T13:00:00Z")!
                            ),
                            UsageSyncWindow(
                                windowId: "weekly",
                                kind: .weekly,
                                durationMinutes: 10_080,
                                remainingPercent: 81,
                                resetsAt: UsageSyncSerialization.date(from: "2026-03-08T00:00:00Z")!
                            )
                        ]
                    )
                )
            ]
        )
    }()
}

/// Loads a schema-v1 snapshot from a JSON file on disk.
///
/// Used to serve one of the shared parity fixtures during the live smoke, so
/// the bytes crossing the tailnet are the same corpus both platform builders
/// are tested against rather than a shape invented for the transport.
///
/// The file is decoded *and validated* at load time. An unreadable or invalid
/// fixture is a startup failure, never a half-served response.
public struct UsageSyncFileSnapshotSource: UsageSyncSnapshotSource {
    private let snapshot: UsageSyncSnapshot

    public enum LoadFailure: Error, CustomStringConvertible {
        case unreadable

        public var description: String { "fixture could not be read" }
    }

    public init(contentsOfFile path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw LoadFailure.unreadable
        }
        self.snapshot = try UsageSyncSerialization.decode(data)
    }

    public func currentSnapshot() throws -> UsageSyncSnapshot {
        snapshot
    }
}
