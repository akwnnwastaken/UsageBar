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
