import XCTest
import UsageBarCore
import UsageBarSync
@testable import UsageBarMobileSyncHost

/// What the desktop puts on the wire, and what it refuses to.
final class LiveSnapshotMappingTests: XCTestCase {
    // MARK: - The source of truth

    /// The single most important property of this phase: the phone is served
    /// the numbers the Mac is *showing*, not the numbers it has retained. The
    /// display filter holds a rise back for a cycle, so reading around it would
    /// make the phone disagree with the Mac beside it.
    func testBuilderUsesTheDisplayFilteredUsageItIsGiven() throws {
        // Raw would be 70% remaining; the displayed value is the filtered 60%.
        let displayed = HostFixtures.codexUsage(fiveHourUsed: 40, weeklyUsed: 10)
        let snapshot = try HostFixtures.snapshot([
            HostFixtures.state("Codex", usage: displayed)
        ])
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        let fiveHour = try XCTUnwrap(measurement.windows.first { $0.kind == .fiveHour })
        XCTAssertEqual(fiveHour.remainingPercent, 60, "the displayed value must be what crosses")
    }

    /// The inputs carry one `ProviderUsage` per provider and nothing else.
    /// There is no parameter through which a history sample could arrive, which
    /// is what makes "history is never transmitted" structural.
    func testInputsCarryOnlyTheDisplayFilteredUsage() {
        let usage = HostFixtures.codexUsage()
        let inputs = MobileSyncLiveSnapshot.inputs(from: [
            HostFixtures.state("Codex", usage: usage)
        ])
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].productName, "Codex")
        XCTAssertEqual(inputs[0].displayFilteredUsage?.windows.count, usage.windows.count)
    }

    func testProviderOrderMatchesTheMenu() {
        XCTAssertEqual(MobileSyncLiveSnapshot.providerOrder, ["Codex", "Claude Code"])
    }

    // MARK: - Lifecycle mapping

    func testConnectedCollectingCodexMapsCorrectly() throws {
        let snapshot = try HostFixtures.snapshot([
            HostFixtures.state("Codex", usage: HostFixtures.codexUsage())
        ])
        let provider = snapshot.providers[0]
        XCTAssertEqual(provider.providerId, "codex")
        XCTAssertTrue(provider.connected)
        XCTAssertTrue(provider.collecting)
        XCTAssertNotNil(provider.measurement)
    }

    func testConnectedCollectingClaudeMapsCorrectly() throws {
        let snapshot = try HostFixtures.snapshot([
            HostFixtures.state("Claude Code", usage: HostFixtures.claudeUsage())
        ])
        let provider = snapshot.providers[0]
        XCTAssertEqual(provider.providerId, "claude-code")
        XCTAssertTrue(provider.connected)
        XCTAssertTrue(provider.collecting)
        XCTAssertNotNil(provider.measurement)
    }

    /// Pausing is a deliberate choice and keeps the reading. A paused provider
    /// that lost its measurement would look broken rather than paused.
    func testPausedProviderStaysConnectedAndKeepsItsMeasurement() throws {
        let snapshot = try HostFixtures.snapshot([
            HostFixtures.state("Codex", collecting: false, usage: HostFixtures.codexUsage())
        ])
        let provider = snapshot.providers[0]
        XCTAssertTrue(provider.connected)
        XCTAssertFalse(provider.collecting)
        XCTAssertEqual(provider.measurement?.measuredAt, HostFixtures.measuredAt)
    }

    /// A disconnected provider carries no measurement, even if the caller
    /// passes one. Both this mapping and the builder drop it, so neither layer
    /// is the only thing standing in the way.
    func testDisconnectedProviderDropsItsMeasurement() throws {
        let snapshot = try HostFixtures.snapshot([
            HostFixtures.state("Codex", connected: false, collecting: false, usage: HostFixtures.codexUsage())
        ])
        let provider = snapshot.providers[0]
        XCTAssertFalse(provider.connected)
        XCTAssertFalse(provider.collecting)
        XCTAssertNil(provider.measurement)

        let inputs = MobileSyncLiveSnapshot.inputs(from: [
            HostFixtures.state("Codex", connected: false, usage: HostFixtures.codexUsage())
        ])
        XCTAssertNil(inputs[0].displayFilteredUsage, "the mapping drops it before the builder sees it")
    }

    /// A refresh that failed leaves the previous accepted reading in place with
    /// its original `measuredAt`. That timestamp is the whole basis of the
    /// phone's freshness display, so it must not advance because a later read
    /// failed.
    func testRetainedStaleReadingPreservesItsMeasuredAt() throws {
        let previous = HostFixtures.codexUsage()
        let stale = ProviderUsage.stale(from: previous, issue: .noData)
        let snapshot = try HostFixtures.snapshot([HostFixtures.state("Codex", usage: stale)])
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.measuredAt, HostFixtures.measuredAt)
        XCTAssertNotEqual(measurement.measuredAt, HostFixtures.generatedAt)
    }

    /// The schema has no field for an error, so a provider issue cannot reach
    /// the wire. Asserted against the encoded bytes, which is where it would
    /// actually show up.
    func testProviderErrorNeverSerializes() throws {
        let stale = ProviderUsage.stale(from: HostFixtures.codexUsage(), issue: .codexUsageUnavailable)
        let snapshot = try HostFixtures.snapshot([HostFixtures.state("Codex", usage: stale)])
        let json = String(decoding: try UsageSyncSerialization.encode(snapshot), as: UTF8.self)
        for forbidden in ["error", "issue", "unavailable", "codexUsageUnavailable", "noData"] {
            XCTAssertFalse(json.contains(forbidden), "encoded snapshot leaked \"\(forbidden)\"")
        }
    }

    func testNoMeasurementYieldsNoMeasurement() throws {
        let snapshot = try HostFixtures.snapshot([HostFixtures.state("Codex", usage: nil)])
        XCTAssertTrue(snapshot.providers[0].connected)
        XCTAssertNil(snapshot.providers[0].measurement)
    }

    // MARK: - Headline policy stays the product's

    /// The builder asks `UsageSummaryCalculator`. These pin the behaviours that
    /// would break if a mobile-specific headline rule were ever introduced.
    func testClaudeUsesFiveHourFirst() throws {
        // Weekly is the more constrained window; Claude still leads with 5h.
        let usage = HostFixtures.claudeUsage(fiveHourUsed: 10, weeklyUsed: 90)
        let snapshot = try HostFixtures.snapshot([HostFixtures.state("Claude Code", usage: usage)])
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.headlineWindowId, "five-hour")
        XCTAssertEqual(measurement.headlineRemainingPercent, 90)
    }

    func testClaudeFallsBackToOrdinaryWeeklyWithoutAFiveHourWindow() throws {
        let usage = ProviderUsage(
            name: "Claude Code",
            windows: [
                HostFixtures.window(.weekly, usedPercent: 30, durationMinutes: 10_080),
                HostFixtures.window(.weeklyScoped(scope: "opus"), usedPercent: 80, durationMinutes: 10_080)
            ],
            error: nil,
            lastSuccessfulAt: HostFixtures.measuredAt
        )
        let snapshot = try HostFixtures.snapshot([HostFixtures.state("Claude Code", usage: usage)])
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.headlineWindowId, "weekly")
        XCTAssertEqual(measurement.headlineRemainingPercent, 70)
    }

    func testCodexUsesTheMostConstrainedWindow() throws {
        let usage = HostFixtures.codexUsage(fiveHourUsed: 10, weeklyUsed: 85)
        let snapshot = try HostFixtures.snapshot([HostFixtures.state("Codex", usage: usage)])
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.headlineWindowId, "weekly")
        XCTAssertEqual(measurement.headlineRemainingPercent, 15)
    }

    func testCodexDurationWindowCanBeTheHeadline() throws {
        let usage = ProviderUsage(
            name: "Codex",
            windows: [
                HostFixtures.window(.weekly, usedPercent: 20, durationMinutes: 10_080),
                HostFixtures.window(.duration(minutes: 4_320), usedPercent: 77, durationMinutes: 4_320)
            ],
            error: nil,
            lastSuccessfulAt: HostFixtures.measuredAt
        )
        let snapshot = try HostFixtures.snapshot([HostFixtures.state("Codex", usage: usage)])
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.headlineWindowId, "duration-4320")
        XCTAssertEqual(measurement.headlineRemainingPercent, 23)
    }

    func testWindowResetTimesArePreserved() throws {
        let resetsAt = HostFixtures.measuredAt.addingTimeInterval(7_200)
        let usage = ProviderUsage(
            name: "Codex",
            windows: [HostFixtures.window(.fiveHour, usedPercent: 25, durationMinutes: 300, resetsAt: resetsAt)],
            error: nil,
            lastSuccessfulAt: HostFixtures.measuredAt
        )
        let snapshot = try HostFixtures.snapshot([HostFixtures.state("Codex", usage: usage)])
        let window = try XCTUnwrap(snapshot.providers[0].measurement?.windows.first)
        XCTAssertEqual(window.resetsAt, resetsAt)
    }

    // MARK: - Failure

    /// A corrupted reading is rejected rather than clamped, and the previously
    /// published snapshot survives. A clamped corrupt value would look entirely
    /// plausible on a phone.
    func testBuilderFailureLeavesThePreviousPublishedSnapshotInPlace() throws {
        let store = UsageSyncLiveSnapshotStore()
        XCTAssertTrue(store.publish(try HostFixtures.snapshot()))
        let good = try XCTUnwrap(store.latest)

        let corrupted = ProviderUsage(
            name: "Codex",
            windows: [HostFixtures.window(.fiveHour, usedPercent: 140, durationMinutes: 300)],
            error: nil,
            lastSuccessfulAt: HostFixtures.measuredAt
        )
        let published = store.publish {
            try MobileSyncLiveSnapshot.build(from: [HostFixtures.state("Codex", usage: corrupted)])
        }
        XCTAssertFalse(published)
        XCTAssertEqual(store.latest, good, "a failed rebuild must not blank the served snapshot")
    }
}
