import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// The headline window, the countdown, and the rule that keeps them from
/// pretending to be freshness.
final class HeadlinePresentationTests: XCTestCase {
    private let measuredAt = Date(timeIntervalSince1970: 1_772_000_000)

    private func window(
        _ id: String,
        kind: UsageSyncWindowKind,
        percent: Int,
        minutes: Int? = nil,
        scope: String? = nil,
        resetsAt: Date? = nil
    ) -> UsageSyncWindow {
        UsageSyncWindow(
            windowId: id,
            kind: kind,
            scope: scope,
            durationMinutes: minutes,
            remainingPercent: percent,
            resetsAt: resetsAt
        )
    }

    private func measurement(
        headline: String,
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

    // MARK: - Resolution

    func testResolvesFiveHourByHeadlineWindowId() throws {
        let value = measurement(headline: "five-hour", windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300),
            window("weekly", kind: .weekly, percent: 81, minutes: 10_080)
        ])
        XCTAssertEqual(HeadlinePresentation.window(in: value)?.windowId, "five-hour")
        XCTAssertEqual(HeadlinePresentation.label(in: value), "5 Hour")
        XCTAssertEqual(HeadlinePresentation.compactLabel(in: value), "5H")
    }

    /// The headline is the *second* window here. A resolver reading
    /// `windows.first` would answer "5 Hour" and be confidently wrong.
    func testResolvesWeeklyWhenItIsHeadlineButNotFirst() throws {
        let value = measurement(headline: "weekly", windows: [
            window("five-hour", kind: .fiveHour, percent: 90, minutes: 300),
            window("weekly", kind: .weekly, percent: 21, minutes: 10_080)
        ])
        XCTAssertNotEqual(value.windows.first?.windowId, value.headlineWindowId, "fixture precondition")
        XCTAssertEqual(HeadlinePresentation.window(in: value)?.windowId, "weekly")
        XCTAssertEqual(HeadlinePresentation.label(in: value), "Weekly")
    }

    /// Codex's real case: a multi-day duration limit that is the most
    /// constrained window and is listed after the weekly one.
    func testResolvesDurationWhenItIsHeadlineButNotFirst() throws {
        let value = measurement(headline: "duration-4320", percent: 45, windows: [
            window("weekly", kind: .weekly, percent: 87, minutes: 10_080),
            window("duration-4320", kind: .duration, percent: 45, minutes: 4_320)
        ])
        XCTAssertEqual(HeadlinePresentation.window(in: value)?.windowId, "duration-4320")
        XCTAssertEqual(HeadlinePresentation.label(in: value), "3 Day")
        XCTAssertEqual(HeadlinePresentation.compactLabel(in: value), "3D")
    }

    func testResolvesScopedWeeklyAndKeepsItsScopeInTheFullLabel() throws {
        let value = measurement(headline: "weekly-opus", percent: 91, windows: [
            window("weekly", kind: .weekly, percent: 74, minutes: 10_080),
            window("weekly-opus", kind: .weeklyScoped, percent: 91, minutes: 10_080, scope: "opus")
        ])
        XCTAssertEqual(HeadlinePresentation.label(in: value), "Weekly · Opus")
        // The compact form drops the scope; it has no honest short spelling.
        XCTAssertEqual(HeadlinePresentation.compactLabel(in: value), "Weekly")
    }

    /// A headline id naming a window that is not present yields nothing —
    /// never a guess at the first one.
    func testMissingHeadlineWindowResolvesToNil() {
        let value = measurement(headline: "not-present", windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300)
        ])
        XCTAssertNil(HeadlinePresentation.window(in: value))
        XCTAssertNil(HeadlinePresentation.label(in: value))
        XCTAssertNil(HeadlinePresentation.compactLabel(in: value))
        XCTAssertNil(HeadlinePresentation.resetsAt(in: value))
        XCTAssertNil(HeadlinePresentation.compactReset(in: value))
    }

    func testEmptyWindowsResolveToNil() {
        let value = measurement(headline: "five-hour", windows: [])
        XCTAssertNil(HeadlinePresentation.window(in: value))
    }

    /// The parity corpus, through the shared resolver.
    func testParityFixturesResolveTheirOwnHeadlineWindow() throws {
        for name in ["basic", "codex-duration-headline", "claude-weekly-scoped", "paused-retained"] {
            let snapshot = try TestFixtures.paritySnapshot(name)
            for provider in snapshot.providers {
                guard let value = provider.measurement else { continue }
                let resolved = try XCTUnwrap(HeadlinePresentation.window(in: value), name)
                XCTAssertEqual(resolved.windowId, value.headlineWindowId, name)
            }
        }
    }

    // MARK: - Countdown

    func testCountdownKeepsEverySignificantComponent() {
        let reset = Date(timeIntervalSince1970: 1_772_000_000)
        func remaining(_ seconds: TimeInterval) -> String? {
            FreshnessPresentation.compactTimeRemaining(
                until: reset, from: reset.addingTimeInterval(-seconds)
            )
        }
        XCTAssertEqual(remaining(59 * 60), "59m left")
        XCTAssertEqual(remaining(119 * 60), "1h 59m left")
        XCTAssertEqual(remaining((2 * 60 + 59) * 60), "2h 59m left")
        XCTAssertEqual(remaining(47 * 3600), "1d 23h left")
        XCTAssertEqual(remaining(72 * 3600), "3d left")
        XCTAssertEqual(remaining(30), "1m left", "a live window never reads as zero")
    }

    func testExpiredCountdownIsNil() {
        let reset = Date(timeIntervalSince1970: 1_772_000_000)
        XCTAssertNil(FreshnessPresentation.compactTimeRemaining(until: reset, from: reset))
        XCTAssertNil(
            FreshnessPresentation.compactTimeRemaining(until: reset, from: reset.addingTimeInterval(1))
        )
        XCTAssertNil(
            FreshnessPresentation.compactTimeRemaining(until: reset, from: reset.addingTimeInterval(86_400))
        )
    }

    func testMissingResetIsNil() {
        let value = measurement(headline: "five-hour", windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300, resetsAt: nil)
        ])
        XCTAssertNil(HeadlinePresentation.compactReset(in: value, now: measuredAt))
    }

    /// The countdown follows the headline window's reset, not the first
    /// window's — which is a different instant here.
    func testCountdownFollowsTheHeadlineWindowsReset() throws {
        let weeklyReset = measuredAt.addingTimeInterval(3 * 86_400)
        let durationReset = measuredAt.addingTimeInterval(2 * 3600)
        let value = measurement(headline: "duration-4320", percent: 45, windows: [
            window("weekly", kind: .weekly, percent: 87, minutes: 10_080, resetsAt: weeklyReset),
            window("duration-4320", kind: .duration, percent: 45, minutes: 4_320, resetsAt: durationReset)
        ])
        XCTAssertEqual(HeadlinePresentation.resetsAt(in: value), durationReset)
        XCTAssertEqual(HeadlinePresentation.compactReset(in: value, now: measuredAt), "2h left")
    }

    // MARK: - Countdown is not freshness

    /// The rule this whole checkpoint has to preserve: a window that resets
    /// soon says nothing about when the reading was taken.
    func testFutureResetNeverMakesAnOldMeasurementLookFresh() throws {
        let takenTwoDaysAgo = measuredAt
        let now = takenTwoDaysAgo.addingTimeInterval(2 * 86_400)
        let value = measurement(
            headline: "five-hour",
            measuredAt: takenTwoDaysAgo,
            windows: [
                window(
                    "five-hour", kind: .fiveHour, percent: 64, minutes: 300,
                    resetsAt: now.addingTimeInterval(2 * 3600)
                )
            ]
        )

        XCTAssertEqual(HeadlinePresentation.compactReset(in: value, now: now), "2h left")
        XCTAssertEqual(FreshnessPresentation.age(of: value, now: now), "Updated 2 days ago")
        XCTAssertEqual(
            FreshnessPresentation.headlineMetadata(of: value, now: now),
            "Updated 2 days ago · 2h left"
        )
    }

    /// Freshness is `measuredAt`, and a document built long afterwards cannot
    /// stand in for it.
    func testGeneratedAtDoesNotAffectAge() throws {
        let value = measurement(headline: "five-hour", windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300)
        ])
        let snapshot = UsageSyncSnapshot(
            generatedAt: measuredAt.addingTimeInterval(26 * 3600),
            providers: [
                UsageSyncProvider(
                    providerId: UsageProviderID.codex,
                    connected: true,
                    collecting: true,
                    measurement: value
                )
            ]
        )
        let now = snapshot.generatedAt
        XCTAssertEqual(FreshnessPresentation.age(of: value, now: now), "Updated 1 day ago")
        XCTAssertNotEqual(value.measuredAt, snapshot.generatedAt)
    }

    // MARK: - Metadata line

    func testHeadlineMetadataCombinesAgeAndCountdown() {
        let value = measurement(headline: "five-hour", windows: [
            window(
                "five-hour", kind: .fiveHour, percent: 64, minutes: 300,
                resetsAt: measuredAt.addingTimeInterval(3 * 3600)
            )
        ])
        let now = measuredAt.addingTimeInterval(3 * 60)
        XCTAssertEqual(
            FreshnessPresentation.headlineMetadata(of: value, now: now),
            "Updated 3 min ago · 2h 57m left"
        )
    }

    func testHeadlineMetadataIsAgeOnlyWithoutAReset() {
        let value = measurement(headline: "five-hour", windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300)
        ])
        let now = measuredAt.addingTimeInterval(3 * 60)
        XCTAssertEqual(FreshnessPresentation.headlineMetadata(of: value, now: now), "Updated 3 min ago")
    }

    func testHeadlineMetadataIsAgeOnlyWhenTheResetHasPassed() {
        let value = measurement(headline: "five-hour", windows: [
            window(
                "five-hour", kind: .fiveHour, percent: 64, minutes: 300,
                resetsAt: measuredAt.addingTimeInterval(60)
            )
        ])
        let now = measuredAt.addingTimeInterval(3 * 60)
        XCTAssertEqual(FreshnessPresentation.headlineMetadata(of: value, now: now), "Updated 3 min ago")
    }

    /// The metadata line must name the headline window's reset even when
    /// another window resets sooner.
    func testHeadlineMetadataUsesTheHeadlineWindowNotTheFirst() {
        let value = measurement(headline: "weekly", percent: 21, windows: [
            window(
                "five-hour", kind: .fiveHour, percent: 90, minutes: 300,
                resetsAt: measuredAt.addingTimeInterval(20 * 60)
            ),
            window(
                "weekly", kind: .weekly, percent: 21, minutes: 10_080,
                resetsAt: measuredAt.addingTimeInterval(2 * 86_400)
            )
        ])
        let now = measuredAt.addingTimeInterval(60)
        XCTAssertEqual(
            FreshnessPresentation.headlineMetadata(of: value, now: now),
            "Updated 1 min ago · 1d 23h 59m left",
            "the sooner five-hour reset must not be what the headline counts down"
        )
    }

    // MARK: - Short age

    func testShortAgeUsesTheLargestWholeUnit() {
        let base = Date(timeIntervalSince1970: 1_772_000_000)
        func age(_ seconds: TimeInterval) -> String {
            FreshnessPresentation.shortAge(from: base, to: base.addingTimeInterval(seconds))
        }
        XCTAssertEqual(age(0), "just now")
        XCTAssertEqual(age(59), "just now")
        XCTAssertEqual(age(60), "1m ago")
        XCTAssertEqual(age(59 * 60), "59m ago")
        XCTAssertEqual(age(3600), "1h ago")
        XCTAssertEqual(age(26 * 3600), "1d ago")
    }

    /// Short, but still `measuredAt`, and still with no stale threshold — it
    /// states an age and draws no conclusion from it.
    func testShortAgeComesFromMeasuredAt() {
        let value = measurement(headline: "five-hour", windows: [
            window("five-hour", kind: .fiveHour, percent: 64, minutes: 300)
        ])
        XCTAssertEqual(
            FreshnessPresentation.shortAge(of: value, now: measuredAt.addingTimeInterval(7 * 60)),
            "7m ago"
        )
    }
}
