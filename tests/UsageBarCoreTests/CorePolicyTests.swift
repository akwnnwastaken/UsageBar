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

    /// Ham dizinin ekrana nasıl yansıdığını hesaplar.
    private func rendered(_ rawSamples: [Int]) -> [Int] {
        var displayed: Int?
        var pendingRise: Int?
        var pendingCount = 0
        return rawSamples.map { raw in
            let decision = UsageDisplayNoiseFilter.decide(
                raw: raw,
                previouslyDisplayed: displayed,
                pendingRise: pendingRise,
                pendingCount: pendingCount
            )
            displayed = decision.displayed
            pendingRise = decision.pendingRise
            pendingCount = decision.pendingCount
            return decision.displayed
        }
    }

    func testFirstReadingIsDisplayedAsIs() {
        XCTAssertEqual(
            UsageDisplayNoiseFilter.decide(
                raw: 42,
                previouslyDisplayed: nil,
                pendingRise: nil,
                pendingCount: 0
            ),
            .init(displayed: 42, pendingRise: nil, pendingCount: 0)
        )
    }

    func testDecreasesAndLargeJumpsPassThroughUnchanged() {
        XCTAssertEqual(rendered([90, 80, 60, 59, 10]), [90, 80, 60, 59, 10])
        // Sıfırlama: büyük yükseliş anında kabul edilir.
        XCTAssertEqual(rendered([4, 100, 98]), [4, 100, 98])
        // Limit değişimi gibi +2'lik bir yükseliş de bekletilmez.
        XCTAssertEqual(rendered([41, 43]), [41, 43])
    }

    /// Gerçek gözlem: 5 saatlik pencerede kaydedilen 42, 41, 42, 42, 40 dizisi.
    /// Ekranda hiçbir noktada artış görünmemeli.
    func testObservedRoundingOscillationNeverRisesOnScreen() {
        let screen = rendered([42, 41, 42, 42, 40])
        XCTAssertEqual(screen, [42, 41, 41, 41, 40])
        XCTAssertFalse(zip(screen, screen.dropFirst()).contains { $1 > $0 })
    }

    /// Gerçek gözlem: haftalık pencerede kaydedilen 52, 51, 52 dizisi.
    func testObservedWeeklyOscillationNeverRisesOnScreen() {
        XCTAssertEqual(rendered([52, 51, 52]), [52, 51, 51])
    }

    /// Yükseliş kalıcıysa gösterim üçüncü ölçümde gerçeğe döner; bekletme
    /// süresiz bir sapmaya dönüşmemeli.
    func testSustainedRiseIsAcceptedAfterThirdReading() {
        XCTAssertEqual(UsageDisplayNoiseFilter.risePersistenceThreshold, 3)
        XCTAssertEqual(rendered([41, 42, 42, 42, 42]), [41, 41, 41, 42, 42])
    }

    /// Dalgalanma sürerken sayaç sıfırlanmalı, yoksa ilgisiz ölçümler birikip
    /// yükselişi erken kabul ettirir.
    func testInterruptedRiseRestartsThePersistenceCount() {
        XCTAssertEqual(rendered([41, 42, 41, 42, 42]), [41, 41, 41, 41, 41])
    }

    func testCodexTimeoutWinsOverSignalKilledExitStatus() {
        // A timed-out fetch that UsageBar killed leaves a non-zero status; it
        // must classify as timedOut, never commandFailed.
        XCTAssertEqual(
            CodexFetchOutcome.classify(
                hasUsage: false, outputExceeded: false, incompatible: false,
                didTimeout: true, terminationStatus: 15
            ),
            .timedOut
        )
    }

    func testCodexClassificationOrdering() {
        // usage and outputTooLarge take precedence even alongside a timeout.
        XCTAssertEqual(
            CodexFetchOutcome.classify(
                hasUsage: true, outputExceeded: false, incompatible: false,
                didTimeout: true, terminationStatus: 9
            ),
            .usage
        )
        XCTAssertEqual(
            CodexFetchOutcome.classify(
                hasUsage: false, outputExceeded: true, incompatible: true,
                didTimeout: true, terminationStatus: 9
            ),
            .outputTooLarge
        )
        // A genuine non-zero exit (no timeout) is a command failure.
        XCTAssertEqual(
            CodexFetchOutcome.classify(
                hasUsage: false, outputExceeded: false, incompatible: false,
                didTimeout: false, terminationStatus: 3
            ),
            .commandFailed
        )
        // Incompatible flag error is diagnosed before a bare command failure.
        XCTAssertEqual(
            CodexFetchOutcome.classify(
                hasUsage: false, outputExceeded: false, incompatible: true,
                didTimeout: false, terminationStatus: 1
            ),
            .incompatible
        )
        // Clean zero exit with no usage is an empty response.
        XCTAssertEqual(
            CodexFetchOutcome.classify(
                hasUsage: false, outputExceeded: false, incompatible: false,
                didTimeout: false, terminationStatus: 0
            ),
            .emptyResponse
        )
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
