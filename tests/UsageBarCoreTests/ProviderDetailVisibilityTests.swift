import XCTest
@testable import UsageBarCore

/// Per-provider detail visibility: what it stores, and what it is not allowed
/// to touch.
///
/// The feature is one preference and one rendering decision, so most of these
/// tests are about *absence* — the things that must go on behaving exactly as
/// they did when the preference did not exist. A hidden provider is still
/// collected, still eligible, still selectable, still rotated through and still
/// keeps every sample it recorded.
///
/// Every case runs against a `UserDefaults` suite of its own, emptied before
/// and after each test, so nothing here can read or write the preferences of
/// the UsageBar the developer is actually running. The suite name is fixed
/// rather than freshly generated per test because emptying a domain leaves its
/// backing file behind, and a per-test name would deposit a new stray file on
/// every run.
final class ProviderDetailVisibilityTests: XCTestCase {
    private static let suiteName = "com.usagebar.tests.provider-detail-visibility"

    /// Spelled out rather than imported: these tests exist precisely to prove
    /// that no other preference family can define detail visibility.
    private static let legacyCodexKey = "provider.codex.enabled"
    private static let legacyClaudeKey = "provider.claude.enabled"
    private static let codexConnectedKey = "provider.codex.connected"

    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = UserDefaults.standard
        super.tearDown()
    }

    private func codexDetailsVisible() -> Bool {
        ProviderDetailVisibilityPreference.areDetailsVisible(
            in: defaults,
            forKey: ProviderDetailVisibilityPreference.codexKey
        )
    }

    private func claudeDetailsVisible() -> Bool {
        ProviderDetailVisibilityPreference.areDetailsVisible(
            in: defaults,
            forKey: ProviderDetailVisibilityPreference.claudeKey
        )
    }

    // MARK: - Stored preference

    func testTheDetailVisibilityKeysAreTheirOwnNames() {
        XCTAssertEqual(ProviderDetailVisibilityPreference.codexKey, "provider.codex.details.visible")
        XCTAssertEqual(ProviderDetailVisibilityPreference.claudeKey, "provider.claude.details.visible")

        XCTAssertNotEqual(
            ProviderDetailVisibilityPreference.codexKey,
            ProviderCollectionPreference.codexKey
        )
        XCTAssertNotEqual(
            ProviderDetailVisibilityPreference.claudeKey,
            ProviderCollectionPreference.claudeKey
        )
        XCTAssertNotEqual(ProviderDetailVisibilityPreference.codexKey, Self.legacyCodexKey)
        XCTAssertNotEqual(ProviderDetailVisibilityPreference.claudeKey, Self.legacyClaudeKey)
        XCTAssertNotEqual(ProviderDetailVisibilityPreference.codexKey, Self.codexConnectedKey)
    }

    func testAnAbsentPreferenceMeansTheDetailsAreVisible() {
        // The upgrade case: 2.0.1 wrote neither key, and a bare `bool(forKey:)`
        // would answer `false` and collapse every card the user has.
        XCTAssertNil(defaults.object(forKey: ProviderDetailVisibilityPreference.codexKey))
        XCTAssertNil(defaults.object(forKey: ProviderDetailVisibilityPreference.claudeKey))

        XCTAssertTrue(codexDetailsVisible())
        XCTAssertTrue(claudeDetailsVisible())
    }

    func testAStoredFalseHidesTheDetails() {
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.claudeKey)

        XCTAssertFalse(codexDetailsVisible())
        XCTAssertFalse(claudeDetailsVisible())
    }

    func testAStoredTrueShowsTheDetails() {
        defaults.set(true, forKey: ProviderDetailVisibilityPreference.codexKey)
        defaults.set(true, forKey: ProviderDetailVisibilityPreference.claudeKey)

        XCTAssertTrue(codexDetailsVisible())
        XCTAssertTrue(claudeDetailsVisible())
    }

    func testEachProviderReadsOnlyItsOwnPreference() {
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)

        XCTAssertFalse(codexDetailsVisible())
        XCTAssertTrue(claudeDetailsVisible())
    }

    /// Restart persistence: the preference is the only thing that decides, so a
    /// fresh reader over the same stored domain answers the same way.
    func testTheStoredChoiceSurvivesARestart() throws {
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)
        defaults.set(true, forKey: ProviderDetailVisibilityPreference.claudeKey)

        let reopened = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))

        XCTAssertFalse(
            ProviderDetailVisibilityPreference.areDetailsVisible(
                in: reopened,
                forKey: ProviderDetailVisibilityPreference.codexKey
            )
        )
        XCTAssertTrue(
            ProviderDetailVisibilityPreference.areDetailsVisible(
                in: reopened,
                forKey: ProviderDetailVisibilityPreference.claudeKey
            )
        )
    }

    // MARK: - No other preference may define it

    func testAPausedProviderStillHasVisibleDetails() {
        // The two are stored apart, so pausing cannot collapse a card and
        // hiding a card cannot pause a provider.
        defaults.set(false, forKey: ProviderCollectionPreference.codexKey)
        defaults.set(false, forKey: ProviderCollectionPreference.claudeKey)

        XCTAssertTrue(codexDetailsVisible())
        XCTAssertTrue(claudeDetailsVisible())
    }

    func testHidingDetailsDoesNotPauseCollection() {
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.claudeKey)

        XCTAssertTrue(
            ProviderCollectionPreference.isCollectionEnabled(
                in: defaults,
                forKey: ProviderCollectionPreference.codexKey
            )
        )
        XCTAssertTrue(
            ProviderCollectionPreference.isCollectionEnabled(
                in: defaults,
                forKey: ProviderCollectionPreference.claudeKey
            )
        )
    }

    func testALegacyDisabledProviderDoesNotHideDetails() {
        defaults.set(false, forKey: Self.legacyCodexKey)
        defaults.set(false, forKey: Self.legacyClaudeKey)

        XCTAssertTrue(codexDetailsVisible())
        XCTAssertTrue(claudeDetailsVisible())
    }

    func testTheConnectionKeyDoesNotDefineDetailVisibilityEither() {
        // Reconnecting resumes collection, and this proves the presentation
        // preference is not carried along by that same connection state: a
        // stored `false` still reads as hidden with the provider connected.
        defaults.set(true, forKey: Self.codexConnectedKey)
        XCTAssertTrue(codexDetailsVisible())

        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)
        XCTAssertFalse(codexDetailsVisible())

        // Disconnect and reconnect: only the connection key moves, so the
        // presentation choice the user made is still there afterwards.
        defaults.set(false, forKey: Self.codexConnectedKey)
        defaults.set(true, forKey: Self.codexConnectedKey)
        XCTAssertFalse(codexDetailsVisible())
    }

    // MARK: - Card plan

    private func plan(
        collecting: Bool = true,
        visible: Bool = true,
        issue: Bool = false
    ) -> ProviderCardPlan {
        ProviderDetailPresentationPolicy.card(
            collectionEnabled: collecting,
            detailsVisible: visible,
            hasIssue: issue
        )
    }

    func testAVisibleCollectingProviderKeepsItsFullBody() {
        let card = plan()

        XCTAssertTrue(card.showsDetailBody)
        XCTAssertFalse(card.showsPausedMarker)
        XCTAssertFalse(card.showsOperationalIssue)
    }

    func testHidingTheDetailsOmitsTheWholeBodyAndNothingElse() {
        // Every usage row, reset line, history summary and chart lives in the
        // body, so one decision removes all of them together — and the heading
        // is not part of it.
        let card = plan(visible: false)

        XCTAssertFalse(card.showsDetailBody)
        XCTAssertFalse(card.showsPausedMarker)
    }

    func testAHiddenPausedProviderKeepsItsPausedMarker() {
        let card = plan(collecting: false, visible: false)

        XCTAssertTrue(card.showsPausedMarker)
        XCTAssertFalse(card.showsDetailBody)
    }

    func testAPausedProviderWithVisibleDetailsStillShowsThem() {
        // Case C of the four combinations: unchanged 2.0.1 behaviour.
        let card = plan(collecting: false, visible: true)

        XCTAssertTrue(card.showsPausedMarker)
        XCTAssertTrue(card.showsDetailBody)
    }

    func testAHiddenProviderStillReportsAnActiveCollectionFailure() {
        // Hiding quota detail must not make a broken provider look idle.
        let card = plan(visible: false, issue: true)

        XCTAssertTrue(card.showsOperationalIssue)
        XCTAssertFalse(card.showsDetailBody)
    }

    func testAPausedProviderIsStillNotBlamedForItsRetainedError() {
        for visible in [true, false] {
            let card = plan(collecting: false, visible: visible, issue: true)
            XCTAssertFalse(card.showsOperationalIssue)
        }
    }

    func testTheFourCombinationsAreIndependent() {
        // Changing one preference never moves the other's part of the plan.
        XCTAssertEqual(plan(collecting: true, visible: true).showsPausedMarker, false)
        XCTAssertEqual(plan(collecting: true, visible: false).showsPausedMarker, false)
        XCTAssertEqual(plan(collecting: false, visible: true).showsPausedMarker, true)
        XCTAssertEqual(plan(collecting: false, visible: false).showsPausedMarker, true)

        XCTAssertEqual(plan(collecting: true, visible: true).showsDetailBody, true)
        XCTAssertEqual(plan(collecting: false, visible: true).showsDetailBody, true)
        XCTAssertEqual(plan(collecting: true, visible: false).showsDetailBody, false)
        XCTAssertEqual(plan(collecting: false, visible: false).showsDetailBody, false)
    }

    // MARK: - Collection, status and rotation are untouched

    func testHiddenDetailsLeaveAProviderFullyEligible() {
        XCTAssertTrue(
            ProviderCollectionPolicy.isEligible(connected: true, collectionEnabled: true)
        )
        XCTAssertEqual(
            ProviderCollectionPolicy.action(connected: true, collectionEnabled: true),
            .collect
        )
        // The policy takes no visibility parameter at all — the strongest form
        // of "eligibility cannot depend on it".
        XCTAssertTrue(
            ProviderCollectionPolicy.shouldAccept(
                connected: true,
                collectionEnabled: true,
                launchGeneration: 4,
                currentGeneration: 4
            )
        )
    }

    func testAHiddenProviderIsStillCollectedAndStillCounted() {
        let states = [
            ProviderCollectionState(name: "Codex", connected: true, collectionEnabled: true),
            ProviderCollectionState(name: "Claude Code", connected: true, collectionEnabled: true)
        ]

        // Codex's details are hidden; nothing about these lists knows or cares.
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)

        XCTAssertEqual(ProviderStatusPolicy.connectedNames(states), ["Codex", "Claude Code"])
        XCTAssertEqual(ProviderStatusPolicy.eligibleNames(states), ["Codex", "Claude Code"])
        XCTAssertNil(ProviderStatusPolicy.idleReason(connectedCount: 2, eligibleCount: 2))
    }

    func testTheMenuBarStillSpeaksForAHiddenProvider() {
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)

        XCTAssertEqual(
            ProviderStatusPolicy.activeProviderName(
                eligible: ["Codex", "Claude Code"],
                selected: "Codex",
                autoRotate: false,
                rotatingIndex: 0
            ),
            "Codex"
        )
    }

    func testRotationStillVisitsAHiddenProvider() {
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)

        XCTAssertTrue(
            ProviderStatusPolicy.rotationIsActive(autoRotate: true, eligibleCount: 2)
        )
        XCTAssertEqual(
            ProviderStatusPolicy.activeProviderName(
                eligible: ["Codex", "Claude Code"],
                selected: nil,
                autoRotate: true,
                rotatingIndex: 0
            ),
            "Codex"
        )
    }

    func testEverythingPausedIsStillItsOwnStateWhateverTheDetailsShow() {
        let allPaused = [
            ProviderCollectionState(name: "Codex", connected: true, collectionEnabled: false),
            ProviderCollectionState(name: "Claude Code", connected: true, collectionEnabled: false)
        ]
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)
        defaults.set(true, forKey: ProviderDetailVisibilityPreference.claudeKey)

        XCTAssertEqual(
            ProviderStatusPolicy.idleReason(
                connectedCount: ProviderStatusPolicy.connectedNames(allPaused).count,
                eligibleCount: ProviderStatusPolicy.eligibleNames(allPaused).count
            ),
            .allCollectionPaused
        )
    }

    // MARK: - History and cache survive

    private let historyOrigin = Date(timeIntervalSince1970: 1_800_000_000)

    private var codexWeeklyKey: String {
        UsageHistoryRecorder.seriesKey(providerName: "Codex", windowKind: .weekly)
    }

    private func measurement(remaining: Int, at date: Date) -> [String: ProviderUsage] {
        [
            "Codex": ProviderUsage(
                name: "Codex",
                windows: [
                    UsageWindow(
                        kind: .weekly,
                        usedPercent: 100 - remaining,
                        resetsAt: nil,
                        durationMinutes: 10_080
                    )
                ],
                error: nil
            ).markedSuccessful(at: date)
        ]
    }

    func testAHiddenProviderGoesOnRecordingHistory() {
        // Recording is driven by the measurements a cycle accepted. Nothing in
        // that path can see the presentation preference, so a hidden provider
        // records exactly the samples a visible one would.
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)

        var history: [String: [UsageHistorySample]] = [:]
        for step in 0..<3 {
            let at = historyOrigin.addingTimeInterval(Double(step) * 600)
            history = UsageHistoryRecorder.recording(
                history,
                measurements: measurement(remaining: 60 - step, at: at),
                at: at
            )
        }

        XCTAssertEqual(history[codexWeeklyKey]?.map(\.remainingPercent), [60, 59, 58])
    }

    func testHidingAndShowingDetailsNeitherDeletesNorGapsTheSeries() {
        var history: [String: [UsageHistorySample]] = [:]
        history = UsageHistoryRecorder.recording(
            history,
            measurements: measurement(remaining: 60, at: historyOrigin),
            at: historyOrigin
        )

        // The user hides the card, two more cycles run, then they show it again.
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)
        for step in 1..<3 {
            let at = historyOrigin.addingTimeInterval(Double(step) * 600)
            history = UsageHistoryRecorder.recording(
                history,
                measurements: measurement(remaining: 60 - step, at: at),
                at: at
            )
        }
        defaults.set(true, forKey: ProviderDetailVisibilityPreference.codexKey)

        let samples = history[codexWeeklyKey] ?? []
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.map(\.remainingPercent), [60, 59, 58])

        // The chart the reopened card draws is the whole retained arc, not one
        // that restarted when the body came back.
        let model = UsageHistoryChartModel(samples: samples)
        XCTAssertEqual(model.displaySamples.count, 3)
        XCTAssertEqual(model.displaySamples.first?.remainingPercent, 60)
        XCTAssertEqual(model.displaySamples.last?.remainingPercent, 58)
    }

    func testRetentionIsUnchangedByTheDetailPreference() {
        var history: [String: [UsageHistorySample]] = [:]
        history = UsageHistoryRecorder.recording(
            history,
            measurements: measurement(remaining: 60, at: historyOrigin),
            at: historyOrigin
        )
        let before = history

        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)
        let after = UsageHistoryModel.sanitized(before, now: historyOrigin.addingTimeInterval(600))

        XCTAssertEqual(after[codexWeeklyKey]?.count, before[codexWeeklyKey]?.count)
        XCTAssertEqual(
            after[codexWeeklyKey]?.map(\.remainingPercent),
            before[codexWeeklyKey]?.map(\.remainingPercent)
        )
    }

    /// The cached reading a hidden card is not drawing is still the reading the
    /// menu bar speaks from.
    func testAHiddenProvidersCachedReadingStillDrivesTheMenuBar() {
        defaults.set(false, forKey: ProviderDetailVisibilityPreference.codexKey)

        let usages = measurement(remaining: 42, at: historyOrigin)
        let summary = UsageSummaryCalculator.summary(for: "Codex", in: usages)

        XCTAssertEqual(summary?.remainingPercent, 42)
    }
}
