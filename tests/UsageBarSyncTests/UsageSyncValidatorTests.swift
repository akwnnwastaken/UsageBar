import XCTest
@testable import UsageBarSync

/// The three invariants JSON Schema cannot express, plus the state and
/// qualifier rules. Each case is constructed directly rather than through the
/// builder, because the builder cannot produce most of them — which is the
/// point: the validator also guards data arriving from elsewhere.
final class UsageSyncValidatorTests: XCTestCase {

    private func window(
        _ id: String,
        _ kind: UsageSyncWindowKind,
        remaining: Int = 50,
        scope: String? = nil,
        durationMinutes: Int? = nil,
        position: Int? = nil
    ) -> UsageSyncWindow {
        UsageSyncWindow(
            windowId: id, kind: kind, scope: scope,
            durationMinutes: durationMinutes, position: position,
            remainingPercent: remaining, resetsAt: nil
        )
    }

    private func measurement(
        headlineId: String = "five-hour",
        headline: Int = 50,
        windows: [UsageSyncWindow]? = nil,
        measuredAt: Date = Fixture.measuredAt
    ) -> UsageSyncMeasurement {
        UsageSyncMeasurement(
            measuredAt: measuredAt,
            headlineRemainingPercent: headline,
            headlineWindowId: headlineId,
            windows: windows ?? [window("five-hour", .fiveHour, durationMinutes: 300)]
        )
    }

    private func snapshot(_ providers: [UsageSyncProvider]) -> UsageSyncSnapshot {
        UsageSyncSnapshot(generatedAt: Fixture.generatedAt, providers: providers)
    }

