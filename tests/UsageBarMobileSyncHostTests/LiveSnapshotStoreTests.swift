import XCTest
import UsageBarSync
@testable import UsageBarMobileSyncHost

/// The only thing between the desktop's main queue and the listener's
/// connection queues.
final class LiveSnapshotStoreTests: XCTestCase {
    func testStartsEmptyAndReportsUnavailable() {
        let store = UsageSyncLiveSnapshotStore()
        XCTAssertNil(store.latest)
        XCTAssertThrowsError(try store.currentSnapshot())
    }

    func testPublishedSnapshotIsServed() throws {
        let store = UsageSyncLiveSnapshotStore()
        let snapshot = try HostFixtures.snapshot()
        XCTAssertTrue(store.publish(snapshot))
        XCTAssertEqual(try store.currentSnapshot(), snapshot)
    }

    /// An initial state where nothing is connected is a perfectly valid
    /// snapshot, and the phone should be told it rather than served a 503.
    func testDisconnectedInitialSnapshotIsValidAndPublishable() throws {
        let store = UsageSyncLiveSnapshotStore()
        let snapshot = try MobileSyncLiveSnapshot.build(from: [
            HostFixtures.state("Codex", connected: false, collecting: false, usage: nil),
            HostFixtures.state("Claude Code", connected: false, collecting: false, usage: nil)
        ])
        XCTAssertTrue(store.publish(snapshot))
        XCTAssertEqual(try store.currentSnapshot().providers.count, 2)
    }

    func testRefreshPausePublishAndDisconnectPublishAreAllValid() throws {
        let store = UsageSyncLiveSnapshotStore()
        // Refresh completion.
        XCTAssertTrue(store.publish(try HostFixtures.snapshot()))
        // Pause.
        XCTAssertTrue(store.publish(try HostFixtures.snapshot([
            HostFixtures.state("Codex", collecting: false, usage: HostFixtures.codexUsage()),
            HostFixtures.state("Claude Code", usage: HostFixtures.claudeUsage())
        ])))
        XCTAssertEqual(store.latest?.providers.first?.collecting, false)
        // Disconnect.
        XCTAssertTrue(store.publish(try HostFixtures.snapshot([
            HostFixtures.state("Codex", connected: false, collecting: false, usage: HostFixtures.codexUsage()),
            HostFixtures.state("Claude Code", usage: HostFixtures.claudeUsage())
        ])))
        XCTAssertNil(store.latest?.providers.first?.measurement)
    }

    /// Validation happens before anything is stored, so an invalid snapshot is
    /// never briefly observable by a request that arrives mid-publish.
    func testInvalidSnapshotIsNeverStored() throws {
        let store = UsageSyncLiveSnapshotStore()
        let good = try HostFixtures.snapshot()
        XCTAssertTrue(store.publish(good))

        let invalid = UsageSyncSnapshot(
            schemaVersion: 1,
            generatedAt: HostFixtures.generatedAt,
            providers: [
                UsageSyncProvider(
                    providerId: "codex",
                    connected: false,
                    // A disconnected provider carrying a measurement is exactly
                    // what the validator exists to catch.
                    collecting: false,
                    measurement: UsageSyncMeasurement(
                        measuredAt: HostFixtures.measuredAt,
                        headlineRemainingPercent: 50,
                        headlineWindowId: "five-hour",
                        windows: [
                            UsageSyncWindow(
                                windowId: "five-hour",
                                kind: .fiveHour,
                                durationMinutes: 300,
                                remainingPercent: 50
                            )
                        ]
                    )
                )
            ]
        )
        XCTAssertFalse(store.publish(invalid))
        XCTAssertEqual(store.latest, good)
    }

    func testThrowingBuilderLeavesThePreviousSnapshot() throws {
        let store = UsageSyncLiveSnapshotStore()
        let good = try HostFixtures.snapshot()
        XCTAssertTrue(store.publish(good))
        struct Boom: Error {}
        XCTAssertFalse(store.publish { throw Boom() })
        XCTAssertEqual(store.latest, good)
    }

    /// Concurrent readers and writers, with the readers asserting that they
    /// only ever observe a whole, valid snapshot.
    func testConcurrentReadsAndWritesAreSafe() throws {
        let store = UsageSyncLiveSnapshotStore()
        let first = try HostFixtures.snapshot()
        let second = try HostFixtures.snapshot([
            HostFixtures.state("Codex", usage: HostFixtures.codexUsage(fiveHourUsed: 70))
        ])
        store.publish(first)

        let iterations = 400
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "store-test", attributes: .concurrent)

        for index in 0..<iterations {
            queue.async(group: group) {
                store.publish(index.isMultiple(of: 2) ? first : second)
            }
            queue.async(group: group) {
                guard let observed = store.latest else { return XCTFail("nil mid-publish") }
                // Whatever is observed must be one of the two whole snapshots,
                // never a mixture of them.
                XCTAssertTrue(observed == first || observed == second)
                do { try UsageSyncValidator.validate(observed) } catch {
                    XCTFail("observed an invalid snapshot: \(error)")
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
    }

    /// Reading never mutates: the source is a value type all the way down, so a
    /// request cannot reach back into desktop state.
    func testServingDoesNotMutateTheStore() throws {
        let store = UsageSyncLiveSnapshotStore()
        let snapshot = try HostFixtures.snapshot()
        store.publish(snapshot)
        for _ in 0..<10 { _ = try store.currentSnapshot() }
        XCTAssertEqual(store.latest, snapshot)
    }

    func testClearRemovesTheServedSnapshot() throws {
        let store = UsageSyncLiveSnapshotStore()
        store.publish(try HostFixtures.snapshot())
        store.clear()
        XCTAssertNil(store.latest)
        XCTAssertThrowsError(try store.currentSnapshot())
    }
}
