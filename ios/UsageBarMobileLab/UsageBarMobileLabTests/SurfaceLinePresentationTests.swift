import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// The exact strings each mobile surface renders.
final class SurfaceLinePresentationTests: XCTestCase {
    private let measuredAt = Date(timeIntervalSince1970: 1_772_000_000)

    private func measurement(
        headline: String = "five-hour",
        percent: Int = 64,
        measuredAt: Date? = nil,
        windows: [UsageSyncWindow]
    ) -> UsageSyncMeasurement {
        UsageSyncMeasurement(
            measuredAt: measuredAt ?? self.measuredAt,
            headlineRemainingPercent: percent,
            headlineWindowId: headline,
            windows: windows
        )
    }

    private func window(
        _ id: String,
        kind: UsageSyncWindowKind,
        percent: Int,
        minutes: Int? = nil,
        resetsAt: Date? = nil
    ) -> UsageSyncWindow {
        UsageSyncWindow(
            windowId: id, kind: kind, scope: nil, durationMinutes: minutes,
            remainingPercent: percent, resetsAt: resetsAt
        )
    }

    /// Codex's awkward case: the headline is a three-day duration window listed
    /// *after* the weekly one, and the two reset at different times.
    private var durationHeadline: UsageSyncMeasurement {
        measurement(headline: "duration-4320", percent: 45, windows: [
            window("weekly", kind: .weekly, percent: 87, minutes: 10_080,
                   resetsAt: measuredAt.addingTimeInterval(5 * 86_400)),
            window("duration-4320", kind: .duration, percent: 45, minutes: 4_320,
                   resetsAt: measuredAt.addingTimeInterval(2 * 3600))
        ])
    }

