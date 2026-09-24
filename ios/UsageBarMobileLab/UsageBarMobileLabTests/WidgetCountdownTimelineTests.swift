import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// How a widget's countdown stays current without asking the network for
/// anything.
///
/// A widget view is rendered when its timeline is built, not when it is looked
/// at. A timeline of one entry therefore freezes its countdown at build time,
/// which is how "2h 59m left" stayed on a Lock Screen long after the window had
/// under two hours in it. The cure is more entries from the *same* fetched
/// reading — never a shorter refresh interval, a timer, or a background task.
final class WidgetCountdownTimelineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_772_000_000)

    private func snapshot(resetsAt: Date, measuredAt: Date) -> UsageSyncSnapshot {
        UsageSyncSnapshot(
            generatedAt: measuredAt,
            providers: [
                UsageSyncProvider(
                    providerId: UsageProviderID.codex,
                    connected: true,
                    collecting: true,
                    measurement: UsageSyncMeasurement(
                        measuredAt: measuredAt,
                        headlineRemainingPercent: 39,
                        headlineWindowId: "five-hour",
                        windows: [
                            UsageSyncWindow(
                                windowId: "five-hour", kind: .fiveHour, scope: nil,
                                durationMinutes: 300, remainingPercent: 39, resetsAt: resetsAt
                            )
                        ]
                    )
                )
            ]
        )
    }

    // MARK: - The ladder

    func testTimelineRendersOneReadingAtManyInstants() {
        let state = UsageSurfaceState.loaded(
            snapshot(resetsAt: start.addingTimeInterval(5 * 3600), measuredAt: start)
        )
        let entries = UsageTimelineProvider.countdownEntries(for: state, startingAt: start)

        XCTAssertGreaterThan(entries.count, 1, "a single entry freezes the countdown")
        XCTAssertEqual(entries.map(\.date), entries.map(\.date).sorted())
        XCTAssertEqual(entries.first?.date, start)
        for entry in entries {
            XCTAssertEqual(entry.state, state, "every entry renders the same fetched reading")
        }

        // The ladder outlasts the refresh request, so a deferred refresh does
        // not strand the widget on a frozen clock.
        let span = try? XCTUnwrap(entries.last?.date).timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(span ?? 0, UsageTimelineProvider.refreshInterval)
    }

    /// The point of the ladder: consecutive entries render different countdowns.
    func testConsecutiveEntriesRenderAFallingCountdown() throws {
        let state = UsageSurfaceState.loaded(
            snapshot(resetsAt: start.addingTimeInterval(5 * 3600), measuredAt: start)
        )
        let entries = UsageTimelineProvider.countdownEntries(for: state, startingAt: start)

        let lines: [String] = try entries.map { entry in
            let measurement = try XCTUnwrap(entry.snapshot?.providers.first?.measurement)
            return try XCTUnwrap(
                SurfaceLinePresentation.headlineWindowLine(in: measurement, now: entry.date)
            )
        }
        XCTAssertEqual(lines.first, "5 Hour · 5h left")
        XCTAssertEqual(lines[1], "5 Hour · 4h 55m left")
        XCTAssertGreaterThan(Set(lines).count, 1, "the countdown never advances")
        XCTAssertEqual(Set(lines).count, lines.count, "each entry is a distinct minute")
    }

    // MARK: - A clock tick is not a refresh

    /// Building the whole ladder costs exactly the one fetch the resolve made.
    func testTheWholeLadderCostsASingleFetch() async throws {
        let fetcher = ScriptedFetcher(
            outcome: .success(snapshot(resetsAt: start.addingTimeInterval(5 * 3600), measuredAt: start))
        )
        let cache = CountingSnapshotCache()
        let entry = await UsageTimelineProvider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: cache,
            client: fetcher
        ).currentEntry(now: start)

        XCTAssertEqual(fetcher.callCount, 1)
        let storesAfterResolve = cache.storeCount

        let entries = UsageTimelineProvider.countdownEntries(for: entry.state, startingAt: start)
        for laterEntry in entries {
            let measurement = try XCTUnwrap(laterEntry.snapshot?.providers.first?.measurement)
            _ = SurfaceLinePresentation.headlineWindowLine(in: measurement, now: laterEntry.date)
            _ = FreshnessPresentation.age(of: measurement, now: laterEntry.date)
        }

        XCTAssertEqual(fetcher.callCount, 1, "rendering a later entry must not fetch")
        XCTAssertEqual(cache.storeCount, storesAfterResolve, "rendering must not write the cache")
    }

    /// The invariant the whole design rests on: the clock moving forward makes
    /// a reading *older*, never newer, and never rewrites `measuredAt`.
    func testClockTicksAgeTheReadingAndNeverRefreshIt() throws {
        let measuredAt = start.addingTimeInterval(-10 * 3600)
        let state = UsageSurfaceState.loaded(
            snapshot(resetsAt: start.addingTimeInterval(5 * 3600), measuredAt: measuredAt)
        )
        let entries = UsageTimelineProvider.countdownEntries(for: state, startingAt: start)

        var previousAge = TimeInterval(-1)
        for entry in entries {
            let measurement = try XCTUnwrap(entry.snapshot?.providers.first?.measurement)
            XCTAssertEqual(measurement.measuredAt, measuredAt, "a tick must never rewrite measuredAt")

            let age = entry.date.timeIntervalSince(measurement.measuredAt)
            XCTAssertGreaterThan(age, previousAge, "a later entry must read as older, not fresher")
            previousAge = age

            let text = FreshnessPresentation.age(of: measurement, now: entry.date)
            XCTAssertFalse(text.contains("just now"), "a ten-hour-old reading is never 'just now'")
            XCTAssertTrue(text.hasSuffix("hr ago"), text)
        }

        let firstMeasurement = try XCTUnwrap(entries.first?.snapshot?.providers.first?.measurement)
        XCTAssertEqual(
            FreshnessPresentation.age(of: firstMeasurement, now: try XCTUnwrap(entries.first?.date)),
            "Updated 10 hr ago"
        )
    }

    /// Freshness and time-remaining stay separate facts: the countdown falls
    /// while the age climbs, from the same entry.
    func testCountdownAndAgeMoveInOppositeDirections() throws {
        let measuredAt = start.addingTimeInterval(-2 * 3600)
        let state = UsageSurfaceState.loaded(
            snapshot(resetsAt: start.addingTimeInterval(3 * 3600), measuredAt: measuredAt)
        )
        let entries = UsageTimelineProvider.countdownEntries(for: state, startingAt: start)
        let first = try XCTUnwrap(entries.first)
        let last = try XCTUnwrap(entries.last)

        let firstMeasurement = try XCTUnwrap(first.snapshot?.providers.first?.measurement)
        let lastMeasurement = try XCTUnwrap(last.snapshot?.providers.first?.measurement)

        XCTAssertEqual(
            SurfaceLinePresentation.accessoryFooter(of: firstMeasurement, now: first.date),
            "3h left · 2h ago"
        )
        XCTAssertEqual(
            SurfaceLinePresentation.accessoryFooter(of: lastMeasurement, now: last.date),
            "2h left · 3h ago",
            "an hour later: one hour less remaining, one hour more age"
        )
    }

    // MARK: - Scheduling stays system-controlled

    func testSchedulingAsksTheSystemForNothingExtra() {
        XCTAssertGreaterThanOrEqual(
            UsageTimelineProvider.refreshInterval, 15 * 60,
            "the ladder must not be paid for with a more aggressive refresh"
        )
        XCTAssertGreaterThanOrEqual(UsageTimelineProvider.countdownStep, 60)
    }
}
