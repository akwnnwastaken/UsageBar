import XCTest
@testable import UsageBarCore

/// Collection eligibility and the preference it reads.
///
/// Every case runs against a `UserDefaults` suite of its own, emptied before
/// and after each test, so nothing here can read or write the preferences of
/// the UsageBar the developer is actually running.
///
/// The suite name is a fixed one rather than a fresh identifier per test on
/// purpose: emptying a domain leaves its backing file in the user's preferences
/// folder, so a per-test name would deposit a new stray file on every run.
final class ProviderCollectionPolicyTests: XCTestCase {
    private static let suiteName = "com.usagebar.tests.provider-collection"

    /// The legacy keys, spelled out rather than imported: they live in the
    /// application's private preference list, and these tests exist precisely
    /// to prove that the names below have no influence on collection state.
    private static let legacyCodexKey = "provider.codex.enabled"
    private static let legacyClaudeKey = "provider.claude.enabled"

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

    private func codexCollectionEnabled() -> Bool {
        ProviderCollectionPreference.isCollectionEnabled(
            in: defaults,
            forKey: ProviderCollectionPreference.codexKey
        )
    }

    private func claudeCollectionEnabled() -> Bool {
        ProviderCollectionPreference.isCollectionEnabled(
            in: defaults,
            forKey: ProviderCollectionPreference.claudeKey
        )
    }

    // MARK: - Eligibility

    func testAConnectedAndCollectionEnabledProviderIsEligible() {
        XCTAssertTrue(
            ProviderCollectionPolicy.isEligible(connected: true, collectionEnabled: true)
        )
    }

    func testPausingOrDisconnectingRemovesEligibility() {
        // A paused provider is still connected, and a disconnected one keeps
        // whatever collection preference it had, so neither fact alone decides.
        XCTAssertFalse(
            ProviderCollectionPolicy.isEligible(connected: true, collectionEnabled: false)
        )
        XCTAssertFalse(
            ProviderCollectionPolicy.isEligible(connected: false, collectionEnabled: true)
        )
        XCTAssertFalse(
            ProviderCollectionPolicy.isEligible(connected: false, collectionEnabled: false)
        )
    }

    // MARK: - Refresh plan

    func testOnlyAnEligibleProviderIsRead() {
        XCTAssertEqual(
            ProviderCollectionPolicy.action(connected: true, collectionEnabled: true),
            .collect
        )
    }

    func testAPausedProviderKeepsItsCacheAndADisconnectedOneDoesNot() {
        // The distinction the pause depends on: paused keeps the readings the
        // user is still looking at, disconnected clears them as it always has.
        XCTAssertEqual(
            ProviderCollectionPolicy.action(connected: true, collectionEnabled: false),
            .retainCache
        )
        XCTAssertEqual(
            ProviderCollectionPolicy.action(connected: false, collectionEnabled: true),
            .dropCache
        )
        XCTAssertEqual(
            ProviderCollectionPolicy.action(connected: false, collectionEnabled: false),
            .dropCache
        )
    }

    func testACycleWithNothingToReadCollectsNothing() {
        XCTAssertFalse(ProviderCollectionPolicy.collectsUsage([]))
        XCTAssertFalse(ProviderCollectionPolicy.collectsUsage([.retainCache, .dropCache]))
        XCTAssertTrue(ProviderCollectionPolicy.collectsUsage([.retainCache, .collect]))
        XCTAssertTrue(ProviderCollectionPolicy.collectsUsage([.collect, .dropCache]))
    }

    // MARK: - Acceptance

    func testACurrentResultFromAnEligibleProviderIsAccepted() {
        XCTAssertTrue(
            ProviderCollectionPolicy.shouldAccept(
                connected: true,
                collectionEnabled: true,
                launchGeneration: 3,
                currentGeneration: 3
            )
        )
    }

    func testAResultIsRejectedOnceItsProviderIsNoLongerEligible() {
        XCTAssertFalse(
            ProviderCollectionPolicy.shouldAccept(
                connected: false,
                collectionEnabled: true,
                launchGeneration: 3,
                currentGeneration: 3
            )
        )
        XCTAssertFalse(
            ProviderCollectionPolicy.shouldAccept(
                connected: true,
                collectionEnabled: false,
                launchGeneration: 3,
                currentGeneration: 3
            )
        )
    }

    func testAResultFromAnOlderGenerationIsRejected() {
        XCTAssertFalse(
            ProviderCollectionPolicy.shouldAccept(
                connected: true,
                collectionEnabled: true,
                launchGeneration: 2,
                currentGeneration: 3
            )
        )
    }

    /// Disconnect → reconnect while a read is in flight. Both bumps land before
    /// the old result returns, and the provider is fully eligible again by then
    /// — so eligibility alone would accept a reading of an account the user has
    /// since reconnected, out of order with the newer one.
    func testReconnectingDoesNotMakeAnInFlightResultCurrentAgain() {
        var generation = 4
        let launchGeneration = generation

        generation += 1 // disconnect
        generation += 1 // reconnect

        XCTAssertFalse(
            ProviderCollectionPolicy.shouldAccept(
                connected: true,
                collectionEnabled: true,
                launchGeneration: launchGeneration,
                currentGeneration: generation
            )
        )
        // The read launched after reconnecting is the one that counts.
        XCTAssertTrue(
            ProviderCollectionPolicy.shouldAccept(
                connected: true,
                collectionEnabled: true,
                launchGeneration: generation,
                currentGeneration: generation
            )
        )
    }

