import XCTest
import UsageBarPairing
@testable import UsageBarMobileSyncHost

/// The narrowness of the pairing window is the defence, so these test the
/// narrowness rather than the happy path.
final class PairingSessionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_772_000_000)

    func testGeneratedCodeIs256Bits() {
        let store = MobileSyncPairingSessionStore()
        XCTAssertEqual(store.start(now: start).code.bitCount, 256)
    }

    func testDefaultLifetimeIsAtMostTwoMinutes() {
        XCTAssertLessThanOrEqual(MobileSyncPairingSession.defaultLifetime, 120)
        XCTAssertLessThanOrEqual(MobileSyncPairingSession.maximumFailedAttempts, 8)
    }

    func testSessionExpires() {
        let store = MobileSyncPairingSessionStore(lifetime: 60)
        let session = store.start(now: start)
        XCTAssertNotNil(store.current(now: start.addingTimeInterval(59)))
        XCTAssertNil(store.current(now: start.addingTimeInterval(60)))
        XCTAssertEqual(
            store.consume(presented: session.code, now: start.addingTimeInterval(61)),
            .rejected
        )
    }

    func testSuccessConsumesTheSession() {
        let store = MobileSyncPairingSessionStore()
        let session = store.start(now: start)
        XCTAssertEqual(store.consume(presented: session.code, now: start), .paired)
        XCTAssertNil(store.current(now: start))
    }

    /// The whole point of "one-time".
    func testReplayIsRejected() {
        let store = MobileSyncPairingSessionStore()
        let session = store.start(now: start)
        XCTAssertEqual(store.consume(presented: session.code, now: start), .paired)
        XCTAssertEqual(store.consume(presented: session.code, now: start), .rejected)
        XCTAssertEqual(store.consume(presented: session.code, now: start), .rejected)
    }

    /// Two callers racing the same valid code: exactly one may win, because the
    /// check and the consume share one critical section.
    func testConcurrentRedemptionIssuesExactlyOnce() {
        let store = MobileSyncPairingSessionStore()
        let session = store.start(now: start)
        let lock = NSLock()
        var successes = 0
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "pair-race", attributes: .concurrent)
        for _ in 0..<64 {
            queue.async(group: group) {
                if store.consume(presented: session.code, now: self.start) == .paired {
                    lock.lock(); successes += 1; lock.unlock()
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(successes, 1)
    }

    /// Pressing "Pair iPhone" again means the previous attempt is abandoned.
    /// Leaving the old code live would keep a window open the owner believes
    /// they closed.
    func testNewSessionInvalidatesTheOldOne() {
        let store = MobileSyncPairingSessionStore()
        let first = store.start(now: start)
        let second = store.start(now: start)
        XCTAssertEqual(store.consume(presented: first.code, now: start), .rejected)
        XCTAssertEqual(store.consume(presented: second.code, now: start), .paired)
    }

    func testCancelInvalidatesTheSession() {
        let store = MobileSyncPairingSessionStore()
        let session = store.start(now: start)
        store.cancel()
        XCTAssertNil(store.current(now: start))
        XCTAssertEqual(store.consume(presented: session.code, now: start), .rejected)
    }

    /// The session lives in memory only. A fresh store — which is what a
    /// relaunched process has — knows nothing about a previous one.
    func testSessionDoesNotSurviveANewStore() {
        let first = MobileSyncPairingSessionStore()
        let session = first.start(now: start)
        let afterRestart = MobileSyncPairingSessionStore()
        XCTAssertNil(afterRestart.current(now: start))
        XCTAssertEqual(afterRestart.consume(presented: session.code, now: start), .rejected)
    }

    /// An online guessing attempt gets one short burst, not an unlimited one.
    func testFailedAttemptCeilingInvalidatesTheSession() {
        let store = MobileSyncPairingSessionStore(attemptCeiling: 3)
        let session = store.start(now: start)
        for _ in 0..<3 {
            XCTAssertEqual(store.consume(presented: .generate(), now: start), .rejected)
        }
        XCTAssertNil(store.current(now: start), "the ceiling must close the window")
        XCTAssertEqual(store.consume(presented: session.code, now: start), .rejected)
    }

    func testSuccessResetsTheAttemptCounterForTheNextSession() {
        let store = MobileSyncPairingSessionStore(attemptCeiling: 3)
        _ = store.start(now: start)
        XCTAssertEqual(store.consume(presented: .generate(), now: start), .rejected)
        XCTAssertEqual(store.consume(presented: .generate(), now: start), .rejected)
        let session = store.start(now: start)
        // Two more failures would have hit the old ceiling; the new session
        // starts from zero.
        XCTAssertEqual(store.consume(presented: .generate(), now: start), .rejected)
        XCTAssertEqual(store.consume(presented: .generate(), now: start), .rejected)
        XCTAssertEqual(store.consume(presented: session.code, now: start), .paired)
    }

    /// The pairing code is never written into the durable auth record — that
    /// record holds digests of a *different* secret entirely.
    func testPairingCodeNeverEntersThePersistentAuthRecord() throws {
        let store = MobileSyncPairingSessionStore()
        let session = store.start(now: start)
        let authStore = InMemoryMobileSyncAuthStore()
        let service = MobileSyncService(
            authStore: authStore,
            pairing: store,
            source: UsageSyncLiveSnapshotStore(initial: try HostFixtures.snapshot()),
            now: { self.start }
        )
        _ = service.respond(to: HostRequests.pair(code: session.code.encoded))

        let record = try XCTUnwrap(authStore.load())
        let encoded = String(decoding: record.encoded(), as: UTF8.self)
        XCTAssertFalse(encoded.contains(session.code.encoded))
    }

    func testRemainingCountsDown() {
        let store = MobileSyncPairingSessionStore(lifetime: 120)
        let session = store.start(now: start)
        XCTAssertEqual(session.remaining(at: start), 120)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(90)), 30)
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(300)), 0)
    }
}