    private var fiveHourHeadline: UsageSyncMeasurement {
        measurement(windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300,
                   resetsAt: measuredAt.addingTimeInterval(90 * 60)),
            window("weekly", kind: .weekly, percent: 81, minutes: 10_080,
                   resetsAt: measuredAt.addingTimeInterval(4 * 86_400))
        ])
    }

    // MARK: - Provider systemSmall

    func testProviderSmallShowsHeadlineWindowLabelAndCountdown() {
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowLine(in: fiveHourHeadline, now: measuredAt),
            "5 Hour · 1h 30m left"
        )
    }

    /// The regression this checkpoint exists for: the label and the countdown
    /// must both follow `headlineWindowId`. Reading `windows.first` would give
    /// "Weekly · 5d left" beside a 45% three-day number.
    func testProviderSmallUsesTheHeadlineWindowNotTheFirst() {
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowLine(in: durationHeadline, now: measuredAt),
            "3 Day · 2h left"
        )
    }

    func testProviderSmallOmitsCountdownWithoutAReset() {
        let value = measurement(windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300)
        ])
        XCTAssertEqual(SurfaceLinePresentation.headlineWindowLine(in: value, now: measuredAt), "5 Hour")
    }

    func testProviderSmallOmitsCountdownOnceTheResetHasPassed() {
        let value = measurement(windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300,
                   resetsAt: measuredAt.addingTimeInterval(60))
        ])
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowLine(in: value, now: measuredAt.addingTimeInterval(120)),
            "5 Hour"
        )
    }

    /// No headline window in the snapshot means no invented label.
    func testProviderSmallRendersNoLineWhenTheHeadlineWindowIsAbsent() {
        let value = measurement(headline: "not-present", windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300)
        ])
        XCTAssertNil(SurfaceLinePresentation.headlineWindowLine(in: value, now: measuredAt))
    }

    // MARK: - Lock Screen accessoryRectangular

    func testAccessoryFooterCarriesCountdownAndAge() {
        XCTAssertEqual(
            SurfaceLinePresentation.accessoryFooter(
                of: fiveHourHeadline, now: measuredAt.addingTimeInterval(3 * 60)
            ),
            "1h27m left · 3m ago"
        )
    }

    /// Freshness is never dropped to make room for the countdown.
    func testAccessoryFooterKeepsAgeWhenThereIsNoCountdown() {
        let value = measurement(windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300)
        ])
        XCTAssertEqual(
            SurfaceLinePresentation.accessoryFooter(of: value, now: measuredAt.addingTimeInterval(7 * 60)),
            "7m ago"
        )
    }

    func testAccessoryFooterAgeComesFromMeasuredAtNotTheReset() {
        let old = measurement(
            measuredAt: measuredAt.addingTimeInterval(-2 * 86_400),
            windows: [
                window("five-hour", kind: .fiveHour, percent: 64, minutes: 300,
                       resetsAt: measuredAt.addingTimeInterval(2 * 3600))
            ]
        )
        XCTAssertEqual(
            SurfaceLinePresentation.accessoryFooter(of: old, now: measuredAt),
            "2h left · 2d ago",
            "a soon reset must not make a two-day-old reading look recent"
        )
    }

    // MARK: - Lock Screen accessoryInline

    func testInlinePutsPercentageBeforeCountdown() {
        let text = SurfaceLinePresentation.inline(
            name: "Codex", percent: 64, measurement: fiveHourHeadline, now: measuredAt
        )
        XCTAssertEqual(text, "Codex 64% · 1h30m")
        let percentIndex = try? XCTUnwrap(text.range(of: "64%")).lowerBound
        let countdownIndex = try? XCTUnwrap(text.range(of: "1h30m")).lowerBound
        XCTAssertNotNil(percentIndex)
        XCTAssertNotNil(countdownIndex)
        XCTAssertLessThan(percentIndex!, countdownIndex!)
    }

    func testInlineFallsBackToPercentageAlone() {
        XCTAssertEqual(
            SurfaceLinePresentation.inline(name: "Codex", percent: 64, measurement: nil),
            "Codex 64%"
        )
        let value = measurement(windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300)
        ])
        XCTAssertEqual(
            SurfaceLinePresentation.inline(
                name: "Claude", percent: 52, measurement: value, now: measuredAt
            ),
            "Claude 52%"
        )
    }

    // MARK: - Overview rows

    func testOverviewCountdownSuffixIsSeparatedAndPerProvider() throws {
        XCTAssertEqual(
            SurfaceLinePresentation.countdownSuffix(in: fiveHourHeadline, now: measuredAt),
            "· 1h30m"
        )
        XCTAssertEqual(
            SurfaceLinePresentation.countdownSuffix(in: durationHeadline, now: measuredAt),
            "· 2h"
        )
    }

    func testOverviewCountdownSuffixIsNilWithoutAMeasurementOrReset() {
        XCTAssertNil(SurfaceLinePresentation.countdownSuffix(in: nil))
        let value = measurement(windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300)
        ])
        XCTAssertNil(SurfaceLinePresentation.countdownSuffix(in: value, now: measuredAt))
    }

    /// Each provider counts down its own headline window; the parity corpus
    /// gives two providers whose five-hour windows reset at different times.
    func testOverviewDerivesEachProviderCountdownIndependently() throws {
        let snapshot = try TestFixtures.paritySnapshot("basic")
        let codex = try XCTUnwrap(snapshot.providers.first { $0.providerId == UsageProviderID.codex })
        let claude = try XCTUnwrap(snapshot.providers.first { $0.providerId == UsageProviderID.claude })
        let codexReset = try XCTUnwrap(HeadlinePresentation.resetsAt(in: XCTUnwrap(codex.measurement)))
        let claudeReset = try XCTUnwrap(HeadlinePresentation.resetsAt(in: XCTUnwrap(claude.measurement)))
        XCTAssertNotEqual(codexReset, claudeReset, "fixture precondition")

        let now = codexReset.addingTimeInterval(-2 * 3600)
        XCTAssertEqual(
            SurfaceLinePresentation.countdownSuffix(in: codex.measurement, now: now), "· 2h"
        )
        XCTAssertEqual(
            SurfaceLinePresentation.countdownSuffix(in: claude.measurement, now: now), "· 1h30m"
        )
    }

    // MARK: - Lifecycle states

    /// A paused provider keeps its retained reading, and that reading's window
    /// keeps running — so the countdown is shown, and the lifecycle status is
    /// reported separately.
    func testPausedRetainedMeasurementStillRendersACountdown() throws {
        let snapshot = try TestFixtures.paritySnapshot("paused-retained")
        let provider = try XCTUnwrap(snapshot.providers.first)
        let value = try XCTUnwrap(provider.measurement)
        XCTAssertFalse(provider.collecting)
        XCTAssertTrue(provider.connected)
        XCTAssertEqual(ProviderPresentation.statusLabel(for: provider), "Paused")

        let reset = try XCTUnwrap(HeadlinePresentation.resetsAt(in: value))
        XCTAssertEqual(
            SurfaceLinePresentation.headlineWindowLine(in: value, now: reset.addingTimeInterval(-3600)),
            "5 Hour · 1h left"
        )
    }

    /// A cached snapshot is still a validated reading whose window is still
    /// running, so the countdown is not suppressed merely because the fetch
    /// failed. The stale indicator is what says the data is not current.
    func testCachedStateDoesNotLoseItsCountdown() async throws {
        let cached = try TestFixtures.paritySnapshot("basic")
        let entry = await UsageTimelineProvider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(snapshot: cached),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))
        ).currentEntry()

        XCTAssertTrue(entry.isStale)
        let value = try XCTUnwrap(entry.snapshot?.providers.first?.measurement)
        let reset = try XCTUnwrap(HeadlinePresentation.resetsAt(in: value))
        XCTAssertNotNil(
            SurfaceLinePresentation.headlineWindowLine(in: value, now: reset.addingTimeInterval(-1800))
        )
    }

    /// Not-configured exposes no quota and therefore no reset.
    func testNotConfiguredExposesNoQuotaOrReset() async throws {
        let entry = await UsageTimelineProvider(
            store: InMemoryConnectionStore(),
            cache: InMemorySnapshotCache(snapshot: try TestFixtures.paritySnapshot("basic")),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.notConnected))
        ).currentEntry()

        XCTAssertEqual(entry.state, .notConfigured)
        XCTAssertNil(entry.snapshot)
        XCTAssertNil(SurfaceLinePresentation.countdownSuffix(in: entry.snapshot?.providers.first?.measurement))
    }

    /// A provider with no measurement at all renders safely everywhere.
    func testNoMeasurementRendersSafely() {
        XCTAssertNil(SurfaceLinePresentation.countdownSuffix(in: nil))
        XCTAssertEqual(
            SurfaceLinePresentation.inline(name: "Codex", percent: 0, measurement: nil),
            "Codex 0%"
        )
    }
}

