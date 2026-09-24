import SwiftUI
import UIKit
import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// The two overview widgets speak the same visual language as the
/// single-provider widget: the medium one *is* that widget twice, and the
/// small one stacks two compact summaries of each provider's headline window.
final class OverviewWidgetTests: XCTestCase {
    private let measuredAt = Date(timeIntervalSince1970: 1_772_000_000)

    private func window(
        _ id: String, _ kind: UsageSyncWindowKind, percent: Int,
        minutes: Int? = nil, scope: String? = nil, resetsIn: TimeInterval? = nil
    ) -> UsageSyncWindow {
        UsageSyncWindow(
            windowId: id, kind: kind, scope: scope, durationMinutes: minutes,
            remainingPercent: percent,
            resetsAt: resetsIn.map { measuredAt.addingTimeInterval($0) }
        )
    }

    private func provider(
        _ id: String, headline: String, percent: Int, _ windows: [UsageSyncWindow]
    ) -> UsageSyncProvider {
        UsageSyncProvider(
            providerId: id, connected: true, collecting: true,
            measurement: UsageSyncMeasurement(
                measuredAt: measuredAt, headlineRemainingPercent: percent,
                headlineWindowId: headline, windows: windows
            )
        )
    }

    private var fiveHour: UsageSyncWindow {
        window("five-hour", .fiveHour, percent: 93, minutes: 300, resetsIn: 3600 + 31 * 60)
    }

    private var weekly: UsageSyncWindow {
        window("weekly", .weekly, percent: 99, minutes: 10_080, resetsIn: 6 * 86_400 + 20 * 3600 + 31 * 60)
    }

    private var slots: [WidgetProviderSlot] {
        [
            WidgetProviderSlot(id: UsageProviderID.codex, provider: provider(
                UsageProviderID.codex, headline: "five-hour", percent: 93, [fiveHour, weekly]
            )),
            WidgetProviderSlot(id: UsageProviderID.claude, provider: provider(
                UsageProviderID.claude, headline: "five-hour", percent: 34, [
                    window("weekly", .weekly, percent: 6, minutes: 10_080, resetsIn: 3 * 86_400 + 4 * 3600 + 14 * 60),
                    window("five-hour", .fiveHour, percent: 34, minutes: 300, resetsIn: 4 * 60)
                ]
            ))
        ]
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func sharedSection(from start: String, to end: String) throws -> String {
        let text = try source("Shared/ProviderPresentation.swift")
        let lower = try XCTUnwrap(text.range(of: start))
        let upper = try XCTUnwrap(text.range(of: end, range: lower.upperBound..<text.endIndex))
        return String(text[lower.lowerBound..<upper.lowerBound])
    }

    // MARK: - Small overview: the true headline window, precisely

    /// Each summary names the desktop's chosen headline window in full with
    /// its own precise countdown — resolved by id, whatever its position.
    func testSmallSummaryResolvesTheTrueHeadlineWindow() {
        let weeklyHeadline = UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 6, headlineWindowId: "weekly",
            windows: [fiveHour, window("weekly", .weekly, percent: 6, minutes: 10_080,
                                       resetsIn: 3 * 86_400 + 4 * 3600 + 14 * 60)]
        )
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowParts(in: weeklyHeadline, now: measuredAt),
            .init(name: "Weekly", countdown: "3d 4h 14m left"),
            "a weekly headline is shown as the weekly, never assumed to be the five-hour"
        )

