import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// What the redesigned Home Screen widgets are allowed to say.
final class WidgetContentTests: XCTestCase {
    private let measuredAt = Date(timeIntervalSince1970: 1_772_000_000)

    private func window(
        _ id: String, _ kind: UsageSyncWindowKind, percent: Int,
        minutes: Int? = nil, scope: String? = nil, position: Int? = nil,
        resetsIn: TimeInterval? = nil
    ) -> UsageSyncWindow {
        UsageSyncWindow(
            windowId: id, kind: kind, scope: scope, durationMinutes: minutes,
            position: position, remainingPercent: percent,
            resetsAt: resetsIn.map { measuredAt.addingTimeInterval($0) }
        )
    }

    // MARK: - Compact row labels

    func testMicroLabelsMapToTheirWindowKind() {
        XCTAssertEqual(
            WindowPresentation.microLabel(for: window("five-hour", .fiveHour, percent: 79, minutes: 300)),
            "5H"
        )
        XCTAssertEqual(
            WindowPresentation.microLabel(for: window("weekly", .weekly, percent: 12, minutes: 10_080)),
            "W"
        )
        XCTAssertEqual(
            WindowPresentation.microLabel(
                for: window("weekly-opus", .weeklyScoped, percent: 91, minutes: 10_080, scope: "opus")
            ),
            "Opus",
            "a scoped weekly keeps its scope; two rows both reading 'W' would be worse than none"
        )
        XCTAssertEqual(
            WindowPresentation.microLabel(
                for: window("weekly-scoped", .weeklyScoped, percent: 91, minutes: 10_080, scope: nil)
            ),
            "W"
        )
        XCTAssertEqual(
            WindowPresentation.microLabel(
                for: window("duration-4320", .duration, percent: 45, minutes: 4_320)
            ),
            "3D"
        )
        XCTAssertEqual(
            WindowPresentation.microLabel(for: window("odd", .unknown, percent: 50, position: 0)),
            "L"
        )
    }

    /// A micro label never fabricates a window identity it does not have.
    func testMicroLabelDegradesWithoutADuration() {
        XCTAssertEqual(
            WindowPresentation.microLabel(for: window("duration-x", .duration, percent: 50)),
            "L"
        )
    }

    // MARK: - No redundant repetition