    /// The same race through pause → resume rather than disconnect → reconnect.
    func testResumingDoesNotMakeAnInFlightResultCurrentAgain() {
        var generation = 9
        let launchGeneration = generation

        generation += 1 // pause
        generation += 1 // resume

        XCTAssertFalse(
            ProviderCollectionPolicy.shouldAccept(
                connected: true,
                collectionEnabled: true,
                launchGeneration: launchGeneration,
                currentGeneration: generation
            )
        )
    }

    // MARK: - Coalescing

    func testResumingWhileIdleCollectsStraightAway() {
        var pending = PendingCollectionRefresh()
        XCTAssertTrue(pending.requestCollection(isRefreshing: false))
        // Nothing was deferred, so no follow-up is owed.
        XCTAssertFalse(pending.consume())
    }

    func testResumingDuringARefreshOwesExactlyOneFollowUp() {
        var pending = PendingCollectionRefresh()

        XCTAssertFalse(pending.requestCollection(isRefreshing: true))
        XCTAssertFalse(pending.requestCollection(isRefreshing: true))
        XCTAssertFalse(pending.requestCollection(isRefreshing: true))

        XCTAssertTrue(pending.consume())
        // Consuming empties the slot, so the follow-up cannot re-arm itself.
        XCTAssertFalse(pending.consume())
    }

    func testAConsumedFollowUpCanBeArmedAgainByANewResume() {
        var pending = PendingCollectionRefresh()
        XCTAssertFalse(pending.requestCollection(isRefreshing: true))
        XCTAssertTrue(pending.consume())

        XCTAssertFalse(pending.requestCollection(isRefreshing: true))
        XCTAssertTrue(pending.consume())
    }

    // MARK: - Stored preference

    func testTheCollectionKeysAreTheirOwnNames() {
        XCTAssertEqual(ProviderCollectionPreference.codexKey, "provider.codex.collection.enabled")
        XCTAssertEqual(ProviderCollectionPreference.claudeKey, "provider.claude.collection.enabled")
        XCTAssertNotEqual(ProviderCollectionPreference.codexKey, Self.legacyCodexKey)
        XCTAssertNotEqual(ProviderCollectionPreference.claudeKey, Self.legacyClaudeKey)
    }

    func testAnAbsentPreferenceMeansCollectionIsEnabled() {
        XCTAssertNil(defaults.object(forKey: ProviderCollectionPreference.codexKey))
        XCTAssertNil(defaults.object(forKey: ProviderCollectionPreference.claudeKey))

        XCTAssertTrue(codexCollectionEnabled())
        XCTAssertTrue(claudeCollectionEnabled())
    }

    func testAStoredFalsePausesCollection() {
        defaults.set(false, forKey: ProviderCollectionPreference.codexKey)
        defaults.set(false, forKey: ProviderCollectionPreference.claudeKey)

        XCTAssertFalse(codexCollectionEnabled())
        XCTAssertFalse(claudeCollectionEnabled())
    }

    func testAStoredTrueEnablesCollection() {
        defaults.set(true, forKey: ProviderCollectionPreference.codexKey)
        defaults.set(true, forKey: ProviderCollectionPreference.claudeKey)

        XCTAssertTrue(codexCollectionEnabled())
        XCTAssertTrue(claudeCollectionEnabled())
    }

    func testEachProviderReadsOnlyItsOwnPreference() {
        defaults.set(false, forKey: ProviderCollectionPreference.codexKey)

        XCTAssertFalse(codexCollectionEnabled())
        XCTAssertTrue(claudeCollectionEnabled())
    }

    // MARK: - Legacy keys

    func testALegacyDisabledProviderIsNotAPausedProvider() {
        // The upgrade that must not silently pause anybody: the user turned a
        // provider off in a build where `provider.*.enabled` meant "configured",
        // long before collection state existed.
        defaults.set(false, forKey: Self.legacyCodexKey)
        defaults.set(false, forKey: Self.legacyClaudeKey)

        XCTAssertTrue(codexCollectionEnabled())
        XCTAssertTrue(claudeCollectionEnabled())
    }

    func testALegacyEnabledProviderDoesNotDefineCollectionStateEither() {
        defaults.set(true, forKey: Self.legacyCodexKey)
        defaults.set(true, forKey: Self.legacyClaudeKey)

        // True for the same reason as an untouched install — the legacy value is
        // never consulted — so an explicitly stored pause still wins over it.
        XCTAssertTrue(codexCollectionEnabled())
        XCTAssertTrue(claudeCollectionEnabled())

        defaults.set(false, forKey: ProviderCollectionPreference.codexKey)
        XCTAssertFalse(codexCollectionEnabled())
    }
}
