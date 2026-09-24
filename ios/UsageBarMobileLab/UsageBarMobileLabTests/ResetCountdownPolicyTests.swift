import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// The precise reset countdown, pinned instant by instant.
///
/// The policy this replaced rendered the largest whole unit and discarded the
/// rest, so "2h 59m" reached every surface as "2h left". Flooring to one unit
/// never overstates the time left, but it throws away up to an hour — or up to
/// a day — of real interval, which is exactly the part a person deciding
/// whether to keep working needs.
final class ResetCountdownPolicyTests: XCTestCase {
    private let reset = Date(timeIntervalSince1970: 1_772_000_000)

    private func spaced(_ seconds: TimeInterval) -> String? {
        FreshnessPresentation.compactTimeRemaining(until: reset, from: reset.addingTimeInterval(-seconds))
    }

    private func tight(_ seconds: TimeInterval) -> String? {
        FreshnessPresentation.tightTimeRemaining(until: reset, from: reset.addingTimeInterval(-seconds))
    }

    private func spoken(_ seconds: TimeInterval) -> String? {
        FreshnessPresentation.spokenTimeRemaining(until: reset, from: reset.addingTimeInterval(-seconds))
    }

    // MARK: - The table

    func testEveryPinnedIntervalRendersItsSignificantComponents() {
        XCTAssertEqual(spaced(30), "1m left", "a live window never reads as zero")
        XCTAssertEqual(spaced(60), "1m left")
        XCTAssertEqual(spaced(17 * 60), "17m left")
        XCTAssertEqual(spaced(59 * 60), "59m left")
        XCTAssertEqual(spaced(60 * 60), "1h left", "a zero minute component is noise")
        XCTAssertEqual(spaced(61 * 60), "1h 1m left")
        XCTAssertEqual(spaced(67 * 60), "1h 7m left")
        XCTAssertEqual(spaced(179 * 60), "2h 59m left")
        XCTAssertEqual(spaced((23 * 60 + 41) * 60), "23h 41m left")
        XCTAssertEqual(spaced((23 * 60 + 59) * 60), "23h 59m left")
        XCTAssertEqual(spaced(24 * 3600), "1d left")
        XCTAssertEqual(spaced(24 * 3600 + 60), "1d 1m left", "zero hours are dropped, minutes are not")
        XCTAssertEqual(spaced(27 * 3600), "1d 3h left")
        XCTAssertEqual(spaced(27 * 3600 + 14 * 60), "1d 3h 14m left")
        XCTAssertEqual(spaced(3 * 24 * 3600), "3d left")
    }

    /// The regression this checkpoint exists to remove, stated on its own so it
    /// cannot be lost in a table.
    func testTwoHoursFiftyNineNeverRendersAsTwoHours() throws {
        let text = try XCTUnwrap(spaced(179 * 60))
        XCTAssertEqual(text, "2h 59m left")
        XCTAssertNotEqual(text, "2h left")
        XCTAssertTrue(text.contains("59m"), "the minutes must survive")

        let compact = try XCTUnwrap(tight(179 * 60))
        XCTAssertEqual(compact, "2h59m")
        XCTAssertNotEqual(compact, "2h")
        XCTAssertTrue(compact.contains("59"), "a constrained surface spends spaces, not components")
    }

    /// A multi-day interval keeps its hours and minutes too.
    func testMultiDayIntervalsKeepTheirRemainder() throws {
        let text = try XCTUnwrap(spaced(3 * 24 * 3600 + 21 * 3600 + 14 * 60))
        XCTAssertEqual(text, "3d 21h 14m left")
        XCTAssertNotEqual(text, "3d left")
        XCTAssertEqual(tight(3 * 24 * 3600 + 21 * 3600 + 14 * 60), "3d21h14m")
    }

    // MARK: - Boundaries

    func testExpiredAndAbsentResetsRenderNothing() {
        XCTAssertNil(FreshnessPresentation.compactTimeRemaining(until: reset, from: reset))
        XCTAssertNil(FreshnessPresentation.tightTimeRemaining(until: reset, from: reset))
        XCTAssertNil(
            FreshnessPresentation.compactTimeRemaining(until: reset, from: reset.addingTimeInterval(1))
        )
        XCTAssertNil(
            FreshnessPresentation.compactTimeRemaining(until: reset, from: reset.addingTimeInterval(86_400))
        )

        let openEnded = UsageSyncWindow(
            windowId: "weekly", kind: .weekly, scope: nil, durationMinutes: 10_080,
            remainingPercent: 81, resetsAt: nil
        )
        XCTAssertNil(FreshnessPresentation.resetSummary(for: openEnded, now: reset))
        XCTAssertNil(FreshnessPresentation.spokenResetSummary(for: openEnded, now: reset))
    }

