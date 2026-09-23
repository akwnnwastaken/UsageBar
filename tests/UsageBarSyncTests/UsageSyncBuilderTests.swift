import XCTest
import UsageBarCore
@testable import UsageBarSync

/// The builder reproduces desktop semantics exactly, and reproduces nothing
/// else. Every expectation here was read off the product's own policies rather
/// than restated from the schema prose.
final class UsageSyncBuilderTests: XCTestCase {

    // MARK: provider lifecycle

    func testMinimalSnapshotCarriesOneCollectingProvider() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(Fixture.claudeSessionAndWeekly, name: "Claude Code")],
            generatedAt: Fixture.generatedAt
        )
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.generatedAt, Fixture.generatedAt)
        XCTAssertEqual(snapshot.providers.count, 1)
        XCTAssertEqual(snapshot.providers[0].providerId, "claude-code")
    }

    func testDisconnectedProviderCarriesNoMeasurement() throws {
        // Even when a reading is handed in, disconnect drops it: the desktop's
        // dropCache branch discards a disconnected provider's cache.
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(
                Fixture.claudeSessionAndWeekly,
                name: "Claude Code",
                connected: false,
                collecting: false
            )],
            generatedAt: Fixture.generatedAt
        )
        let provider = snapshot.providers[0]
        XCTAssertFalse(provider.connected)
        XCTAssertFalse(provider.collecting)
        XCTAssertNil(provider.measurement)
    }

    func testDisconnectedProviderIsNeverReportedAsCollecting() throws {
        // collecting is forced false, because a disconnected provider is not
        // read no matter what its stored preference says.
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(nil, name: "Codex", connected: false, collecting: true)],
            generatedAt: Fixture.generatedAt
        )
        XCTAssertFalse(snapshot.providers[0].collecting)
    }

    func testConnectedAndCollectingProviderCarriesItsMeasurement() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(Fixture.codexDurationHeadline, name: "Codex")],
            generatedAt: Fixture.generatedAt
        )
        let provider = snapshot.providers[0]
        XCTAssertTrue(provider.connected)
        XCTAssertTrue(provider.collecting)
        XCTAssertNotNil(provider.measurement)
    }

    func testPausedProviderKeepsItsRetainedMeasurement() throws {
        // The whole point of a pause: the reading survives it.
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(
                Fixture.claudeSessionAndWeekly,
                name: "Claude Code",
                connected: true,
                collecting: false
            )],
            generatedAt: Fixture.generatedAt
        )
        let provider = snapshot.providers[0]
        XCTAssertTrue(provider.connected)
        XCTAssertFalse(provider.collecting)
        XCTAssertEqual(provider.measurement?.measuredAt, Fixture.measuredAt)
    }

    func testConnectedProviderThatNeverSucceededHasNoMeasurement() throws {
        // windows present but never accepted: lastSuccessfulAt is what the
        // desktop sets on acceptance, so its absence means no measurement.
        let neverAccepted = ProviderUsage(
            name: "Codex",
            windows: [Fixture.window(.fiveHour, used: 10, durationMinutes: 300)],
            error: nil
        )
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(neverAccepted, name: "Codex")],
            generatedAt: Fixture.generatedAt
        )
        XCTAssertNil(snapshot.providers[0].measurement)
    }

    func testProviderWithNoUsageAtAllHasNoMeasurement() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(nil, name: "Codex")],
            generatedAt: Fixture.generatedAt
        )
        XCTAssertNil(snapshot.providers[0].measurement)
    }

    // MARK: headline policy, reused rather than reimplemented

    func testClaudePrefersFiveHourHeadline() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(Fixture.claudeSessionAndWeekly, name: "Claude Code")],
            generatedAt: Fixture.generatedAt
        )
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.headlineWindowId, "five-hour")
        XCTAssertEqual(measurement.headlineRemainingPercent, 59)
    }

    func testClaudeFallsBackToOrdinaryWeeklyHeadline() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(Fixture.claudeWeeklyOnly, name: "Claude Code")],
            generatedAt: Fixture.generatedAt
        )
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.headlineWindowId, "weekly")
        XCTAssertEqual(measurement.headlineRemainingPercent, 82)
    }

    func testClaudeCarriesOrdinaryAndScopedWeeklyTogether() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(Fixture.claudeWeeklyAndScoped, name: "Claude Code")],
            generatedAt: Fixture.generatedAt
        )
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.windows.map(\.windowId), ["weekly", "weekly-opus"])

        let scoped = try XCTUnwrap(measurement.windows.first { $0.kind == .weeklyScoped })
        XCTAssertEqual(scoped.scope, "opus")
        XCTAssertEqual(scoped.windowId, "weekly-opus")
        XCTAssertEqual(scoped.remainingPercent, 93)

        // A model-qualified weekly limit is never the headline: Claude's policy
        // falls back to the ordinary all-models window.
        XCTAssertEqual(measurement.headlineWindowId, "weekly")
    }

    func testCodexDurationWindowCanBeTheHeadline() throws {
        // The most-constrained rule scans every window, so a three-day window
        // at 45% remaining beats the weekly one at 87%.
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(Fixture.codexDurationHeadline, name: "Codex")],
            generatedAt: Fixture.generatedAt
        )
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.headlineWindowId, "duration-4320")
        XCTAssertEqual(measurement.headlineRemainingPercent, 45)

        let duration = try XCTUnwrap(measurement.windows.first { $0.kind == .duration })
        XCTAssertEqual(duration.durationMinutes, 4320)
        XCTAssertNil(duration.scope)
        XCTAssertNil(duration.position)
    }

    func testAdditionalDurationWindowIsCarriedAlongsideWeekly() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(Fixture.codexDurationHeadline, name: "Codex")],
            generatedAt: Fixture.generatedAt
        )
        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.windows.map(\.windowId), ["weekly", "duration-4320"])
    }

    func testUnknownWindowCarriesPositionAndNoDuration() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(Fixture.codexUnknownWindow, name: "Codex")],
            generatedAt: Fixture.generatedAt
        )
        let window = try XCTUnwrap(snapshot.providers[0].measurement?.windows.first)
        XCTAssertEqual(window.windowId, "unknown-0")
        XCTAssertEqual(window.kind, .unknown)
        XCTAssertEqual(window.position, 0)
        XCTAssertNil(window.durationMinutes)
        XCTAssertEqual(window.remainingPercent, 30)
    }

    // MARK: reset timestamps

    func testResetTimestampIsCarriedWhenPresent() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(Fixture.claudeSessionAndWeekly, name: "Claude Code")],
            generatedAt: Fixture.generatedAt
        )
        let window = try XCTUnwrap(
            snapshot.providers[0].measurement?.windows.first { $0.windowId == "five-hour" }
        )
        XCTAssertEqual(window.resetsAt, Fixture.date("2026-01-15T17:00:00Z"))
    }

    func testResetTimestampIsAbsentWhenProviderDidNotReportOne() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(Fixture.claudeWeeklyAndScoped, name: "Claude Code")],
            generatedAt: Fixture.generatedAt
        )
        for window in try XCTUnwrap(snapshot.providers[0].measurement).windows {
            XCTAssertNil(window.resetsAt)
        }
    }

    // MARK: freshness

    func testMeasuredAtIsRetainedIndependentlyOfGeneratedAt() throws {
        // The case the contract exists for: Codex refreshed now, Claude's
        // reading was retained from earlier, one document generated at 14:05.
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [
                Fixture.input(
                    Fixture.accepted("Codex", [Fixture.window(.fiveHour, used: 28, durationMinutes: 300)],
                                     at: Fixture.generatedAt),
                    name: "Codex"
                ),
                Fixture.input(Fixture.claudeSessionAndWeekly, name: "Claude Code")
            ],
            generatedAt: Fixture.generatedAt
        )
        XCTAssertEqual(snapshot.providers[0].measurement?.measuredAt, Fixture.generatedAt)
        XCTAssertEqual(snapshot.providers[1].measurement?.measuredAt, Fixture.measuredAt)
        XCTAssertLessThan(
            try XCTUnwrap(snapshot.providers[1].measurement).measuredAt,
            snapshot.generatedAt
        )
    }

    func testRegeneratingASnapshotDoesNotAdvanceARetainedMeasurement() throws {
        let later = Fixture.date("2026-01-15T18:00:00Z")
        let input = [Fixture.input(Fixture.claudeSessionAndWeekly, name: "Claude Code", collecting: false)]

        let first = try UsageSyncSnapshotBuilder.snapshot(from: input, generatedAt: Fixture.generatedAt)
        let second = try UsageSyncSnapshotBuilder.snapshot(from: input, generatedAt: later)

        XCTAssertEqual(first.providers[0].measurement?.measuredAt, Fixture.measuredAt)
        XCTAssertEqual(second.providers[0].measurement?.measuredAt, Fixture.measuredAt)
        XCTAssertNotEqual(first.generatedAt, second.generatedAt)
    }

    // MARK: the display filter belongs to the desktop, not here

    func testDisplayFilteredValuesArePreservedExactly() throws {
        // Whatever the call site hands in is what crosses, to the point.
        for used in [0, 1, 37, 99, 100] {
            let usage = Fixture.accepted("Codex", [Fixture.window(.fiveHour, used: used, durationMinutes: 300)])
            let snapshot = try UsageSyncSnapshotBuilder.snapshot(
                from: [Fixture.input(usage, name: "Codex")],
                generatedAt: Fixture.generatedAt
            )
            XCTAssertEqual(snapshot.providers[0].measurement?.windows.first?.remainingPercent, 100 - used)
        }
    }

    func testBuilderDoesNotHoldBackARiseTheWayTheDesktopFilterWould() throws {
        // UsageDisplayNoiseFilter holds a small rise for three consecutive
        // measurements. The builder is stateless and must apply no such rule:
        // filtering twice would make the phone lag the Mac beside it.
        let low = Fixture.accepted("Codex", [Fixture.window(.fiveHour, used: 60, durationMinutes: 300)])
        let risen = Fixture.accepted("Codex", [Fixture.window(.fiveHour, used: 57, durationMinutes: 300)])

        let firstBuild = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(low, name: "Codex")], generatedAt: Fixture.generatedAt
        )
        let secondBuild = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(risen, name: "Codex")], generatedAt: Fixture.generatedAt
        )
        XCTAssertEqual(firstBuild.providers[0].measurement?.windows.first?.remainingPercent, 40)
        XCTAssertEqual(secondBuild.providers[0].measurement?.windows.first?.remainingPercent, 43)
    }

    // MARK: the builder as a privacy boundary

    func testProviderErrorDoesNotChangeWhatIsBuilt() throws {
        // A retained-but-stale reading carries an error on the desktop. The
        // snapshot has no field for it, and its presence must not perturb
        // anything else either.
        let healthy = Fixture.claudeSessionAndWeekly
        let stale = ProviderUsage.stale(from: healthy, issue: .claudeUsageUnreadable)

        let fromHealthy = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(healthy, name: "Claude Code")], generatedAt: Fixture.generatedAt
        )
        let fromStale = try UsageSyncSnapshotBuilder.snapshot(
            from: [Fixture.input(stale, name: "Claude Code")], generatedAt: Fixture.generatedAt
        )
        XCTAssertEqual(fromHealthy, fromStale)
    }

    func testProductNameIsNormalizedAndNeverTransmittedVerbatim() throws {
        let snapshot = try UsageSyncSnapshotBuilder.snapshot(
            from: [
                Fixture.input(nil, name: "Codex"),
                Fixture.input(nil, name: "Claude Code")
            ],
            generatedAt: Fixture.generatedAt
        )
        XCTAssertEqual(snapshot.providers.map(\.providerId), ["codex", "claude-code"])
    }

    func testProviderNameThatNormalizesToNothingIsRejected() {
        XCTAssertThrowsError(
            try UsageSyncSnapshotBuilder.snapshot(
                from: [Fixture.input(nil, name: "—")],
                generatedAt: Fixture.generatedAt
            )
        ) { error in
            XCTAssertEqual(error as? UsageSyncBuilderError, .malformedProviderName)
        }
    }

    func testCorruptedPercentageIsRejectedRatherThanClamped() {
        let corrupted = ProviderUsage(
            name: "Codex",
            windows: [UsageWindow(kind: .fiveHour, usedPercent: 140, resetsAt: nil, durationMinutes: 300)],
            error: nil
        ).markedSuccessful(at: Fixture.measuredAt)

        XCTAssertThrowsError(
            try UsageSyncSnapshotBuilder.snapshot(
                from: [Fixture.input(corrupted, name: "Codex")],
                generatedAt: Fixture.generatedAt
            )
        ) { error in
            XCTAssertEqual(
                error as? UsageSyncBuilderError,
                .percentageOutOfRange(providerId: "codex", windowId: "five-hour", value: -40)
            )
        }
    }
}
