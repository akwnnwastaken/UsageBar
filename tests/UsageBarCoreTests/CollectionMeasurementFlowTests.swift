import XCTest
@testable import UsageBarCore

/// What a refresh cycle is allowed to treat as a measurement.
///
/// The display filter and the usage history both advance from the set of
/// measurements a cycle newly accepted — never from the usage cache. These
/// tests pin that distinction from both ends: a genuine reading still counts,
/// and a retained one never does, however many cycles go by.
final class CollectionMeasurementFlowTests: XCTestCase {
    private let codexWeekly = UsageHistoryRecorder.seriesKey(
        providerName: "Codex",
        windowKind: .weekly
    )
    private let claudeWeekly = UsageHistoryRecorder.seriesKey(
        providerName: "Claude Code",
        windowKind: .weekly
    )
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    private func measurement(
        provider providerName: String,
        remaining: Int,
        at date: Date? = nil
    ) -> ProviderUsage {
        ProviderUsage(
            name: providerName,
            windows: [
                UsageWindow(
                    kind: .weekly,
                    usedPercent: 100 - remaining,
                    resetsAt: nil,
                    durationMinutes: 10_080
                )
            ],
            error: nil
        ).markedSuccessful(at: date ?? origin)
    }

    // MARK: - Display filter

    /// The frozen counterexample. Codex is displaying 33, reads 38 once, and the
    /// filter holds that rise until three consecutive readings confirm it. If
    /// another provider's refreshes could re-feed the cached 38, a rise needing
    /// three measurements would be accepted after two.
    func testAHeldRiseDoesNotAdvanceWhileTheProviderIsPaused() {
        var filter = UsageDisplayFilterState()
        filter.advance(key: codexWeekly, raw: 33)
        filter.advance(key: codexWeekly, raw: 38)

        XCTAssertEqual(filter.displayedValue(forKey: codexWeekly), 33)
        XCTAssertEqual(filter.pendingRise(forKey: codexWeekly), 38)
        XCTAssertEqual(filter.pendingCount(forKey: codexWeekly), 1)

        // Codex is paused. Three Claude-only cycles follow: the accepted set
        // never contains Codex, so nothing about Codex may move.
        for cycle in 0..<3 {
            filter.advance(key: claudeWeekly, raw: 70 - cycle)
        }

        XCTAssertEqual(filter.displayedValue(forKey: codexWeekly), 33)
        XCTAssertEqual(filter.pendingCount(forKey: codexWeekly), 1)
    }

    func testGenuineMeasurementsStillConfirmARiseAfterAResume() {
        var filter = UsageDisplayFilterState()
        filter.advance(key: codexWeekly, raw: 33)
        filter.advance(key: codexWeekly, raw: 38)
        filter.clearPendingRise(forProvider: "Codex")

        // Persistence rebuilds from a clean slate: three consecutive genuine
        // readings, not the one that was already half-proven before the pause.
        filter.advance(key: codexWeekly, raw: 38)
        XCTAssertEqual(filter.displayedValue(forKey: codexWeekly), 33)
        filter.advance(key: codexWeekly, raw: 38)
        XCTAssertEqual(filter.displayedValue(forKey: codexWeekly), 33)
        filter.advance(key: codexWeekly, raw: 38)
        XCTAssertEqual(filter.displayedValue(forKey: codexWeekly), 38)
    }

    func testPausingClearsTheHeldRiseButKeepsWhatIsOnScreen() {
        var filter = UsageDisplayFilterState()
        filter.advance(key: codexWeekly, raw: 33)
        filter.advance(key: codexWeekly, raw: 38)

        filter.clearPendingRise(forProvider: "Codex")

        XCTAssertEqual(filter.displayedValue(forKey: codexWeekly), 33)
        XCTAssertNil(filter.pendingRise(forKey: codexWeekly))
        XCTAssertEqual(filter.pendingCount(forKey: codexWeekly), 0)
    }

    func testDisconnectingForgetsTheDisplayedValueTooAndOnlyForThatProvider() {
        var filter = UsageDisplayFilterState()
        filter.advance(key: codexWeekly, raw: 33)
        filter.advance(key: claudeWeekly, raw: 70)

        filter.forget(provider: "Codex")

        XCTAssertNil(filter.displayedValue(forKey: codexWeekly))
        XCTAssertEqual(filter.displayedValue(forKey: claudeWeekly), 70)
    }

