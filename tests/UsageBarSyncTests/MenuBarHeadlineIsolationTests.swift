import XCTest
import UsageBarCore
@testable import UsageBarSync

final class MenuBarHeadlineIsolationTests: XCTestCase {
    func testHiddenWeeklyStillSuppliesSnapshotHeadlineAndWindow() throws {
        for provider in ["Claude Code", "Codex"] {
            let usage = Fixture.accepted(provider, [Fixture.window(.weekly, used: 90, durationMinutes: 10_080)])
            let menuBar = MenuBarUsageSummaryCalculator.summary(for: provider, in: [provider: usage])
            XCTAssertEqual(menuBar?.remainingPercent, 10)
            XCTAssertEqual(menuBar?.windowKind, .weekly)
            let snapshot = try UsageSyncSnapshotBuilder.snapshot(
                from: [Fixture.input(usage, name: provider)], generatedAt: Fixture.generatedAt
            )
            let measurement = try XCTUnwrap(snapshot.providers.first?.measurement)
            XCTAssertEqual(measurement.headlineWindowId, "weekly")
            XCTAssertEqual(measurement.headlineRemainingPercent, 10)
            XCTAssertEqual(measurement.windows.first?.remainingPercent, 10)
        }
    }

    func testLowWeeklyDoesNotChangeClaudeSnapshotSessionPreference() throws {
        let provider = "Claude Code"
        let usage = Fixture.accepted(provider, [
            Fixture.window(.fiveHour, used: 20, durationMinutes: 300),
            Fixture.window(.weekly, used: 91, durationMinutes: 10_080)
        ])
        XCTAssertEqual(MenuBarUsageSummaryCalculator.summary(for: provider, in: [provider: usage])?.remainingPercent, 9)
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(usage, name: provider)], generatedAt: Fixture.generatedAt
        )
        let measurement = try XCTUnwrap(snapshot.providers.first?.measurement)
        XCTAssertEqual(measurement.headlineWindowId, "five-hour")
        XCTAssertEqual(measurement.headlineRemainingPercent, 80)
        XCTAssertEqual(measurement.windows.count, 2)
    }
}
