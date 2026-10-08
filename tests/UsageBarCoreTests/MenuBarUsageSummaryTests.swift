import XCTest
@testable import UsageBarCore

final class MenuBarUsageSummaryTests: XCTestCase {
    private let providers = ["Claude Code", "Codex"]
    private let reset = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(_ kind: UsageWindowKind, remaining: Int) -> UsageWindow {
        UsageWindow(kind: kind, usedPercent: 100 - remaining, resetsAt: reset, durationMinutes: nil)
    }

    private func usages(_ provider: String, _ windows: [UsageWindow]) -> [String: ProviderUsage] {
        [provider: ProviderUsage(name: provider, windows: windows, error: nil)]
    }

    func testWeeklyAboveAndAtTenIsHiddenWithSessionAvailable() {
        for provider in providers {
            for weekly in [100, 50, 11, 10] {
                let input = usages(provider, [window(.weekly, remaining: weekly), window(.fiveHour, remaining: 80)])
                let summary = MenuBarUsageSummaryCalculator.summary(for: provider, in: input)
                XCTAssertEqual(summary?.windowKind, .fiveHour, provider)
                XCTAssertEqual(summary?.remainingPercent, 80, provider)
                XCTAssertEqual(summary?.resetsAt, reset)
            }
        }
    }

    func testWeeklyOnlyAlwaysFallsBackToActualRemainingPercent() {
        for provider in providers {
            for weekly in [100, 50, 11, 10, 9, 1, 0] {
                let summary = MenuBarUsageSummaryCalculator.summary(
                    for: provider, in: usages(provider, [window(.weekly, remaining: weekly)])
                )
                XCTAssertEqual(summary?.windowKind, .weekly, provider)
                XCTAssertEqual(summary?.remainingPercent, weekly, provider)
                XCTAssertEqual(summary?.resetsAt, reset, provider)
            }
        }
    }

    func testLowWeeklySelectsSessionOnlyWhenStrictlyLower() {
        for provider in providers {
            for session in [0, 8, 9, 10, 80] {
                // Both input orders must give weekly the tie.
                let windows = [window(.weekly, remaining: 9), window(.fiveHour, remaining: session)]
                for ordered in [windows, Array(windows.reversed())] {
                    let summary = MenuBarUsageSummaryCalculator.summary(for: provider, in: usages(provider, ordered))
                    XCTAssertEqual(summary?.windowKind, session < 9 ? .fiveHour : .weekly, provider)
                    XCTAssertEqual(summary?.remainingPercent, min(session, 9), provider)
                }
            }
        }
    }

    func testHiddenWeeklyPreservesProviderSpecificOtherWindowSelection() {
        let windows = [window(.weekly, remaining: 10), window(.fiveHour, remaining: 80),
                       window(.duration(minutes: 60), remaining: 20), window(.weeklyScoped(scope: "opus"), remaining: 30)]
        XCTAssertEqual(MenuBarUsageSummaryCalculator.summary(for: "Claude Code", in: usages("Claude Code", windows))?.windowKind, .fiveHour)
        XCTAssertEqual(MenuBarUsageSummaryCalculator.summary(for: "Codex", in: usages("Codex", windows))?.windowKind, .duration(minutes: 60))
        let otherOnly = Array(windows.dropFirst().dropFirst())
        let claudeFallback = MenuBarUsageSummaryCalculator.summary(for: "Claude Code", in: usages("Claude Code", [windows[0]] + otherOnly))
        XCTAssertEqual(claudeFallback?.windowKind, .weekly)
        XCTAssertEqual(claudeFallback?.remainingPercent, 10)
        XCTAssertEqual(MenuBarUsageSummaryCalculator.summary(for: "Codex", in: usages("Codex", [windows[0]] + otherOnly))?.remainingPercent, 20)
    }

    func testHiddenWeeklyPreservesCodexUnknownWindowSelection() {
        let input = usages("Codex", [window(.weekly, remaining: 50), window(.unknown(position: 0), remaining: 30)])
        let summary = MenuBarUsageSummaryCalculator.summary(for: "Codex", in: input)
        XCTAssertEqual(summary?.windowKind, .unknown(position: 0))
        XCTAssertEqual(summary?.remainingPercent, 30)
    }

    func testLowWeeklyComparisonDoesNotSubstituteOtherKindsForSession() {
        for provider in providers {
            let input = usages(provider, [window(.weekly, remaining: 9), window(.duration(minutes: 60), remaining: 0)])
            XCTAssertEqual(MenuBarUsageSummaryCalculator.summary(for: provider, in: input)?.windowKind, .weekly)
        }
    }

    func testNoWeeklyPreservesExistingPolicyIncludingScopedAndUnknownWindows() {
        let cases: [[UsageWindow]] = [
            [], [window(.fiveHour, remaining: 40)],
            [window(.weeklyScoped(scope: "opus"), remaining: 5)],
            [window(.unknown(position: 0), remaining: 30)],
            [window(.fiveHour, remaining: 60), window(.duration(minutes: 60), remaining: 20)]
        ]
        for provider in providers {
            for windows in cases {
                let input = usages(provider, windows)
                let original = UsageSummaryCalculator.summary(for: provider, in: input)
                let menuBar = MenuBarUsageSummaryCalculator.summary(for: provider, in: input)
                XCTAssertEqual(menuBar?.windowKind, original?.windowKind)
                XCTAssertEqual(menuBar?.remainingPercent, original?.remainingPercent)
            }
            XCTAssertNil(MenuBarUsageSummaryCalculator.summary(for: provider, in: [:]))
        }
    }

    func testMenuBarSelectionLeavesSharedSummaryAndHistoryUnchanged() {
        for provider in providers {
            let input = usages(provider, [window(.fiveHour, remaining: 80), window(.weekly, remaining: 10)])
            XCTAssertEqual(MenuBarUsageSummaryCalculator.summary(for: provider, in: input)?.remainingPercent, 80)
            let original = UsageSummaryCalculator.summary(for: provider, in: input)
            XCTAssertEqual(original?.remainingPercent, provider == "Claude Code" ? 80 : 10)
            let legacy = UsageHistorySample(recordedAt: reset.addingTimeInterval(-120), remainingPercent: 50)
            let recorded = UsageHistoryRecorder.recording([provider: [legacy]], measurements: input, at: reset)
            XCTAssertEqual(recorded["\(provider)|five-hour"]?.last?.remainingPercent, 80)
            XCTAssertEqual(recorded["\(provider)|weekly"]?.last?.remainingPercent, 10)
            XCTAssertEqual(recorded["\(provider)|\(original!.windowKind.historyKey)"]?.first?.remainingPercent, 50)
        }
    }
}
