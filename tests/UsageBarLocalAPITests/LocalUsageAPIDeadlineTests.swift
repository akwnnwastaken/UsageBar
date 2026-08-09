import XCTest
@testable import UsageBarLocalAPI

final class LocalUsageAPIDeadlineTests: XCTestCase {
    func testAbsoluteDeadlineDoesNotResetWhenStartedAgain() {
        let scheduler = ManualDeadlineScheduler()
        let deadline = LocalUsageAPIAbsoluteDeadline(delay: 2, scheduler: scheduler)
        var expirations = 0

        deadline.start { expirations += 1 }
        deadline.start { expirations += 100 }

        XCTAssertEqual(scheduler.scheduledDelays, [2])
        scheduler.fireAll()
        XCTAssertEqual(expirations, 1)
    }

    func testNormalCompletionAndStopCancelDeadline() {
        let scheduler = ManualDeadlineScheduler()
        let deadline = LocalUsageAPIAbsoluteDeadline(delay: 2, scheduler: scheduler)
        var expirations = 0
        deadline.start { expirations += 1 }
        deadline.cancel()
        scheduler.fireAll()
        XCTAssertEqual(expirations, 0)

        deadline.start { expirations += 1 }
        XCTAssertEqual(scheduler.scheduledDelays, [2, 2])
        scheduler.fireAll()
        XCTAssertEqual(expirations, 1)
    }
}

private final class ManualDeadlineScheduler: LocalUsageAPIDeadlineScheduling {
    private(set) var scheduledDelays: [TimeInterval] = []
    private var entries: [(token: ManualDeadlineToken, action: () -> Void)] = []

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) -> LocalUsageAPIDeadlineToken {
        let token = ManualDeadlineToken()
        scheduledDelays.append(delay)
        entries.append((token, action))
        return token
    }

    func fireAll() {
        let current = entries
        entries.removeAll()
        for entry in current where !entry.token.isCancelled {
            entry.action()
        }
    }
}

private final class ManualDeadlineToken: LocalUsageAPIDeadlineToken {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}
