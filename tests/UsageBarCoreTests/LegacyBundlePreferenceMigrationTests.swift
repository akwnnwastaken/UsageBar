import XCTest
@testable import UsageBarCore

/// The one-time copy of preferences from UsageBar's former bundle identifier.
///
/// UsageBar 2.3.4 and earlier stored every preference — connections, settings
/// and usage history — under `local.codex.usagebar`. The app now runs as
/// `com.akwnnwastaken.usagebar`, whose defaults domain starts empty, so without
/// this copy an upgrade would silently disconnect both providers and drop the
/// recorded history.
///
/// Every case runs against a fixed `UserDefaults` suite of its own, emptied
/// before and after each test, so nothing here can read or write the
/// preferences of the UsageBar the developer is actually running.
final class LegacyBundlePreferenceMigrationTests: XCTestCase {
    private static let suiteName = "com.usagebar.tests.legacy-bundle-migration"
    private static let currentBundle = "com.akwnnwastaken.usagebar"

    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    private var currentDomain: [String: Any] {
        defaults.persistentDomain(forName: Self.suiteName) ?? [:]
    }

    private func run(legacy: [String: Any]?, bundle: String? = currentBundle) -> Int {
        LegacyBundlePreferenceMigration.run(
            defaults: defaults,
            currentDomain: currentDomain,
            legacyDomain: legacy,
            bundleIdentifier: bundle
        )
    }

    func testIdentifiersMatchTheShippedBundles() {
        XCTAssertEqual(LegacyBundlePreferenceMigration.legacyDomain, "local.codex.usagebar")
        XCTAssertEqual(LegacyBundlePreferenceMigration.currentBundleIdentifier, Self.currentBundle)
    }

    func testCopiesEveryLegacyValueIntoAnEmptyDomain() {
        let history = Data([1, 2, 3])
        let copied = run(legacy: [
            "provider.codex.connected": true,
            "provider.claude.connected": true,
            "app.language": "tr",
            "usage.history.samples.v2": history
        ])

        XCTAssertEqual(copied, 4)
        XCTAssertTrue(defaults.bool(forKey: "provider.codex.connected"))
        XCTAssertTrue(defaults.bool(forKey: "provider.claude.connected"))
        XCTAssertEqual(defaults.string(forKey: "app.language"), "tr")
        XCTAssertEqual(defaults.data(forKey: "usage.history.samples.v2"), history)
    }

    /// Before the copy has ever run, anything already in the new domain was
    /// written by a pre-release build of the identifier change itself — for
    /// example the "not connected" fallback a first launch records. The
    /// upgrade must still restore the user's real choices.
    func testLegacyValuesWinOverValuesWrittenBeforeTheMigrationRan() {
        defaults.set(false, forKey: "provider.codex.connected")
        defaults.set("en", forKey: "app.language")
        defaults.set(true, forKey: "only.in.current")

        let copied = run(legacy: [
            "provider.codex.connected": true,
            "app.language": "tr"
        ])

        XCTAssertEqual(copied, 2)
        XCTAssertTrue(defaults.bool(forKey: "provider.codex.connected"))
        XCTAssertEqual(defaults.string(forKey: "app.language"), "tr")
        XCTAssertTrue(defaults.bool(forKey: "only.in.current"))
    }

    func testNeverTouchesTheCurrentDomainOnceTheMigrationRan() {
        XCTAssertEqual(run(legacy: [:]), 0)
        defaults.set(false, forKey: "provider.codex.connected")

        XCTAssertEqual(run(legacy: ["provider.codex.connected": true]), 0)
        XCTAssertFalse(defaults.bool(forKey: "provider.codex.connected"))
    }

    func testRunsOnlyOnce() {
        XCTAssertEqual(run(legacy: ["provider.codex.connected": true]), 1)
        defaults.removeObject(forKey: "provider.codex.connected")

        XCTAssertEqual(run(legacy: ["provider.codex.connected": true]), 0)
        XCTAssertNil(defaults.object(forKey: "provider.codex.connected"))
    }

    func testMissingLegacyDomainStillCompletesTheMigration() {
        XCTAssertEqual(run(legacy: nil), 0)
        XCTAssertEqual(run(legacy: ["provider.codex.connected": true]), 0)
        XCTAssertNil(defaults.object(forKey: "provider.codex.connected"))
    }

    func testDoesNothingOutsideTheShippedBundle() {
        for bundle in [nil, "local.codex.usagebar", "com.apple.dt.xctest.tool"] {
            XCTAssertEqual(run(legacy: ["provider.codex.connected": true], bundle: bundle), 0)
            XCTAssertNil(defaults.object(forKey: "provider.codex.connected"))
            XCTAssertNil(defaults.object(forKey: LegacyBundlePreferenceMigration.completedKey))
        }
    }

    func testALegacyCompletionMarkerIsNotCopied() {
        let copied = run(legacy: [
            LegacyBundlePreferenceMigration.completedKey: true,
            "provider.codex.connected": true
        ])

        XCTAssertEqual(copied, 1)
        XCTAssertTrue(defaults.bool(forKey: LegacyBundlePreferenceMigration.completedKey))
    }
}
