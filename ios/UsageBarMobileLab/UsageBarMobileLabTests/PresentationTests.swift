import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

final class PresentationTests: XCTestCase {
    private func date(_ string: String) throws -> Date {
        try XCTUnwrap(UsageSyncSerialization.date(from: string))
    }

    // MARK: - Provider names

    func testKnownProviderDisplayNames() {
        XCTAssertEqual(ProviderPresentation.displayName(for: "codex"), "Codex")
        XCTAssertEqual(ProviderPresentation.displayName(for: "claude-code"), "Claude")
    }

    /// A provider added on the desktop after this app shipped must still render
    /// readably rather than as a raw slug.
    func testUnknownProviderGetsDerivedLabel() {
        XCTAssertEqual(ProviderPresentation.displayName(for: "future-model"), "Future Model")
        XCTAssertEqual(ProviderPresentation.displayName(for: "gemini"), "Gemini")
    }

    // MARK: - Lifecycle states

    func testPausedProviderPresentation() {
        let provider = UsageSyncProvider(
            providerId: "codex",
            connected: true,
            collecting: false,
            measurement: nil
        )
        XCTAssertEqual(ProviderPresentation.statusLabel(for: provider), "Paused")
        // Paused is a user choice, not a fault.
        XCTAssertFalse(ProviderPresentation.isAttentionState(provider))
    }

    /// A paused provider keeps its retained reading, and that reading must
    /// still be shown.
    func testPausedProviderWithRetainedMeasurementStillPresentsIt() throws {
        let measurement = UsageSyncMeasurement(
            measuredAt: try date("2026-03-04T08:00:00Z"),
            headlineRemainingPercent: 41,
            headlineWindowId: "five-hour",
            windows: [
                UsageSyncWindow(
                    windowId: "five-hour",
                    kind: .fiveHour,
                    durationMinutes: 300,
                    remainingPercent: 41
                )
            ]
        )
        let provider = UsageSyncProvider(
            providerId: "codex",
            connected: true,
            collecting: false,
            measurement: measurement
        )
        XCTAssertEqual(ProviderPresentation.statusLabel(for: provider), "Paused")
        XCTAssertEqual(provider.measurement?.headlineRemainingPercent, 41)
    }

    func testConnectedCollectingWithoutMeasurement() {
        let provider = UsageSyncProvider(
            providerId: "codex",
            connected: true,
            collecting: true,
            measurement: nil
        )
        XCTAssertEqual(ProviderPresentation.statusLabel(for: provider), "Waiting for usage data")
    }

    func testDisconnectedProviderPresentation() {
        let provider = UsageSyncProvider(
            providerId: "codex",
            connected: false,
            collecting: false,
            measurement: nil
        )
        XCTAssertEqual(ProviderPresentation.statusLabel(for: provider), "Disconnected")
        XCTAssertTrue(ProviderPresentation.isAttentionState(provider))
    }

    // MARK: - Window labels

    func testFiveHourAndWeeklyLabels() {
        XCTAssertEqual(
            WindowPresentation.label(for: UsageSyncWindow(
                windowId: "five-hour", kind: .fiveHour, durationMinutes: 300, remainingPercent: 50
            )),
            "5 Hour"
        )
        XCTAssertEqual(
            WindowPresentation.label(for: UsageSyncWindow(
                windowId: "weekly", kind: .weekly, durationMinutes: 10_080, remainingPercent: 50
            )),
            "Weekly"
        )
    }

    func testWeeklyScopedLabelUsesScope() {
        XCTAssertEqual(
            WindowPresentation.label(for: UsageSyncWindow(
                windowId: "weekly-opus", kind: .weeklyScoped, scope: "opus", remainingPercent: 30
            )),
            "Weekly · Opus"
        )
    }

    func testDurationLabelUsesLargestExactUnit() {
        XCTAssertEqual(WindowPresentation.durationLabel(minutes: 4_320), "3 Day")
        XCTAssertEqual(WindowPresentation.durationLabel(minutes: 180), "3 Hour")
        XCTAssertEqual(WindowPresentation.durationLabel(minutes: 90), "90 Minute")
        XCTAssertEqual(
            WindowPresentation.label(for: UsageSyncWindow(
                windowId: "duration-4320", kind: .duration, durationMinutes: 4_320, remainingPercent: 20
            )),
            "3 Day"
        )
    }

    /// The forward-compatibility case must read neutrally and must never fall
    /// back to showing the wire identifier.
    func testUnknownWindowFallbackLabel() {
        let window = UsageSyncWindow(
            windowId: "unknown-0", kind: .unknown, position: 0, remainingPercent: 12
        )
        let label = WindowPresentation.label(for: window)
        XCTAssertEqual(label, "Additional Limit 1")
        XCTAssertFalse(label.contains("unknown-0"))
    }

    func testWindowLabelsNeverExposeWindowId() {
        let windows = [
            UsageSyncWindow(windowId: "five-hour", kind: .fiveHour, durationMinutes: 300, remainingPercent: 1),
            UsageSyncWindow(windowId: "weekly", kind: .weekly, durationMinutes: 10_080, remainingPercent: 1),
            UsageSyncWindow(windowId: "weekly-opus", kind: .weeklyScoped, scope: "opus", remainingPercent: 1),
            UsageSyncWindow(windowId: "duration-4320", kind: .duration, durationMinutes: 4_320, remainingPercent: 1),
            UsageSyncWindow(windowId: "unknown-2", kind: .unknown, position: 2, remainingPercent: 1)
        ]
        for window in windows {
            XCTAssertFalse(WindowPresentation.label(for: window).contains(window.windowId))
        }
    }

    // MARK: - Freshness

