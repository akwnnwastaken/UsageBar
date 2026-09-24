import SwiftUI
import UIKit
import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// The single-provider Home Screen widget lists the five-hour *and* the weekly
/// window, each with its own countdown, whenever the snapshot really has them.
final class WeeklyWidgetDetailTests: XCTestCase {
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

    private func measurement(
        headline: String, percent: Int, _ windows: [UsageSyncWindow]
    ) -> UsageSyncMeasurement {
        UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: percent,
            headlineWindowId: headline, windows: windows
        )
    }

    private var fiveHour: UsageSyncWindow {
        window("five-hour", .fiveHour, percent: 100, minutes: 300, resetsIn: 4 * 3600 + 52 * 60)
    }

    private var weekly: UsageSyncWindow {
        window("weekly", .weekly, percent: 100, minutes: 10_080,
               resetsIn: 6 * 86_400 + 13 * 3600 + 12 * 60)
    }

    // MARK: - Which windows

    func testFiveHourAndWeeklyBothAppear() {
        let value = measurement(headline: "five-hour", percent: 100, [fiveHour, weekly])
        XCTAssertEqual(
            WindowPresentation.widgetDetailWindows(in: value).map(\.windowId),
            ["five-hour", "weekly"]
        )
    }

    /// Chosen by kind: a snapshot listing the weekly first still puts the
    /// five-hour row on top.
    func testSelectionIsByKindNotArrayPosition() {
        let value = measurement(headline: "weekly", percent: 100, [weekly, fiveHour])
        XCTAssertEqual(
            WindowPresentation.widgetDetailWindows(in: value).map(\.kind),
            [.fiveHour, .weekly]
        )
    }

    func testFiveHourOnlyGetsNoFabricatedWeeklyRow() {
        let value = measurement(headline: "five-hour", percent: 100, [fiveHour])
        let rows = WindowPresentation.widgetDetailWindows(in: value)
        XCTAssertEqual(rows.map(\.windowId), ["five-hour"])
        XCTAssertFalse(rows.contains { $0.kind == .weekly }, "no weekly row without a weekly window")
    }

    func testWeeklyOnlyStillDisplays() {
        let value = measurement(headline: "weekly", percent: 100, [weekly])
        let rows = WindowPresentation.widgetDetailWindows(in: value)
        XCTAssertEqual(rows.map(\.windowId), ["weekly"])
        XCTAssertEqual(WindowPresentation.microLabel(for: rows[0]), "W")
        XCTAssertEqual(
            SurfaceLinePresentation.windowCountdown(for: rows[0], now: measuredAt),
            "6d 13h 12m left"
        )
    }

    /// Extra windows never crowd out the five-hour and the weekly, and never
    /// push the list past two rows.
    func testFiveHourAndWeeklyOutrankAdditionalWindows() {
        let value = measurement(headline: "duration-4320", percent: 4, [
            window("odd", .unknown, percent: 50, position: 0, resetsIn: 3600),
            window("duration-4320", .duration, percent: 4, minutes: 4_320, resetsIn: 86_400),
            weekly,
            window("weekly-opus", .weeklyScoped, percent: 91, minutes: 10_080, scope: "opus"),
            fiveHour
        ])
        XCTAssertEqual(
            WindowPresentation.widgetDetailWindows(in: value).map(\.windowId),
            ["five-hour", "weekly"]
        )
    }

    /// When only one of the two exists, the spare row goes to the headline
    /// window rather than to a guess — so the big number's window is listed.
    func testSpareRowGoesToTheHeadlineWindowOnly() {
        let value = measurement(headline: "weekly-opus", percent: 91, [
            window("odd", .unknown, percent: 50, position: 0),
            fiveHour,
            window("weekly-opus", .weeklyScoped, percent: 91, minutes: 10_080, scope: "opus")
        ])
        XCTAssertEqual(
            WindowPresentation.widgetDetailWindows(in: value).map(\.windowId),
            ["five-hour", "weekly-opus"]
        )
    }

    /// A headline id that names no window invents no row, and a snapshot with
    /// neither window yields nothing to itemise.
    func testNothingIsInventedWhenWindowsAreAbsent() {
        let empty = measurement(headline: "not-present", percent: 70, [
            window("odd", .unknown, percent: 70, position: 0)
        ])
        XCTAssertTrue(WindowPresentation.widgetDetailWindows(in: empty).isEmpty)
    }

    // MARK: - Weekly countdown

    /// The weekly row keeps every significant component; it is never floored
    /// to its largest unit.
    func testWeeklyCountdownUsesThePreciseSharedPolicy() {
        XCTAssertEqual(SurfaceLinePresentation.windowCountdown(for: weekly, now: measuredAt), "6d 13h 12m left")
        XCTAssertEqual(SurfaceLinePresentation.windowCountdown(for: fiveHour, now: measuredAt), "4h 52m left")

        XCTAssertEqual(
            SurfaceLinePresentation.windowCountdown(for: weekly, now: measuredAt),
            weekly.resetsAt.flatMap { FreshnessPresentation.compactTimeRemaining(until: $0, from: measuredAt) },
            "the row must be the shared ResetRemainder spelling, not a second policy"
        )

        let dayAndMinutes = window("weekly", .weekly, percent: 30, minutes: 10_080,
                                   resetsIn: 86_400 + 2 * 3600 + 14 * 60)
        XCTAssertEqual(SurfaceLinePresentation.windowCountdown(for: dayAndMinutes, now: measuredAt), "1d 2h 14m left")
    }

    /// Each row counts down its own window, against the clock it is given —
    /// which in the widget is the timeline entry's date.
    func testRowCountdownsFallWithTheEntryDate() {
        let later = measuredAt.addingTimeInterval(5 * 60)
        XCTAssertEqual(SurfaceLinePresentation.windowCountdown(for: fiveHour, now: later), "4h 47m left")
        XCTAssertEqual(SurfaceLinePresentation.windowCountdown(for: weekly, now: later), "6d 13h 7m left")
    }

    func testExpiredOrMissingResetDrawsNoCountdown() {
        XCTAssertNil(SurfaceLinePresentation.windowCountdown(
            for: window("weekly", .weekly, percent: 10, minutes: 10_080), now: measuredAt
        ))
        XCTAssertNil(SurfaceLinePresentation.windowCountdown(
            for: window("weekly", .weekly, percent: 10, minutes: 10_080, resetsIn: -60), now: measuredAt
        ))
    }

    // MARK: - Widget wiring

    /// The extension renders the shared content, with the entry's date.
    func testProviderWidgetRendersTheSharedWeeklyAwareContent() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("UsageBarWidgets/WidgetViews.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("ProviderWidgetSmallContent("))
        XCTAssertTrue(source.contains("now: entry.date"))
        XCTAssertFalse(source.contains("Date()"), "widget views format against entry.date only")
        XCTAssertFalse(source.contains("windows.prefix("), "no array-order window selection")
    }

    // MARK: - It fits

    /// Content sizes of the small Home Screen widget, after the system's
    /// default 16pt content margins, on the narrowest and a typical iPhone.
    private static let typicalSmallContent: CGFloat = 158 - 32
    private static let smallestSmallContent: CGFloat = 148 - 32

    @MainActor
    private func naturalHeight(_ view: some View, width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view.fixedSize(horizontal: false, vertical: true))
        return host.sizeThatFits(in: CGSize(width: width, height: 10_000)).height
    }

    private var bothWindows: UsageSyncProvider {
        UsageSyncProvider(
            providerId: UsageProviderID.codex, connected: true, collecting: true,
            measurement: measurement(headline: "five-hour", percent: 100, [fiveHour, weekly])
        )
    }

    /// With both windows, the roomy form fits a typical small widget and the
    /// compact form fits the smallest one — so the weekly is never clipped
    /// away, on any iPhone this app supports.
    @MainActor
    func testBothWindowsFitTheSmallWidget() {
        let content = ProviderWidgetSmallContent(
            providerId: UsageProviderID.codex, provider: bothWindows, now: measuredAt, isStale: true
        )
        let roomy = naturalHeight(content.layout(compact: false), width: Self.typicalSmallContent)
        let compact = naturalHeight(content.layout(compact: true), width: Self.smallestSmallContent)
        XCTAssertLessThanOrEqual(roomy, Self.typicalSmallContent, "roomy form: \(roomy)pt")
        XCTAssertLessThanOrEqual(compact, Self.smallestSmallContent, "compact form: \(compact)pt")
        XCTAssertLessThan(compact, roomy)
    }
}