/// Contract assertions that span the surfaces: one resolver, no `windows.first`
/// headline anywhere, and detail rows that keep their precise reset time.
final class HeadlineContractTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// Drops `//` comments so a source assertion tests code, not prose — these
    /// files legitimately document the mistake they no longer make.
    private static func strippingComments(from source: String) -> String {
        source.components(separatedBy: .newlines).map { line -> String in
            guard let range = line.range(of: "//") else { return line }
            return String(line[..<range.lowerBound])
        }.joined(separator: "\n")
    }

    /// The regression guard. No mobile surface may treat the first listed
    /// window as the headline; the desktop said which one it is.
    func testNoSurfaceTreatsTheFirstWindowAsTheHeadline() throws {
        let manager = FileManager.default
        var scanned = 0
        for root in ["Shared", "UsageBarMobileLab", "UsageBarWidgets"] {
            let base = projectRoot.appendingPathComponent(root)
            guard let walker = manager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let code = Self.strippingComments(from: try String(contentsOf: url, encoding: .utf8))
                scanned += 1
                XCTAssertFalse(
                    code.contains("windows.first") && !code.contains("windows.first {"),
                    "\(url.lastPathComponent) resolves a headline by array position"
                )
            }
        }
        XCTAssertGreaterThan(scanned, 0)
    }

    /// Exactly one place resolves `headlineWindowId`.
    func testOnlyOneHeadlineResolverExists() throws {
        let manager = FileManager.default
        var resolvers: [String] = []
        for root in ["Shared", "UsageBarMobileLab", "UsageBarWidgets"] {
            let base = projectRoot.appendingPathComponent(root)
            guard let walker = manager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let code = Self.strippingComments(from: try String(contentsOf: url, encoding: .utf8))
                if code.contains("$0.windowId == measurement.headlineWindowId") {
                    resolvers.append(url.lastPathComponent)
                }
            }
        }
        XCTAssertEqual(resolvers, ["ProviderPresentation.swift"])
    }

    /// The app's detail rows carry **both** reset facts.
    ///
    /// They keep the precise absolute instant they always had — the headline
    /// answers "should I slow down?", these answer "when exactly?" — and they
    /// now state the remaining interval beside it at full precision. The two
    /// are not the same fact in two formats: one is a duration a person budgets
    /// against, the other an instant they plan an afternoon around.
    func testDetailedWindowRowsKeepTheAbsoluteResetTimeAndGainAPreciseCountdown() throws {
        let card = Self.strippingComments(
            from: try source("UsageBarMobileLab/Views/ProviderCardView.swift")
        )
        XCTAssertTrue(
            card.contains("FreshnessPresentation.resetSummary(for: window, now: now)"),
            "detail rows must render the one shared reset summary"
        )

        let now = Date(timeIntervalSince1970: 1_772_000_000)
        let window = UsageSyncWindow(
            windowId: "five-hour", kind: .fiveHour, scope: nil, durationMinutes: 300,
            remainingPercent: 64,
            resetsAt: now.addingTimeInterval((4 * 60 + 59) * 60)
        )

        let summary = try XCTUnwrap(FreshnessPresentation.resetSummary(for: window, now: now))
        XCTAssertTrue(summary.hasPrefix("Resets in 4h 59m · "), summary)
        XCTAssertFalse(summary.hasPrefix("Resets in 4h · "), "a row must not drop its minutes")

        // The absolute instant survives, still locale-formatted by the one
        // formatter both spellings share.
        let clock = try XCTUnwrap(FreshnessPresentation.resetLabel(for: window, now: now))
            .replacingOccurrences(of: "Resets ", with: "")
        XCTAssertTrue(summary.hasSuffix(clock), summary)

        // Once the reset has passed there is no interval left to state, so the
        // row falls back to the instant alone rather than printing a zero or a
        // negative countdown.
        let elapsed = try XCTUnwrap(
            FreshnessPresentation.resetSummary(for: window, now: now.addingTimeInterval(6 * 3600))
        )
        XCTAssertFalse(elapsed.contains("Resets in"), elapsed)

        // A window with no reset instant renders nothing at all.
        let openEnded = UsageSyncWindow(
            windowId: "weekly", kind: .weekly, scope: nil, durationMinutes: 10_080,
            remainingPercent: 81, resetsAt: nil
        )
        XCTAssertNil(FreshnessPresentation.resetSummary(for: openEnded, now: now))
    }

    /// The dashboard's local tick is presentation only.
    func testDashboardTickTouchesNothingButTheClock() throws {
        let card = Self.strippingComments(
            from: try source("UsageBarMobileLab/Views/ProviderCardView.swift")
        )
        XCTAssertTrue(card.contains("TimelineView(.periodic("))
        for forbidden in [
            "refresh(", "fetchSnapshot", "cache.store", "WidgetCenter", "ControlCenter",
            "Timer.scheduledTimer", "URLSession"
        ] {
            XCTAssertFalse(card.contains(forbidden), "dashboard tick reaches \(forbidden)")
        }
    }

    /// Control Center's wording is unchanged by the resolver refactor.
    func testControlCenterOutputIsUnchanged() async throws {
        let snapshot = try TestFixtures.paritySnapshot("codex-duration-headline")
        let value = try await UsageControlValueProvider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(snapshot))
        ).currentValue()

        let headline = try XCTUnwrap(value.headline(for: UsageProviderID.codex))
        XCTAssertEqual(headline.remainingPercent, 45)
        XCTAssertEqual(headline.windowLabel, "3D")
        let reset = try XCTUnwrap(headline.resetsAt)
        XCTAssertEqual(
            ControlPresentation.providerTitle(
                for: value, providerId: UsageProviderID.codex,
                now: reset.addingTimeInterval(-2 * 3600)
            ),
            "Codex 3D 45% · 2h"
        )
    }

    /// WidgetKit scheduling is untouched: no shorter interval, no new clock.
    func testWidgetSchedulingIsUnchanged() throws {
        XCTAssertGreaterThanOrEqual(UsageTimelineProvider.refreshInterval, 15 * 60)
        let manager = FileManager.default
        for root in ["Shared", "UsageBarWidgets"] {
            let base = projectRoot.appendingPathComponent(root)
            guard let walker = manager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let code = try String(contentsOf: url, encoding: .utf8)
                for forbidden in [
                    "import BackgroundTasks", "BGTaskScheduler", "Timer.scheduledTimer",
                    "registerForRemoteNotifications", "ControlPushHandler"
                ] {
                    XCTAssertFalse(code.contains(forbidden), "\(url.lastPathComponent): \(forbidden)")
                }
            }
        }
    }
}
