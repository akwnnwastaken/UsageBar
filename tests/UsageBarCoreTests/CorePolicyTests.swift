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
        // Sıfırlama: reset eşiği ve üzeri büyük yükseliş anında kabul edilir.
        XCTAssertEqual(rendered([4, 100, 98]), [4, 100, 98])
    }

    /// Gerçek gözlem: yeni okuyucu oturumu eski bir snapshot alınca kalan yüzde
    /// birkaç puan geri sıçrayabiliyor (33 → 38). Aralıklı geldiği için ekranda
    /// hiç görünmemeli; kalıcı bir artışsa üçüncü ölçümde gerçeğe dönmeli.
    func testStaleSnapshotReboundIsHeld() {
        let screen = rendered([33, 38, 33])
        XCTAssertEqual(screen, [33, 33, 33])
        XCTAssertFalse(zip(screen, screen.dropFirst()).contains { $1 > $0 })
        // Aynı yüksek değer üst üste sürerse gerçek artış olarak kabul edilir.
        XCTAssertEqual(rendered([33, 38, 38, 38]), [33, 33, 33, 38])
    }

    /// Reset eşiği sınırı: eşiğin altı bekletilir, eşik ve üzeri anında geçer.
    func testRiseHoldThresholdBoundary() {
        XCTAssertEqual(UsageDisplayNoiseFilter.riseHoldThreshold, 12)
        // +12 (eşik) reset kabul edilip anında gösterilir.
        XCTAssertEqual(rendered([50, 62]), [50, 62])
        // +11 (eşik altı) bekletilir; aralıklıysa hiç görünmez.
        XCTAssertEqual(rendered([50, 61, 50]), [50, 50, 50])
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

    // MARK: - Provider disconnect transition

    func testDisconnectKeepsValidSelectionOtherwiseFallsBack() {
        // Disconnecting the non-selected provider keeps the selection.
        XCTAssertEqual(
            ProviderConnectionTransition.selection(
                afterDisconnecting: "Codex",
                remaining: ["Claude Code"],
                previousSelection: "Claude Code"
            ),
            "Claude Code"
        )
        // Disconnecting the selected provider falls back to what remains.
        XCTAssertEqual(
            ProviderConnectionTransition.selection(
                afterDisconnecting: "Claude Code",
                remaining: ["Codex"],
                previousSelection: "Claude Code"
            ),
            "Codex"
        )
        // Nothing left -> no selection.
        XCTAssertNil(
            ProviderConnectionTransition.selection(
                afterDisconnecting: "Codex",
                remaining: [],
                previousSelection: "Codex"
            )
        )
    }

    func testAutoRotateTurnsOffBelowTwoProviders() {
        XCTAssertFalse(ProviderConnectionTransition.autoRotateStaysEnabled(remainingCount: 1, wasEnabled: true))
        XCTAssertFalse(ProviderConnectionTransition.autoRotateStaysEnabled(remainingCount: 0, wasEnabled: true))
        XCTAssertTrue(ProviderConnectionTransition.autoRotateStaysEnabled(remainingCount: 2, wasEnabled: true))
        XCTAssertFalse(ProviderConnectionTransition.autoRotateStaysEnabled(remainingCount: 2, wasEnabled: false))
    }

    // MARK: - Codex parsing

    func testCodexResponseParsesAndClassifiesWindows() {
        let json = """
        {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":35,"windowDurationMins":300,"resetsAt":1784740000},"secondary":{"usedPercent":12.4,"windowDurationMins":10080,"resetsAt":1785000000}}}}
        """
        let usage = UsageParser.codexResponse(from: Data(json.utf8))
        XCTAssertEqual(usage?.session?.usedPercent, 35)
        XCTAssertEqual(usage?.session?.kind, .fiveHour)
        XCTAssertEqual(usage?.weekly?.usedPercent, 12) // 12.4 rounds down
        XCTAssertEqual(usage?.weekly?.kind, .weekly)
        XCTAssertNil(usage?.error)
    }

    func testCodexResponseMissingLimitsIsUnavailable() {
        let usage = UsageParser.codexResponse(from: Data(#"{"id":2,"result":{}}"#.utf8))
        XCTAssertEqual(usage?.error?.diagnosticCode, "codex_limit_missing")
    }

    // MARK: - Claude print-mode parsing

    func testClaudePrintUsageParsesBothWindows() {
        let usage = UsageParser.claudePrintUsage("""
        Current session: 100% used · resets Jul 23 at 10:20pm (Europe/Istanbul)
        Current week (all models): 53% used · resets Jul 26 at 10pm (Europe/Istanbul)
        Last 24h · 623 requests · 8 sessions
        """)
        XCTAssertEqual(usage.session?.usedPercent, 100)
        XCTAssertEqual(usage.weekly?.usedPercent, 53)
        XCTAssertNotNil(usage.session?.resetsAt)
        XCTAssertNotNil(usage.weekly?.resetsAt) // minute-less "10pm" parses
        XCTAssertNil(usage.error)
    }

    func testClaudePrintUsageLoginAndUnreadableVerdicts() {
        if case .claudeNotLoggedIn? = UsageParser.claudePrintUsage("Please run /login").error {} else {
            XCTFail("expected claudeNotLoggedIn")
        }
        if case .claudeUsageUnreadable? = UsageParser.claudePrintUsage("noise").error {} else {
            XCTFail("expected claudeUsageUnreadable")
        }
    }

    // MARK: - Reset time zone / DST

    private func instant(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ zone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        return calendar.date(from: c)!
    }

    private func resetInstant(_ reset: String, now: Date) -> Date? {
        UsageParser.claudePrintUsage("Current session: 10% used · resets \(reset)", now: now)
            .session?.resetsAt
    }

    func testResetRollForwardUsesResetZoneAcrossDST() {
        let ist = "Europe/Istanbul"
        let ny = "America/New_York"
        XCTAssertEqual(
            resetInstant("Jul 26 at 10pm (Europe/Istanbul)", now: instant(2026, 7, 20, 12, 0, ist)),
            instant(2026, 7, 26, 22, 0, ist)
        )
        XCTAssertEqual(
            resetInstant("5pm (America/New_York)", now: instant(2026, 3, 10, 18, 0, ny)),
            instant(2026, 3, 11, 17, 0, ny)
        )
        XCTAssertEqual(
            resetInstant("4:59pm (America/New_York)", now: instant(2026, 3, 10, 12, 0, ny)),
            instant(2026, 3, 10, 16, 59, ny)
        )
        XCTAssertEqual(
            resetInstant("Jan 1 at 1am (America/New_York)", now: instant(2026, 12, 15, 12, 0, ny)),
            instant(2027, 1, 1, 1, 0, ny)
        )
        // Spring-forward: rolling 1am a day preserves the wall clock in New York.
        XCTAssertEqual(
            resetInstant("1am (America/New_York)", now: instant(2026, 3, 8, 3, 0, ny)),
            instant(2026, 3, 9, 1, 0, ny)
        )
    }

    // MARK: - Usage summary selection

    func testSummaryPrefersClaudeFiveHourThenWeekly() {
        let both = ProviderUsage(name: "Claude Code", windows: [
            UsageWindow(kind: .fiveHour, usedPercent: 41, resetsAt: nil, durationMinutes: 300),
            UsageWindow(kind: .weekly, usedPercent: 74, resetsAt: nil, durationMinutes: 10_080)
        ], error: nil)
        XCTAssertEqual(
            UsageSummaryCalculator.summary(for: "Claude Code", in: ["Claude Code": both])?.remainingPercent,
            59
        )
        let weeklyOnly = ProviderUsage(name: "Claude Code", windows: [
            UsageWindow(kind: .weekly, usedPercent: 26, resetsAt: nil, durationMinutes: 10_080)
        ], error: nil)
        let s = UsageSummaryCalculator.summary(for: "Claude Code", in: ["Claude Code": weeklyOnly])
        XCTAssertEqual(s?.remainingPercent, 74)
        XCTAssertEqual(s?.windowKind, .weekly)
    }

    func testSummaryPicksMostConstrainedCodexWindow() {
        let usage = ProviderUsage(name: "Codex", windows: [
            UsageWindow(kind: .fiveHour, usedPercent: 20, resetsAt: nil, durationMinutes: 300),
            UsageWindow(kind: .weekly, usedPercent: 74, resetsAt: nil, durationMinutes: 10_080)
        ], error: nil)
        XCTAssertEqual(
            UsageSummaryCalculator.summary(for: "Codex", in: ["Codex": usage])?.remainingPercent,
            26 // 100 - 74, the highest used
        )
    }

    // MARK: - Usage history

    func testHistoryRetainsWindowAndEnforcesMinInterval() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var samples = UsageHistoryModel.adding(remainingPercent: 50, at: base, to: [])
        // Within one minute: replaces the last sample rather than appending.
        samples = UsageHistoryModel.adding(remainingPercent: 49, at: base.addingTimeInterval(30), to: samples)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.last?.remainingPercent, 49)
        // After a minute: appends.
        samples = UsageHistoryModel.adding(remainingPercent: 48, at: base.addingTimeInterval(120), to: samples)
        XCTAssertEqual(samples.count, 2)
        // Older than 24h is dropped.
        let far = base.addingTimeInterval(25 * 60 * 60)
        samples = UsageHistoryModel.adding(remainingPercent: 40, at: far, to: samples)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.last?.remainingPercent, 40)
    }

    func testHistoryDecodeRejectsOversizedData() {
        let big = Data(count: UsageHistoryModel.maximumEncodedBytes + 1)
        XCTAssertTrue(UsageHistoryModel.decode(big).isEmpty)
        XCTAssertTrue(UsageHistoryModel.decode(Data("not json".utf8)).isEmpty)
    }

    func testChartSmoothsNoiseComputesDeltaAndResetMarkers() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func series(_ values: [Int]) -> [UsageHistorySample] {
            values.enumerated().map {
                UsageHistorySample(recordedAt: base.addingTimeInterval(Double($0.offset * 120)),
                                   remainingPercent: $0.element)
            }
        }
        // Isolated 33,34,33 one-point spike is smoothed to 33 for display only.
        let noisy = UsageHistoryChartModel(samples: series([33, 34, 33]))
        XCTAssertEqual(noisy.displaySamples.map(\.remainingPercent), [33, 33, 33])
        XCTAssertEqual(noisy.samples.map(\.remainingPercent), [33, 34, 33]) // raw kept
        // Delta is end minus start of the shown window.
        XCTAssertEqual(UsageHistoryChartModel(samples: series([50, 45, 42])).delta, -8)
    }

    /// After a reset (a >=20 upward jump), the chart restarts: it shows only the
    /// samples from the most recent reset onward, so each window is a clean arc.
    func testChartRestartsAtMostRecentReset() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func series(_ values: [Int]) -> [UsageHistorySample] {
            values.enumerated().map {
                UsageHistorySample(recordedAt: base.addingTimeInterval(Double($0.offset * 120)),
                                   remainingPercent: $0.element)
            }
        }
        // A single reset near the end: only the post-reset sample remains.
        let single = UsageHistoryChartModel(samples: series([30, 12, 95]))
        XCTAssertEqual(single.displaySamples.map(\.remainingPercent), [95])
        XCTAssertNil(single.delta)
        // Full raw history is still retained.
        XCTAssertEqual(single.samples.map(\.remainingPercent), [30, 12, 95])

        // Consumption, a reset to 100, then more consumption: the chart shows the
        // current window from the reset, and the delta is measured from there.
        let windowed = UsageHistoryChartModel(samples: series([80, 50, 30, 100, 90, 70]))
        XCTAssertEqual(windowed.displaySamples.map(\.remainingPercent), [100, 90, 70])
        XCTAssertEqual(windowed.delta, -30)

        // Two resets: the chart starts at the most recent one.
        let twoResets = UsageHistoryChartModel(samples: series([90, 40, 100, 60, 20, 95, 80]))
        XCTAssertEqual(twoResets.displaySamples.map(\.remainingPercent), [95, 80])
        XCTAssertEqual(twoResets.delta, -15)
    }
}