        let durationHeadline = UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 4, headlineWindowId: "duration-4320",
            windows: [weekly, window("duration-4320", .duration, percent: 4, minutes: 4_320,
                                     resetsIn: 2 * 86_400 + 3 * 3600 + 14 * 60), fiveHour]
        )
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowParts(in: durationHeadline, now: measuredAt),
            .init(name: "3 Day", countdown: "2d 3h 14m left")
        )
    }

    /// Minute precision survives: four minutes reads "4m left", and an hour
    /// and a half is not floored to "1h".
    func testSmallSummaryCountdownIsMinutePrecise() {
        let value = UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 93, headlineWindowId: "five-hour",
            windows: [fiveHour]
        )
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowParts(in: value, now: measuredAt)?.countdown,
            "1h 31m left"
        )
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowParts(in: value, now: measuredAt.addingTimeInterval(87 * 60))?.countdown,
            "4m left"
        )
    }

    private var scopedWeekly: UsageSyncMeasurement {
        UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 100, headlineWindowId: "weekly-opus",
            windows: [fiveHour, window("weekly-opus", .weeklyScoped, percent: 100, minutes: 10_080, scope: "opus",
                                       resetsIn: 6 * 86_400 + 23 * 3600 + 59 * 60)]
        )
    }

    private var threeDay: UsageSyncMeasurement {
        UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 4, headlineWindowId: "duration-4320",
            windows: [fiveHour, weekly, window("duration-4320", .duration, percent: 4, minutes: 4_320,
                                               resetsIn: 2 * 86_400 + 3 * 3600 + 14 * 60)]
        )
    }

    private func parts(
        _ measurement: UsageSyncMeasurement, _ tier: SurfaceLinePresentation.LineTier
    ) -> SurfaceLinePresentation.WindowLineParts? {
        SurfaceLinePresentation.headlineWindowParts(in: measurement, now: measuredAt, tier: tier)
    }

    /// The whole fallback chain for the hardest case, tier by tier: words go,
    /// then spaces, then the scope, then the name — the countdown's
    /// components never do.
    func testScopedWeeklyFallbackChainKeepsTheWholeCountdown() {
        XCTAssertEqual(parts(scopedWeekly, .full), .init(name: "Weekly · Opus", countdown: "6d 23h 59m left"))
        XCTAssertEqual(parts(scopedWeekly, .short), .init(name: "Opus", countdown: "6d 23h 59m left"))
        XCTAssertEqual(parts(scopedWeekly, .shortTight), .init(name: "Opus", countdown: "6d23h59m"))
        XCTAssertEqual(parts(scopedWeekly, .markerTight), .init(name: "W", countdown: "6d23h59m"))
        XCTAssertEqual(parts(scopedWeekly, .countdownOnly), .init(name: nil, countdown: "6d23h59m"))
    }

    /// Every tier's countdown is exactly the shared ResetRemainder spelling —
    /// spaced or tight — so no tier can drop or round a component.
    func testEveryTierCountdownIsTheCompleteSharedSpelling() throws {
        for measurement in [scopedWeekly, threeDay] {
            let resetsAt = try XCTUnwrap(HeadlinePresentation.resetsAt(in: measurement))
            let remainder = try XCTUnwrap(ResetRemainder(until: resetsAt, from: measuredAt))
            for tier in SurfaceLinePresentation.LineTier.allCases {
                let countdown = try XCTUnwrap(parts(measurement, tier)?.countdown, "\(tier)")
                XCTAssertTrue(
                    countdown == "\(remainder.spaced) left" || countdown == remainder.tight,
                    "\(tier) spelled \(countdown)"
                )
                XCTAssertFalse(countdown.contains("…"))
            }
        }
        XCTAssertEqual(parts(threeDay, .full)?.countdown, "2d 3h 14m left")
        XCTAssertEqual(parts(threeDay, .countdownOnly)?.countdown, "2d3h14m")
    }

    /// No tier ever names a window as something it is not — a weekly or a
    /// three-day limit never becomes a "5 Hour".
    func testNoTierSubstitutesAFiveHourLabel() {
        for tier in SurfaceLinePresentation.LineTier.allCases {
            let weeklyName = parts(scopedWeekly, tier)?.name
            let durationName = parts(threeDay, tier)?.name
            XCTAssertTrue([nil, "Weekly · Opus", "Opus", "W"].contains(weeklyName), "\(tier): \(String(describing: weeklyName))")
            XCTAssertTrue([nil, "3 Day", "3D"].contains(durationName), "\(tier): \(String(describing: durationName))")
        }
        XCTAssertEqual(parts(threeDay, .markerTight), .init(name: "3D", countdown: "2d3h14m"))
    }

    /// VoiceOver always hears the full window identity and the full countdown,
    /// whichever tier is drawn.
    func testAccessibilityCarriesTheFullIdentityAndCountdown() {
        XCTAssertEqual(
            SurfaceLinePresentation.spokenHeadlineWindowLine(in: scopedWeekly, now: measuredAt),
            "Weekly · Opus, 6 days 23 hours 59 minutes left"
        )
        XCTAssertEqual(
            SurfaceLinePresentation.spokenHeadlineWindowLine(in: threeDay, now: measuredAt),
            "3 Day, 2 days 3 hours 14 minutes left"
        )
    }

    /// A headline id naming a window the snapshot does not carry yields no
    /// line at all, and the composed string still agrees with the parts.
    func testMissingHeadlineWindowInventsNothing() {
        let absent = UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 70, headlineWindowId: "not-present",
            windows: [fiveHour]
        )
        XCTAssertNil(SurfaceLinePresentation.headlineWindowParts(in: absent, now: measuredAt))
        XCTAssertNil(SurfaceLinePresentation.headlineWindowLine(in: absent, now: measuredAt))

        let present = UsageSyncMeasurement(
            measuredAt: measuredAt, headlineRemainingPercent: 93, headlineWindowId: "five-hour",
            windows: [fiveHour]
        )
        XCTAssertEqual(SurfaceLinePresentation.headlineWindowLine(in: present, now: measuredAt), "5 Hour · 1h 31m left")
    }

    /// The small summary lists the headline only: it never reaches for the
    /// detail-window selection, so it cannot grow a weekly row it has no room
    /// for, and nothing in the overview code orders windows by position.
    func testSmallSummaryShowsTheHeadlineOnlyAndNoPositionalWindows() throws {
        let summary = try sharedSection(
            from: "public struct OverviewProviderSummary", to: "public struct WidgetProviderSlot"
        )
        XCTAssertTrue(summary.contains("SurfaceLinePresentation.headlineWindowParts"))
        XCTAssertFalse(summary.contains("widgetDetailWindows"), "no second window in the small overview")
        XCTAssertFalse(summary.contains("windows.first"))
        XCTAssertFalse(summary.contains("windows["))

        let overview = try sharedSection(
            from: "public struct OverviewProviderSummary", to: "public struct WidgetHeadlineValue"
        )
        XCTAssertFalse(overview.contains("windows.prefix("))
        XCTAssertFalse(overview.contains(".tertiary"), "no faint tertiary text in the overview widgets")
        XCTAssertFalse(try source("UsageBarWidgets/WidgetViews.swift").contains("windows.prefix("))
    }

    // MARK: - Medium overview: the single-provider widget, twice

    /// Each medium column is the approved single-provider widget itself, so
    /// its five-hour and weekly blocks — full names, own countdowns, bars —
    /// and its by-kind selection are exactly that widget's.
    func testMediumColumnsReuseTheSingleProviderWidget() throws {
        let medium = try sharedSection(
            from: "public struct OverviewMediumContent", to: "public struct WidgetHeadlineValue"
        )
        XCTAssertTrue(medium.contains("ProviderWidgetSmallContent("))
        XCTAssertTrue(medium.contains("Divider()"))

        let widget = try source("UsageBarWidgets/WidgetViews.swift")
        XCTAssertTrue(widget.contains("OverviewMediumContent(providers: slots, now: entry.date"))
        XCTAssertTrue(widget.contains("OverviewSmallContent(providers: slots, now: entry.date"))
        XCTAssertFalse(widget.contains("Text(\"UsageBar\").font(.caption.weight(.semibold))"),
                       "the global title no longer spends the overview's height")
    }

    /// What each medium column lists: five-hour then weekly by kind, each with
    /// its own precise countdown from the shared policy.
    func testMediumColumnsListFiveHourAndWeeklyWithTheirOwnCountdowns() throws {
        let claude = try XCTUnwrap(slots[1].provider?.measurement)
        let rows = WindowPresentation.widgetDetailWindows(in: claude)
        XCTAssertEqual(rows.map(\.kind), [.fiveHour, .weekly], "by kind, though the snapshot lists weekly first")
        XCTAssertEqual(rows.map(WindowPresentation.label(for:)), ["5 Hour", "Weekly"])
        XCTAssertEqual(
            rows.map { SurfaceLinePresentation.windowCountdown(for: $0, now: measuredAt) },
            ["4m left", "3d 4h 14m left"]
        )
    }

    // MARK: - It fits

    @MainActor
    private func naturalHeight(_ view: some View, width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view.fixedSize(horizontal: false, vertical: true))
        return host.sizeThatFits(in: CGSize(width: width, height: 10_000)).height
    }

    /// A widget's content box after the system's 16pt margins.
    private func content(_ side: CGFloat) -> CGFloat { side - 32 }

    @MainActor
    private func idealWidth(_ view: some View) -> CGFloat {
        UIHostingController(rootView: view.fixedSize()).sizeThatFits(in: CGSize(width: 10_000, height: 10_000)).width
    }

    private typealias Form = OverviewSmallContent.Form

    /// The small overview: the readable form fits a 158pt widget in both
    /// directions, the compact one the smallest 148pt widget. Width is part of
    /// the check because the overview steps both blocks down together when a
    /// headline and a provider name no longer fit side by side.
    @MainActor
    func testSmallOverviewFitsItsMeasuredBounds() {
        let small = OverviewSmallContent(providers: slots, now: measuredAt, isStale: true)
        let readable = small.layout(Form(compact: false, tier: .full))
        let compact = small.layout(Form(compact: true, tier: .full))
        let roomy = naturalHeight(readable, width: content(158))
        let tight = naturalHeight(compact, width: content(148))
        XCTAssertLessThanOrEqual(roomy, content(158), "readable small overview: \(roomy)pt")
        XCTAssertLessThanOrEqual(tight, content(148), "compact small overview: \(tight)pt")
        XCTAssertLessThanOrEqual(idealWidth(readable), content(158))
        XCTAssertLessThanOrEqual(idealWidth(compact), content(148))
    }

    /// The first form that fits, as the widget's own `ViewThatFits` picks it.
    @MainActor
    private func chosenForm(
        _ small: OverviewSmallContent, side: CGFloat, typeSize: DynamicTypeSize
    ) -> Form? {
        OverviewSmallContent.forms.first { form in
            let view = small.layout(form).environment(\.dynamicTypeSize, typeSize)
            return idealWidth(view) <= content(side) && naturalHeight(view, width: content(side)) <= content(side)
        }
    }

    /// The blocker case: the smallest widget, XXL text, a scoped weekly
    /// headline at 100% beside a three-day one. Some form fits whole — so the
    /// widget never falls through to a truncated line — and the one chosen
    /// still carries the complete countdown.
    @MainActor
    func testExtremeScopedWeeklyNeverTruncatesTheCountdown() throws {
        let slots = [
            WidgetProviderSlot(id: UsageProviderID.codex, provider: UsageSyncProvider(
                providerId: UsageProviderID.codex, connected: true, collecting: true, measurement: threeDay
            )),
            WidgetProviderSlot(id: UsageProviderID.claude, provider: UsageSyncProvider(
                providerId: UsageProviderID.claude, connected: true, collecting: true, measurement: scopedWeekly
            ))
        ]
        let small = OverviewSmallContent(providers: slots, now: measuredAt)
        for typeSize in [DynamicTypeSize.large, .xLarge, .xxLarge, .xxxLarge] {
            let form = try XCTUnwrap(
                chosenForm(small, side: 148, typeSize: typeSize),
                "no overview form fits a 148pt widget at \(typeSize)"
            )
            let chosen = try XCTUnwrap(parts(scopedWeekly, form.tier)?.countdown)
            XCTAssertTrue(["6d 23h 59m left", "6d23h59m"].contains(chosen), "\(typeSize): \(chosen)")
            // Freshness gives way before the window's identity does.
            XCTAssertNotNil(parts(scopedWeekly, form.tier)?.name, "\(typeSize) kept a window name")
        }
    }

    /// Both providers are always drawn in one form: a single tier is chosen
    /// for the whole overview, so one block cannot read "5H" beside another's
    /// "5 Hour".
    @MainActor
    func testBothProvidersShareOneForm() throws {
        let small = OverviewSmallContent(providers: slots, now: measuredAt)
        let form = try XCTUnwrap(chosenForm(small, side: 158, typeSize: .large))
        XCTAssertEqual(form, Form(compact: false, tier: .full), "default text on a 158pt widget stays readable")
        XCTAssertEqual(OverviewSmallContent.forms.last?.tier, .countdownOnly)
    }

    /// The medium overview: each column is at least as wide as a small
    /// widget of the same phone and exactly as tall, so the single-provider
    /// widget's readable form fits a 338×158pt medium widget and its compact
    /// form the smallest 321×148pt one.
    @MainActor
    func testMediumColumnsFitTheirMeasuredBounds() {
        func column(_ mediumWidth: CGFloat) -> CGFloat {
            (content(mediumWidth) - 2 * OverviewMediumContent.columnSpacing - 1) / 2
        }
        XCTAssertGreaterThanOrEqual(column(338), content(158), "a column is no narrower than a small widget")

        let codex = ProviderWidgetSmallContent(
            providerId: UsageProviderID.codex, provider: slots[0].provider, now: measuredAt, isStale: true
        )
        let roomy = naturalHeight(codex.layout(compact: false), width: column(338))
        let compact = naturalHeight(codex.layout(compact: true), width: column(321))
        XCTAssertLessThanOrEqual(roomy, content(158), "readable medium column: \(roomy)pt")
        XCTAssertLessThanOrEqual(compact, content(148), "compact medium column: \(compact)pt")

        let whole = naturalHeight(
            OverviewMediumContent(providers: slots, now: measuredAt, isStale: true), width: content(338)
        )
        XCTAssertLessThanOrEqual(whole, content(158), "whole medium overview: \(whole)pt")
    }
}