    func testAgeIsDerivedFromMeasuredAt() throws {
        let measuredAt = try date("2026-03-04T09:00:00Z")
        let measurement = UsageSyncMeasurement(
            measuredAt: measuredAt,
            headlineRemainingPercent: 64,
            headlineWindowId: "five-hour",
            windows: [UsageSyncWindow(windowId: "five-hour", kind: .fiveHour, durationMinutes: 300, remainingPercent: 64)]
        )
        XCTAssertEqual(
            FreshnessPresentation.age(of: measurement, now: measuredAt.addingTimeInterval(180)),
            "Updated 3 min ago"
        )
        XCTAssertEqual(
            FreshnessPresentation.age(of: measurement, now: measuredAt.addingTimeInterval(7_200)),
            "Updated 2 hr ago"
        )
        XCTAssertEqual(
            FreshnessPresentation.age(of: measurement, now: measuredAt.addingTimeInterval(30)),
            "Updated just now"
        )
        XCTAssertEqual(
            FreshnessPresentation.age(of: measurement, now: measuredAt.addingTimeInterval(86_400 * 2)),
            "Updated 2 days ago"
        )
    }

    /// The critical freshness rule: a recent `generatedAt` must not make an old
    /// `measuredAt` look fresh. The snapshot below was generated "now" but
    /// measured a day earlier, and the age must reflect the measurement.
    func testGeneratedAtDoesNotSubstituteForMeasuredAt() throws {
        let generatedAt = try date("2026-03-05T09:00:00Z")
        let measuredAt = try date("2026-03-04T09:00:00Z")
        let snapshot = UsageSyncSnapshot(
            generatedAt: generatedAt,
            providers: [
                UsageSyncProvider(
                    providerId: "codex",
                    connected: true,
                    collecting: true,
                    measurement: UsageSyncMeasurement(
                        measuredAt: measuredAt,
                        headlineRemainingPercent: 64,
                        headlineWindowId: "five-hour",
                        windows: [UsageSyncWindow(windowId: "five-hour", kind: .fiveHour, durationMinutes: 300, remainingPercent: 64)]
                    )
                )
            ]
        )
        let measurement = try XCTUnwrap(snapshot.providers.first?.measurement)
        let rendered = FreshnessPresentation.age(of: measurement, now: generatedAt)
        XCTAssertEqual(rendered, "Updated 1 day ago")
        XCTAssertNotEqual(rendered, "Updated just now")
    }

    func testResetLabelOmittedWhenAbsent() {
        let window = UsageSyncWindow(
            windowId: "five-hour", kind: .fiveHour, durationMinutes: 300, remainingPercent: 50
        )
        XCTAssertNil(FreshnessPresentation.resetLabel(for: window))
    }

    func testResetLabelPresentWhenAvailable() throws {
        let window = UsageSyncWindow(
            windowId: "five-hour",
            kind: .fiveHour,
            durationMinutes: 300,
            remainingPercent: 50,
            resetsAt: try date("2026-03-04T13:00:00Z")
        )
        let label = try XCTUnwrap(FreshnessPresentation.resetLabel(for: window, now: try date("2026-03-04T09:00:00Z")))
        XCTAssertTrue(label.hasPrefix("Resets "))
    }

    // MARK: - Canonical fixture rendering

    /// The whole dashboard, against the shared parity corpus.
    func testBasicFixtureRendersExpectedHeadlinesAndWindows() throws {
        let snapshot = try TestFixtures.decodedBasicSnapshot()
        XCTAssertEqual(snapshot.providers.map(\.providerId), ["codex", "claude-code"])

        let codex = try XCTUnwrap(snapshot.providers.first { $0.providerId == "codex" })
        XCTAssertEqual(ProviderPresentation.displayName(for: codex.providerId), "Codex")
        XCTAssertEqual(codex.measurement?.headlineRemainingPercent, 64)
        XCTAssertEqual(
            codex.measurement?.windows.map { WindowPresentation.label(for: $0) },
            ["5 Hour", "Weekly"]
        )
        XCTAssertEqual(codex.measurement?.windows.map(\.remainingPercent), [64, 81])

        let claude = try XCTUnwrap(snapshot.providers.first { $0.providerId == "claude-code" })
        XCTAssertEqual(ProviderPresentation.displayName(for: claude.providerId), "Claude")
        XCTAssertEqual(claude.measurement?.headlineRemainingPercent, 52)
        XCTAssertEqual(claude.measurement?.windows.map(\.remainingPercent), [52, 76])
    }

    /// A duration window can legitimately be the headline; the dashboard must
    /// render that without treating it as a special case.
    func testCodexDurationHeadlineRenders() throws {
        let snapshot = UsageSyncSnapshot(
            generatedAt: try date("2026-03-04T09:00:00Z"),
            providers: [
                UsageSyncProvider(
                    providerId: "codex",
                    connected: true,
                    collecting: true,
                    measurement: UsageSyncMeasurement(
                        measuredAt: try date("2026-03-04T09:00:00Z"),
                        headlineRemainingPercent: 18,
                        headlineWindowId: "duration-4320",
                        windows: [
                            UsageSyncWindow(
                                windowId: "duration-4320",
                                kind: .duration,
                                durationMinutes: 4_320,
                                remainingPercent: 18
                            )
                        ]
                    )
                )
            ]
        )
        let provider = try XCTUnwrap(snapshot.providers.first)
        let window = try XCTUnwrap(provider.measurement?.windows.first)
        XCTAssertEqual(WindowPresentation.label(for: window), "3 Day")
        XCTAssertEqual(provider.measurement?.headlineRemainingPercent, 18)
    }
}
