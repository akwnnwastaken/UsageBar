import XCTest
@testable import UsageBarCore

final class CorePolicyTests: XCTestCase {
    func testPreferredLanguageUsesFirstSystemLanguage() {
        XCTAssertEqual(AppLanguage.preferred(from: ["tr-TR", "en-US"]), .turkish)
        XCTAssertEqual(AppLanguage.preferred(from: ["en-US", "tr-TR"]), .english)
        XCTAssertEqual(AppLanguage.preferred(from: []), .english)
    }

    func testBalancedAlertThresholds() {
        let policy = UsageAlertPolicy(isEnabled: true, preset: .balanced)
        XCTAssertEqual(policy.level(for: 21), .normal)
        XCTAssertEqual(policy.level(for: 20), .warning)
        XCTAssertEqual(policy.level(for: 10), .critical)
        XCTAssertEqual(policy.level(for: -1), .critical)
    }

    func testDisabledAlertsRemainNormal() {
        let policy = UsageAlertPolicy(isEnabled: false, preset: .early)
        XCTAssertEqual(policy.level(for: 0), .normal)
    }

    func testProviderRotationWrapsAndHandlesEmptyInput() {
        XCTAssertEqual(ProviderRotation.nextIndex(after: 0, providerCount: 2), 1)
        XCTAssertEqual(ProviderRotation.nextIndex(after: 1, providerCount: 2), 0)
        XCTAssertEqual(ProviderRotation.nextIndex(after: 8, providerCount: 0), 0)
        XCTAssertEqual(ProviderRotation.interval, 30)
    }

    func testRefreshIntervalOptionsAndDurations() {
        XCTAssertEqual(UsageRefreshInterval.allCases.map(\.minutes), [1, 2, 5])
        XCTAssertEqual(UsageRefreshInterval.oneMinute.seconds, 60)
        XCTAssertEqual(UsageRefreshInterval.twoMinutes.seconds, 120)
        XCTAssertEqual(UsageRefreshInterval.fiveMinutes.seconds, 300)
    }

    func testRefreshIntervalFallsBackToFiveMinutes() {
        XCTAssertEqual(UsageRefreshInterval.resolved(from: nil), .fiveMinutes)
        XCTAssertEqual(UsageRefreshInterval.resolved(from: ""), .fiveMinutes)
        XCTAssertEqual(UsageRefreshInterval.resolved(from: "threeMinutes"), .fiveMinutes)
        XCTAssertEqual(UsageRefreshInterval.resolved(from: "twoMinutes"), .twoMinutes)
    }

    func testMenuOpenRefreshUsesThirtySecondThreshold() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(UsageRefreshPolicy.menuOpenStalenessThreshold, 30)
        XCTAssertFalse(UsageRefreshPolicy.shouldRefreshOnMenuOpen(lastUpdated: nil, now: now))
        XCTAssertFalse(
            UsageRefreshPolicy.shouldRefreshOnMenuOpen(
                lastUpdated: now.addingTimeInterval(-30),
                now: now
            )
        )
        XCTAssertTrue(
            UsageRefreshPolicy.shouldRefreshOnMenuOpen(
                lastUpdated: now.addingTimeInterval(-31),
                now: now
            )
        )
    }
}