    private func expect(
        _ expected: UsageSyncValidationError,
        _ subject: UsageSyncSnapshot,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try UsageSyncValidator.validate(subject), line: line) { error in
            XCTAssertEqual(error as? UsageSyncValidationError, expected, line: line)
        }
    }

    func testValidSnapshotPasses() throws {
        try UsageSyncValidator.validate(snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                              measurement: measurement())
        ]))
    }

    func testDuplicateProviderIdIsRejected() {
        expect(.duplicateProviderId("codex"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true),
            UsageSyncProvider(providerId: "codex", connected: true, collecting: false)
        ]))
    }

    func testDuplicateWindowIdWithinAProviderIsRejected() {
        expect(.duplicateWindowId(providerId: "codex", windowId: "weekly"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                measurement: measurement(headlineId: "weekly", windows: [
                    window("weekly", .weekly, durationMinutes: 10_080),
                    window("weekly", .weekly, durationMinutes: 10_080)
                ]))
        ]))
    }

    func testSameWindowIdInDifferentProvidersIsAllowed() throws {
        // Identity is scoped per provider, so this is legitimate.
        try UsageSyncValidator.validate(snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                              measurement: measurement()),
            UsageSyncProvider(providerId: "claude-code", connected: true, collecting: true,
                              measurement: measurement())
        ]))
    }

    func testUnresolvedHeadlineWindowIdIsRejected() {
        expect(.headlineWindowNotFound(providerId: "codex", headlineWindowId: "weekly"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                              measurement: measurement(headlineId: "weekly"))
        ]))
    }

    func testHeadlinePercentageMustMatchItsWindow() {
        expect(.headlineDisagreesWithWindow(providerId: "codex", windowId: "five-hour"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                              measurement: measurement(headline: 77))
        ]))
    }

    func testHeadlinePercentageOutOfRangeIsRejected() {
        expect(.percentageOutOfRange(providerId: "codex", windowId: nil, value: 101), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                              measurement: measurement(headline: 101))
        ]))
    }

    func testWindowPercentageOutOfRangeIsRejected() {
        // The headline stays valid and resolvable, so the failure can only come
        // from the non-headline window being out of range.
        expect(.percentageOutOfRange(providerId: "codex", windowId: "weekly", value: -1), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                measurement: measurement(windows: [
                    window("five-hour", .fiveHour, durationMinutes: 300),
                    window("weekly", .weekly, remaining: -1, durationMinutes: 10_080)
                ]))
        ]))
    }

    func testDisconnectedProviderWithMeasurementIsRejected() {
        expect(.disconnectedProviderHasMeasurement(providerId: "codex"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: false, collecting: false,
                              measurement: measurement())
        ]))
    }

    func testDisconnectedProviderThatIsCollectingIsRejected() {
        expect(.disconnectedProviderIsCollecting(providerId: "codex"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: false, collecting: true)
        ]))
    }

    func testMeasuredAfterGeneratedIsRejected() {
        let future = Fixture.date("2026-01-15T14:06:00Z")
        expect(.measuredAfterGenerated(providerId: "codex"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                              measurement: measurement(measuredAt: future))
        ]))
    }

    func testMeasurementWithNoWindowsIsRejected() {
        expect(.emptyWindows(providerId: "codex"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                              measurement: measurement(windows: []))
        ]))
    }

    // MARK: qualifier consistency

    func testWeeklyScopedWithoutScopeIsRejected() {
        expect(.missingQualifier(providerId: "codex", windowId: "weekly-opus",
                                 kind: .weeklyScoped, qualifier: "scope"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                measurement: measurement(headlineId: "weekly-opus", windows: [
                    window("weekly-opus", .weeklyScoped, durationMinutes: 10_080)
                ]))
        ]))
    }

    func testDurationWithoutDurationMinutesIsRejected() {
        expect(.missingQualifier(providerId: "codex", windowId: "duration-4320",
                                 kind: .duration, qualifier: "durationMinutes"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                measurement: measurement(headlineId: "duration-4320", windows: [
                    window("duration-4320", .duration)
                ]))
        ]))
    }

    func testUnknownWithoutPositionIsRejected() {
        expect(.missingQualifier(providerId: "codex", windowId: "unknown-0",
                                 kind: .unknown, qualifier: "position"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                measurement: measurement(headlineId: "unknown-0", windows: [
                    window("unknown-0", .unknown)
                ]))
        ]))
    }

    func testScopeOnAnOrdinaryWeeklyWindowIsRejected() {
        expect(.unexpectedQualifier(providerId: "codex", windowId: "weekly",
                                    kind: .weekly, qualifier: "scope"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                measurement: measurement(headlineId: "weekly", windows: [
                    window("weekly", .weekly, scope: "opus", durationMinutes: 10_080)
                ]))
        ]))
    }

    func testPositionOnAFiveHourWindowIsRejected() {
        expect(.unexpectedQualifier(providerId: "codex", windowId: "five-hour",
                                    kind: .fiveHour, qualifier: "position"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                measurement: measurement(windows: [
                    window("five-hour", .fiveHour, durationMinutes: 300, position: 0)
                ]))
        ]))
    }

    func testDurationOnAnUnknownWindowIsRejected() {
        expect(.unexpectedQualifier(providerId: "codex", windowId: "unknown-0",
                                    kind: .unknown, qualifier: "durationMinutes"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                measurement: measurement(headlineId: "unknown-0", windows: [
                    window("unknown-0", .unknown, durationMinutes: 300, position: 0)
                ]))
        ]))
    }

    func testWindowIdThatDisagreesWithItsKindIsRejected() {
        expect(.windowIdDisagreesWithKind(providerId: "codex", windowId: "weekly-sonnet",
                                          expected: "weekly-opus"), snapshot([
            UsageSyncProvider(providerId: "codex", connected: true, collecting: true,
                measurement: measurement(headlineId: "weekly-sonnet", windows: [
                    window("weekly-sonnet", .weeklyScoped, scope: "opus", durationMinutes: 10_080)
                ]))
        ]))
    }

    func testMalformedProviderIdIsRejected() {
        expect(.malformedProviderId("Claude Code"), snapshot([
            UsageSyncProvider(providerId: "Claude Code", connected: true, collecting: false)
        ]))
    }

    func testUnsupportedSchemaVersionIsRejected() {
        expect(.unsupportedSchemaVersion(found: 2, expected: 1),
               UsageSyncSnapshot(schemaVersion: 2, generatedAt: Fixture.generatedAt, providers: []))
    }

    func testEmptyProviderListIsValidAndMeansNothingConnected() throws {
        try UsageSyncValidator.validate(snapshot([]))
    }
}