    /// The column names the headline window once, in full; the rows beneath it
    /// use the short form. The two must not be the same string.
    func testDetailRowsDoNotRepeatTheFullHeadlineWindowText() {
        let fiveHour = window("five-hour", .fiveHour, percent: 79, minutes: 300, resetsIn: 4 * 3600)
        let measurement = UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 79,
            headlineWindowId: "five-hour",
            windows: [fiveHour, window("weekly", .weekly, percent: 12, minutes: 10_080)]
        )
        let headline = SurfaceLinePresentation.headlineWindowLine(in: measurement, now: measuredAt)
        XCTAssertEqual(headline, "5 Hour · 4h left")
        XCTAssertEqual(WindowPresentation.microLabel(for: fiveHour), "5H")
        XCTAssertNotEqual(WindowPresentation.microLabel(for: fiveHour), "5 Hour")
        XCTAssertFalse(
            WindowPresentation.microLabel(for: fiveHour).contains("Hour"),
            "the row must not restate what the headline line already said"
        )
    }

    /// The widget rows compose from the micro label, and no widget surface
    /// reaches for the full prose label at all.
    func testWidgetRowsUseTheMicroLabelAndNeverTheProseLabel() throws {
        func source(_ path: String) throws -> String {
            try String(
                contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent(path),
                encoding: .utf8
            )
        }
        let shared = try source("Shared/ProviderPresentation.swift")
        XCTAssertTrue(
            shared.contains("WindowPresentation.microLabel(for: window)"),
            "the shared widget row must use the micro label"
        )
        XCTAssertFalse(
            try source("UsageBarWidgets/WidgetViews.swift").contains("WindowPresentation.label(for:"),
            "a widget surface must not print the full window prose"
        )
    }

    // MARK: - Nothing else regressed

    /// Both providers survive the overview redesign, each with its own
    /// headline, percentage and countdown.
    func testOverviewKeepsBothProvidersAndTheirOwnCountdowns() throws {
        let snapshot = try TestFixtures.paritySnapshot("basic")
        XCTAssertEqual(snapshot.providers.count, 2)

        let codex = try XCTUnwrap(snapshot.providers.first { $0.providerId == UsageProviderID.codex })
        let claude = try XCTUnwrap(snapshot.providers.first { $0.providerId == UsageProviderID.claude })
        let codexMeasurement = try XCTUnwrap(codex.measurement)
        let claudeMeasurement = try XCTUnwrap(claude.measurement)

        XCTAssertEqual(codexMeasurement.headlineRemainingPercent, 64)
        XCTAssertEqual(claudeMeasurement.headlineRemainingPercent, 52)

        let now = try XCTUnwrap(HeadlinePresentation.resetsAt(in: codexMeasurement))
            .addingTimeInterval(-(2 * 3600 + 37 * 60))
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowLine(in: codexMeasurement, now: now),
            "5 Hour · 2h 37m left",
            "the widget countdown must stay precise"
        )
        XCTAssertNotEqual(
            SurfaceLinePresentation.countdownSuffix(in: codexMeasurement, now: now),
            SurfaceLinePresentation.countdownSuffix(in: claudeMeasurement, now: now),
            "each provider counts down its own headline window"
        )
    }

    /// Percentages reach the widget exactly as the snapshot stated them; the
    /// colour policy reads them and never rewrites them.
    func testRemainingPercentagesAreUnchangedByPresentation() throws {
        let snapshot = try TestFixtures.paritySnapshot("basic")
        let codex = try XCTUnwrap(snapshot.providers.first { $0.providerId == UsageProviderID.codex })
        let measurement = try XCTUnwrap(codex.measurement)
        XCTAssertEqual(measurement.windows.map(\.remainingPercent), [64, 81])
        for value in measurement.windows.map(\.remainingPercent) {
            XCTAssertEqual(UsageLevelPresentation.displayPercent(value), value)
        }
    }

    /// Freshness is still `measuredAt`, and still not the reset.
    func testWidgetFreshnessComesFromMeasuredAt() throws {
        let measurement = UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 79,
            headlineWindowId: "five-hour",
            windows: [window("five-hour", .fiveHour, percent: 79, minutes: 300, resetsIn: 6 * 3600)]
        )
        let now = measuredAt.addingTimeInterval(3 * 3600)
        XCTAssertEqual(FreshnessPresentation.age(of: measurement, now: now), "Updated 3 hr ago")
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowLine(in: measurement, now: now),
            "5 Hour · 3h left",
            "a reset three hours out must not make a three-hour-old reading look fresh"
        )
    }

    /// A window with no reset renders a label and no countdown, and a headline
    /// id naming an absent window fabricates nothing.
    func testMissingResetAndMissingWindowDegradeCleanly() {
        let noReset = UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 79,
            headlineWindowId: "five-hour",
            windows: [window("five-hour", .fiveHour, percent: 79, minutes: 300)]
        )
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowLine(in: noReset, now: measuredAt), "5 Hour"
        )
        XCTAssertNil(SurfaceLinePresentation.countdownSuffix(in: noReset, now: measuredAt))

        let absent = UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 79,
            headlineWindowId: "not-present",
            windows: [window("five-hour", .fiveHour, percent: 79, minutes: 300, resetsIn: 3600)]
        )
        XCTAssertNil(SurfaceLinePresentation.headlineWindowLine(in: absent, now: measuredAt))
        XCTAssertNil(HeadlinePresentation.compactLabel(in: absent))
    }

    /// Control Center is untouched by the widget redesign.
    func testControlCenterStillReadsProviderWindowPercentAndTightCountdown() {
        let reset = measuredAt.addingTimeInterval(4 * 3600 + 6 * 60)
        let value = UsageControlValue(availability: .live, headlines: [
            UsageControlHeadline(
                providerId: UsageProviderID.claude, remainingPercent: 79,
                measuredAt: measuredAt, windowLabel: "5H", resetsAt: reset
            )
        ])
        XCTAssertEqual(
            ControlPresentation.providerTitle(
                for: value, providerId: UsageProviderID.claude, now: measuredAt
            ),
            "Claude 5H 79% · 4h6m"
        )
    }
}