    /// Seconds are floored, because the UI promises minute resolution — but
    /// only the seconds are.
    func testSecondsAreFlooredAndNothingElseIs() {
        XCTAssertEqual(spaced(179 * 60 + 59), "2h 59m left", "the trailing 59 seconds are dropped")
        XCTAssertEqual(spaced(180 * 60), "3h left")
        XCTAssertEqual(spaced(60 * 60 - 1), "59m left")
    }

    // MARK: - Spoken form

    func testSpokenFormIsASentenceWithCorrectPlurals() {
        XCTAssertEqual(spoken(60), "1 minute")
        XCTAssertEqual(spoken(179 * 60), "2 hours 59 minutes")
        XCTAssertEqual(spoken(24 * 3600), "1 day")
        XCTAssertEqual(spoken(25 * 3600 + 60), "1 day 1 hour 1 minute")
        XCTAssertEqual(spoken(3 * 24 * 3600 + 2 * 3600 + 30 * 60), "3 days 2 hours 30 minutes")
    }

    // MARK: - One policy, every surface

    /// Every mobile surface derives its countdown from the same remainder, so
    /// none can drift back to a coarser spelling on its own.
    func testEverySurfaceKeepsTheMinutesOfTheSameInterval() throws {
        let measuredAt = reset.addingTimeInterval(-6 * 3600)
        let measurement = UsageSyncMeasurement(
            measuredAt: measuredAt,
            headlineRemainingPercent: 39,
            headlineWindowId: "five-hour",
            windows: [
                UsageSyncWindow(
                    windowId: "five-hour", kind: .fiveHour, scope: nil, durationMinutes: 300,
                    remainingPercent: 39, resetsAt: reset
                )
            ]
        )
        let now = reset.addingTimeInterval(-(4 * 3600 + 59 * 60))

        // Dashboard headline line.
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowLine(in: measurement, now: now),
            "5 Hour · 4h 59m left"
        )
        // Dashboard detail row.
        let row = try XCTUnwrap(
            FreshnessPresentation.resetSummary(for: measurement.windows[0], now: now)
        )
        XCTAssertTrue(row.hasPrefix("Resets in 4h 59m · "), row)
        // Lock Screen inline.
        XCTAssertEqual(
            SurfaceLinePresentation.inline(
                name: "Claude", percent: 39, measurement: measurement, now: now
            ),
            "Claude 39% · 4h59m"
        )
        // Lock Screen rectangular footer.
        XCTAssertEqual(
            SurfaceLinePresentation.accessoryFooter(of: measurement, now: now),
            "4h59m left · 1h ago"
        )
        // Overview row suffix.
        XCTAssertEqual(
            SurfaceLinePresentation.countdownSuffix(in: measurement, now: now), "· 4h59m"
        )
        // Control Center.
        let control = UsageControlValue(availability: .live, headlines: [
            UsageControlHeadline(
                providerId: UsageProviderID.claude,
                remainingPercent: 39,
                measuredAt: measuredAt,
                windowLabel: "5H",
                resetsAt: reset
            )
        ])
        XCTAssertEqual(
            ControlPresentation.providerTitle(
                for: control, providerId: UsageProviderID.claude, now: now
            ),
            "Claude 5H 39% · 4h59m"
        )

        // None of them may render the old coarse value.
        for text in [
            SurfaceLinePresentation.headlineWindowLine(in: measurement, now: now),
            row,
            SurfaceLinePresentation.inline(name: "Claude", percent: 39, measurement: measurement, now: now),
            SurfaceLinePresentation.accessoryFooter(of: measurement, now: now),
            SurfaceLinePresentation.countdownSuffix(in: measurement, now: now),
            ControlPresentation.providerTitle(for: control, providerId: UsageProviderID.claude, now: now)
        ] {
            let value = try XCTUnwrap(text)
            XCTAssertTrue(value.contains("59"), "\(value) lost the minutes of a 4h59m interval")
        }
    }
}