    func testPausingOneProviderLeavesTheOtherHeldRiseAlone() {
        var filter = UsageDisplayFilterState()
        filter.advance(key: claudeWeekly, raw: 70)
        filter.advance(key: claudeWeekly, raw: 75)

        filter.clearPendingRise(forProvider: "Codex")

        XCTAssertEqual(filter.pendingRise(forKey: claudeWeekly), 75)
        XCTAssertEqual(filter.pendingCount(forKey: claudeWeekly), 1)
    }

    // MARK: - History

    func testAnAcceptedMeasurementBecomesASample() {
        let history = UsageHistoryRecorder.recording(
            [:],
            measurements: ["Codex": measurement(provider: "Codex", remaining: 60)],
            at: origin
        )

        XCTAssertEqual(history[codexWeekly]?.count, 1)
        XCTAssertEqual(history[codexWeekly]?.first?.remainingPercent, 60)
    }

    func testACycleThatAcceptedNothingRecordsNothing() {
        let existing = [codexWeekly: [UsageHistorySample(recordedAt: origin, remainingPercent: 60)]]

        let history = UsageHistoryRecorder.recording(
            existing,
            measurements: [:],
            at: origin.addingTimeInterval(600)
        )

        XCTAssertEqual(history[codexWeekly], existing[codexWeekly])
    }

    /// A Claude-only cycle: Codex is paused and its last reading is still on
    /// screen, but the chart must not gain a point nobody measured.
    func testAnotherProvidersCycleAddsNoSampleForTheRetainedOne() {
        let existing = [codexWeekly: [UsageHistorySample(recordedAt: origin, remainingPercent: 60)]]
        let later = origin.addingTimeInterval(600)

        let history = UsageHistoryRecorder.recording(
            existing,
            measurements: ["Claude Code": measurement(provider: "Claude Code", remaining: 70, at: later)],
            at: later
        )

        XCTAssertEqual(history[codexWeekly]?.count, 1)
        XCTAssertEqual(history[claudeWeekly]?.count, 1)
    }

    func testAFailedReadContributesNoSample() {
        let failed = ProviderUsage.unavailable("Codex", .codexUsageUnavailable)

        let history = UsageHistoryRecorder.recording([:], measurements: ["Codex": failed], at: origin)

        XCTAssertTrue(history.isEmpty)
    }

    func testRecordingStillPrunesEverythingOlderThanTheRetentionWindow() {
        let expired = origin.addingTimeInterval(-UsageHistoryModel.retentionInterval - 60)
        let existing = [
            codexWeekly: [UsageHistorySample(recordedAt: expired, remainingPercent: 95)]
        ]

        let history = UsageHistoryRecorder.recording(
            existing,
            measurements: ["Codex": measurement(provider: "Codex", remaining: 60)],
            at: origin
        )

        XCTAssertEqual(history[codexWeekly]?.count, 1)
        XCTAssertEqual(history[codexWeekly]?.first?.remainingPercent, 60)
    }

    /// The all-paused tick: retention is the only thing that runs, and it runs
    /// whether or not anything was collected — a long pause does not stop the
    /// 24-hour clock.
    func testRetentionPrunesWithoutAnyMeasurement() {
        let expired = origin.addingTimeInterval(-UsageHistoryModel.retentionInterval - 60)
        let history = UsageHistoryModel.sanitized(
            [
                codexWeekly: [
                    UsageHistorySample(recordedAt: expired, remainingPercent: 95),
                    UsageHistorySample(recordedAt: origin.addingTimeInterval(-120), remainingPercent: 80)
                ]
            ],
            now: origin
        )

        XCTAssertEqual(history[codexWeekly]?.count, 1)
        XCTAssertEqual(history[codexWeekly]?.first?.remainingPercent, 80)
    }

    func testASeriesRecordedBeforeWindowsWereSeparatedIsMigratedOnce() {
        let legacy = [
            "Codex": [UsageHistorySample(recordedAt: origin.addingTimeInterval(-600), remainingPercent: 90)]
        ]

        let history = UsageHistoryRecorder.recording(
            legacy,
            measurements: ["Codex": measurement(provider: "Codex", remaining: 60)],
            at: origin
        )

        XCTAssertNil(history["Codex"])
        XCTAssertEqual(history[codexWeekly]?.map(\.remainingPercent), [90, 60])
    }
}
