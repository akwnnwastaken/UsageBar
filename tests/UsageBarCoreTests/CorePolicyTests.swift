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

    // MARK: - Codex handshake

    private func handshakeLines(appVersion: String) -> [String] {
        CodexHandshake.requestPayload(appVersion: appVersion)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private func jsonObject(_ line: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private func announcedVersion(appVersion: String) -> String? {
        let initialize = jsonObject(handshakeLines(appVersion: appVersion).first ?? "")
        let clientInfo = (initialize?["params"] as? [String: Any])?["clientInfo"] as? [String: Any]
        return clientInfo?["version"] as? String
    }

    /// Bütün el sıkışma satırları geçerli JSON kalmalı ve JSON-RPC sözleşmesi
    /// (initialize id 1, initialized, kota isteği id 2) korunmalı.
    func testCodexHandshakeKeepsItsJSONRPCContract() {
        let lines = handshakeLines(appVersion: "9.9.9-test")

        // Üç mesaj ve sondaki satır sonu.
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines.last, "")

        for line in lines.dropLast() {
            XCTAssertNotNil(jsonObject(line), "Geçersiz JSON satırı: \(line)")
        }

        let initialize = jsonObject(lines[0])
        XCTAssertEqual(initialize?["method"] as? String, CodexHandshake.initializeMethod)
        XCTAssertEqual(initialize?["method"] as? String, "initialize")
        XCTAssertEqual(initialize?["id"] as? Int, 1)

        XCTAssertEqual(jsonObject(lines[1])?["method"] as? String, "initialized")

        let rateLimits = jsonObject(lines[2])
        XCTAssertEqual(rateLimits?["method"] as? String, "account/rateLimits/read")
        XCTAssertEqual(rateLimits?["id"] as? Int, 2)
    }

    /// Beyan edilen sürüm çağıranın verdiği sürüm olmalı. İki farklı sürüm aynı
    /// sonucu verirse üretim kodu sabit bir sürüm yazıyor demektir; bu test tam
    /// olarak o gerilemede kırılır.
    func testCodexHandshakeAnnouncesTheGivenApplicationVersion() {
        XCTAssertEqual(announcedVersion(appVersion: "2.0.0"), "2.0.0")
        XCTAssertEqual(announcedVersion(appVersion: "1.9.0"), "1.9.0")
        XCTAssertEqual(announcedVersion(appVersion: "9.9.9-sentinel"), "9.9.9-sentinel")
        XCTAssertNotEqual(
            announcedVersion(appVersion: "2.0.1"),
            announcedVersion(appVersion: "2.0.0")
        )
        // Sabit bir sürüm sızmamalı: 2.0.1 yükü 2.0.0'ı hiç içermemeli.
        XCTAssertFalse(CodexHandshake.requestPayload(appVersion: "2.0.1").contains("2.0.0"))
    }

    /// Sürüm düzeltmesi istemci kimliğini değiştirmemeli; app server UsageBar'ı
    /// bu ad ve başlıkla tanıyor.
    func testCodexHandshakeClientIdentityIsUnchanged() {
        let initialize = jsonObject(handshakeLines(appVersion: "2.0.0").first ?? "")
        let clientInfo = (initialize?["params"] as? [String: Any])?["clientInfo"] as? [String: Any]

        XCTAssertEqual(clientInfo?["name"] as? String, "usage_bar")
        XCTAssertEqual(clientInfo?["title"] as? String, "UsageBar")
        XCTAssertEqual(clientInfo?.count, 3)
        XCTAssertEqual(CodexHandshake.clientName, "usage_bar")
        XCTAssertEqual(CodexHandshake.clientTitle, "UsageBar")
    }

    /// Tel üzerindeki biçim 2.0.0 ile aynı kalmalı: `initializeMessage` yükün ilk
    /// satırıdır ve tüm yük bayt bayt bu dizedir.
    func testCodexHandshakeWireFormatIsUnchanged() {
        let payload = CodexHandshake.requestPayload(appVersion: "2.0.0")

        XCTAssertEqual(
            handshakeLines(appVersion: "2.0.0").first,
            CodexHandshake.initializeMessage(appVersion: "2.0.0")
        )
        XCTAssertEqual(
            payload,
            """
            {"method":"initialize","id":1,"params":{"clientInfo":{"name":"usage_bar","title":"UsageBar","version":"2.0.0"}}}
            {"method":"initialized"}
            {"method":"account/rateLimits/read","id":2}

            """
        )
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

    /// The exact line of `shared/fixtures/claude/print-usage-weekly-only.txt`:
    /// an account that exposes no session window at all.
    func testClaudePrintUsageAcceptsWeeklyOnlyOutput() {
        let usage = UsageParser.claudePrintUsage(
            "Current week (all models): 26% used · resets Jul 29, 11:59pm (Europe/Istanbul)"
        )
        XCTAssertNil(usage.error)
        XCTAssertNil(usage.session)
        XCTAssertEqual(usage.windows.count, 1)
        XCTAssertEqual(usage.weekly?.kind, .weekly)
        XCTAssertEqual(usage.weekly?.usedPercent, 26)

        // The weekly fallback then drives the summary.
        let summary = UsageSummaryCalculator.summary(for: "Claude Code", in: ["Claude Code": usage])
        XCTAssertEqual(summary?.remainingPercent, 74)
        XCTAssertEqual(summary?.windowKind, .weekly)
    }

    /// The exact lines of `shared/fixtures/claude/print-usage-truncated.txt`: the
    /// reader waits for process exit, so this documents what the parser does if
    /// it ever saw a partially written weekly line — it keeps the complete
    /// window and invents nothing from the fragment.
    func testClaudePrintUsageIgnoresIncompleteTrailingWindow() {
        let usage = UsageParser.claudePrintUsage("""
        Current session: 12% used · resets Jul 23 at 10:20pm (Europe/Istanbul)
        Current week (all mod
        """)
        XCTAssertNil(usage.error)
        XCTAssertEqual(usage.session?.usedPercent, 12)
        XCTAssertEqual(usage.windows.count, 1)
        XCTAssertNil(usage.weekly)
    }

    /// The exact lines of `shared/fixtures/claude/print-usage-fractional-and-partial.txt`.
    func testClaudePrintUsageRoundsFractionalPercentAndAllowsMissingReset() {
        let usage = UsageParser.claudePrintUsage("""
        Current session: 8.6% used · resets Jul 23 at 5pm (Europe/Istanbul)
        Current week (all models): 47% used
        Last 24h · 640 requests · 8 sessions
        """)
        XCTAssertNil(usage.error)
        XCTAssertEqual(usage.session?.usedPercent, 9) // 8.6 rounds up
        XCTAssertNotNil(usage.session?.resetsAt)
        XCTAssertEqual(usage.weekly?.usedPercent, 47)
        XCTAssertNil(usage.weekly?.resetsAt) // no "resets" text on that row
        XCTAssertEqual(usage.windows.count, 2)
    }

    // MARK: - Claude model-specific weekly windows

    /// The exact three lines of `shared/fixtures/claude/print-usage-extra-window.txt`.
    private let extraWindowFixture = """
    Current session: 41% used · resets Jul 23 at 5pm (Europe/Istanbul)
    Current week (all models): 18% used · resets Jul 26 at 10pm (Europe/Istanbul)
    Current week (Opus): 7% used · resets Jul 26 at 10pm (Europe/Istanbul)
    """

    func testClaudePrintUsageKeepsModelSpecificWeeklyWindows() {
        let usage = UsageParser.claudePrintUsage(extraWindowFixture)
        XCTAssertNil(usage.error)
        XCTAssertEqual(usage.windows.count, 3)
        XCTAssertEqual(usage.windows.map(\.kind), [.fiveHour, .weekly, .weeklyScoped(scope: "opus")])
        XCTAssertEqual(usage.windows.map(\.usedPercent), [41, 18, 7])
        let opus = usage.windows.first { $0.kind == .weeklyScoped(scope: "opus") }
        XCTAssertEqual(opus?.durationMinutes, 10_080)
        XCTAssertNotNil(opus?.resetsAt)
    }

    func testClaudePrintUsageOrdinaryWeeklyIsTheAllModelsRowRegardlessOfOrder() {
        let opusFirst = UsageParser.claudePrintUsage("""
        Current week (Opus): 92% used · resets Jul 26 at 10pm (Europe/Istanbul)
        Current week (all models): 18% used · resets Jul 26 at 10pm (Europe/Istanbul)
        """)
        XCTAssertEqual(opusFirst.windows.count, 2)
        XCTAssertEqual(opusFirst.weekly?.usedPercent, 18)
        XCTAssertEqual(opusFirst.weekly?.kind, .weekly)
        XCTAssertNil(opusFirst.session)

        // A weekly-only account still summarises the all-models limit, never the
        // scoped one, however constrained the scoped one is.
        let summary = UsageSummaryCalculator.summary(for: "Claude Code", in: ["Claude Code": opusFirst])
        XCTAssertEqual(summary?.remainingPercent, 82)
        XCTAssertEqual(summary?.windowKind, .weekly)

        // With a session window the session still drives the summary.
        let withSession = UsageParser.claudePrintUsage("""
        Current week (Opus): 92% used
        Current session: 41% used · resets Jul 23 at 5pm (Europe/Istanbul)
        Current week (all models): 18% used
        """)
        let sessionSummary = UsageSummaryCalculator.summary(for: "Claude Code", in: ["Claude Code": withSession])
        XCTAssertEqual(sessionSummary?.remainingPercent, 59)
        XCTAssertEqual(sessionSummary?.windowKind, .fiveHour)
    }

    func testWeeklyQualifierNormalization() {
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: nil), .weekly)
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "  "), .weekly)
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "all models"), .weekly)
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: " All Models "), .weekly)
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "Opus"), .weeklyScoped(scope: "opus"))
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "Opus only"), .weeklyScoped(scope: "opus"))
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "Sonnet only"), .weeklyScoped(scope: "sonnet"))
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "Fable"), .weeklyScoped(scope: "fable"))
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "Premium models"), .weeklyScoped(scope: "premium-models"))
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "--Opus / 4.x--"), .weeklyScoped(scope: "opus-4-x"))
        // A lone "only" is not a suffix to strip; it is the whole qualifier.
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "only"), .weeklyScoped(scope: "only"))
        // Non-ASCII letters are unsupported characters, collapsed like any other.
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "Ünlü"), .weeklyScoped(scope: "nl"))
        // Nothing safe left: the row is skipped, never treated as all-models.
        XCTAssertNil(UsageWindowKind.weeklyKind(qualifier: "???"))
        XCTAssertNil(UsageWindowKind.weeklyKind(qualifier: "( )"))
        // Bounded: the slug never grows with the provider's text.
        let long = String(repeating: "a", count: 100)
        if case .weeklyScoped(let scope)? = UsageWindowKind.weeklyKind(qualifier: long) {
            XCTAssertEqual(scope.count, UsageWindowKind.maximumWeeklyScopeLength)
        } else {
            XCTFail("expected a bounded scoped kind")
        }
    }

    /// The bound is the last step of normalization, so it holds at every
    /// separator and "only" boundary — not only for one unbroken token.
    func testWeeklyScopeLengthBoundary() {
        let limit = UsageWindowKind.maximumWeeklyScopeLength
        XCTAssertEqual(limit, 32)
        func scope(_ qualifier: String) -> String? {
            if case .weeklyScoped(let scope)? = UsageWindowKind.weeklyKind(qualifier: qualifier) { return scope }
            return nil
        }
        let a = { (count: Int) in String(repeating: "a", count: count) }

        // A. One unbroken token is cut to the bound.
        XCTAssertEqual(scope(a(100)), a(32))

        // B. A separator right at the bound: the cut lands on the "-", which
        // is dropped rather than left dangling — never 33 characters.
        XCTAssertEqual(scope(a(31) + " b"), a(31))
        XCTAssertEqual(scope(a(30) + " bc"), a(30) + "-b")

        // C. A trailing "only" around the bound is removed whole, never cut to
        // a partial "-on" / "-onl".
        XCTAssertEqual(scope(a(27) + " only"), a(27))
        XCTAssertEqual(scope(a(28) + " only"), a(28))
        XCTAssertEqual(scope(a(30) + " only"), a(30))
        XCTAssertEqual(scope(a(31) + " only"), a(31))
        XCTAssertEqual(scope(a(40) + " only"), a(32))

        // D. Separator-heavy: leading/trailing/multiple separators collapse,
        // and the cut never leaves a trailing "-".
        XCTAssertEqual(scope("--" + a(30) + " / _ " + "bcd!!"), a(30) + "-b")
        XCTAssertEqual(scope("--" + a(31) + " / _ " + "bcd!!"), a(31))

        // E. The ordinary cases are untouched by the ordering.
        XCTAssertEqual(scope("Opus"), "opus")
        XCTAssertEqual(scope("Opus only"), "opus")
        XCTAssertEqual(scope("Sonnet only"), "sonnet")
        XCTAssertEqual(scope("Fable"), "fable")
        XCTAssertEqual(scope("Premium models"), "premium-models")
        XCTAssertEqual(UsageWindowKind.weeklyKind(qualifier: "all models"), .weekly)
        XCTAssertNil(UsageWindowKind.weeklyKind(qualifier: "???"))

        // Every case above, plus every prefix of a long mixed input, stays
        // within the bound and never ends with a separator.
        let mixed = "--" + a(31) + " only / " + a(40) + " only"
        for length in 0...mixed.count {
            guard let value = scope(String(mixed.prefix(length))) else { continue }
            XCTAssertLessThanOrEqual(value.count, limit, "prefix \(length)")
            XCTAssertFalse(value.hasSuffix("-"), "prefix \(length)")
        }
    }

    func testClaudePrintUsageKeepsUnknownQualifiersAndSkipsUnusableOnes() {
        let usage = UsageParser.claudePrintUsage("""
        Current session: 41% used
        Current week (Premium models): 40% used · resets Jul 26 at 10pm (Europe/Istanbul)
        Current week (???): 60% used
        """)
        XCTAssertNil(usage.error)
        XCTAssertEqual(usage.windows.map(\.kind), [.fiveHour, .weeklyScoped(scope: "premium-models")])
        let premium = usage.windows.first { $0.kind == .weeklyScoped(scope: "premium-models") }
        XCTAssertEqual(premium?.usedPercent, 40)
        XCTAssertEqual(premium?.kind.historyKey, "weekly-premium-models")
        // The unusable row did not become the ordinary weekly limit.
        XCTAssertNil(usage.weekly)
    }

    func testClaudePrintUsageKeepsTheFirstRowPerWeeklyIdentity() {
        let usage = UsageParser.claudePrintUsage("""
        Current week (all models): 18% used
        Current week (Opus): 7% used
        Current week (Opus only): 50% used
        Current week (all models): 99% used
        Current week (Sonnet only): 33% used
        """)
        XCTAssertEqual(usage.windows.map(\.kind), [.weekly, .weeklyScoped(scope: "opus"), .weeklyScoped(scope: "sonnet")])
        XCTAssertEqual(usage.windows.map(\.usedPercent), [18, 7, 33])
    }

    func testScopedWeeklyHistoryKeysAreDistinctAndAdditive() {
        XCTAssertEqual(UsageWindowKind.weekly.historyKey, "weekly")
        XCTAssertEqual(UsageWindowKind.weeklyScoped(scope: "opus").historyKey, "weekly-opus")
        XCTAssertEqual(UsageHistoryRecorder.seriesKey(providerName: "Claude Code", windowKind: .weekly), "Claude Code|weekly")
        XCTAssertEqual(
            UsageHistoryRecorder.seriesKey(providerName: "Claude Code", windowKind: .weeklyScoped(scope: "opus")),
            "Claude Code|weekly-opus"
        )
        XCTAssertNotEqual(UsageWindowKind.weekly, UsageWindowKind.weeklyScoped(scope: "opus"))
        XCTAssertNotEqual(UsageWindowKind.weeklyScoped(scope: "opus"), UsageWindowKind.weeklyScoped(scope: "sonnet"))

        // Two parsed weekly windows record into two series; the all-models
        // series keeps the all-models value instead of the scoped one.
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = UsageParser.claudePrintUsage(extraWindowFixture, now: at)
        let history = UsageHistoryRecorder.recording([:], measurements: ["Claude Code": usage], at: at)
        XCTAssertEqual(history.keys.sorted(), ["Claude Code|five-hour", "Claude Code|weekly", "Claude Code|weekly-opus"])
        XCTAssertEqual(history["Claude Code|weekly"]?.map(\.remainingPercent), [82])
        XCTAssertEqual(history["Claude Code|weekly-opus"]?.map(\.remainingPercent), [93])
    }

    func testWeeklyScopeDisplayNames() {
        XCTAssertEqual(UsageWindowKind.weeklyScopeDisplayName("opus"), "Opus")
        XCTAssertEqual(UsageWindowKind.weeklyScopeDisplayName("sonnet"), "Sonnet")
        XCTAssertEqual(UsageWindowKind.weeklyScopeDisplayName("fable"), "Fable")
        XCTAssertEqual(UsageWindowKind.weeklyScopeDisplayName("premium-models"), "Premium Models")
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

    // MARK: - Chart hover selection

    private static let hoverBase = Date(timeIntervalSince1970: 1_800_000_000)

    /// Samples at explicit offsets (seconds), so uneven spacing can be tested.
    private func hoverSeries(_ points: [(offset: Double, percent: Int)]) -> [UsageHistorySample] {
        points.map {
            UsageHistorySample(
                recordedAt: Self.hoverBase.addingTimeInterval($0.offset),
                remainingPercent: $0.percent
            )
        }
    }

    func testHoverReturnsNilForEmptySeries() {
        let empty = UsageHistoryChartModel(samples: [])
        XCTAssertNil(empty.nearestDisplaySample(toNormalizedX: 0))
        XCTAssertNil(empty.nearestDisplaySample(toNormalizedX: 0.5))
        XCTAssertNil(empty.nearestDisplaySample(toNormalizedX: 1))
    }

    func testHoverAlwaysReturnsTheOnlySample() {
        let single = UsageHistoryChartModel(samples: hoverSeries([(0, 42)]))
        for x in [CGFloat(0), 0.5, 1, -3, 4] {
            XCTAssertEqual(single.nearestDisplaySample(toNormalizedX: x)?.remainingPercent, 42)
        }
    }

    func testHoverSelectsEndsAndClampsBeyondThem() {
        let model = UsageHistoryChartModel(samples: hoverSeries([(0, 50), (120, 46), (240, 44)]))
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: 0)?.remainingPercent, 50)
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: 1)?.remainingPercent, 44)
        // Outside the chart the value clamps rather than wrapping or failing.
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: -0.4)?.remainingPercent, 50)
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: -1_000)?.remainingPercent, 50)
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: 1.4)?.remainingPercent, 44)
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: 1_000)?.remainingPercent, 44)
    }

    /// Samples are not evenly spaced in time, so the nearest one must be found
    /// by timestamp. Index-based interpolation would answer 40 here.
    func testHoverSelectsByTimestampNotArrayIndex() {
        let model = UsageHistoryChartModel(samples: hoverSeries([
            (0, 50), (3_540, 40), (3_560, 39), (3_600, 38)
        ]))
        // A quarter of the way across is still 15 minutes from the cluster of
        // late samples, so the first sample stays nearest in time.
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: 0.25)?.remainingPercent, 50)
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: 0.4)?.remainingPercent, 50)
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: 0.9)?.remainingPercent, 40)
    }

    /// A pointer exactly between two samples deterministically picks the
    /// earlier one, and never invents an interpolated percentage.
    func testHoverTieSelectsTheEarlierSampleAndNeverInterpolates() {
        let model = UsageHistoryChartModel(samples: hoverSeries([(0, 48), (300, 46)]))
        let middle = model.nearestDisplaySample(toNormalizedX: 0.5)
        XCTAssertEqual(middle?.remainingPercent, 48)
        XCTAssertEqual(middle?.recordedAt, Self.hoverBase)
        // Just past the midpoint the later sample wins.
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: 0.51)?.remainingPercent, 46)
    }

    func testHoverCannotSelectSamplesBeforeTheLatestReset() {
        let model = UsageHistoryChartModel(samples: hoverSeries([
            (0, 80), (120, 50), (240, 30), (360, 100), (480, 90), (600, 70)
        ]))
        XCTAssertEqual(model.displaySamples.map(\.remainingPercent), [100, 90, 70])
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: 0)?.remainingPercent, 100)
        // Sweeping the whole chart only ever reports drawn samples.
        for step in -20...120 {
            let selected = model.nearestDisplaySample(toNormalizedX: CGFloat(step) / 100)
            XCTAssertNotNil(selected)
            guard let selected else { continue }
            XCTAssertTrue(model.displaySamples.contains(selected))
            XCTAssertTrue([100, 90, 70].contains(selected.remainingPercent))
        }
    }

    /// The hover value must agree with the visible line, so the smoothed
    /// display value is reported for an isolated one-point spike.
    func testHoverReportsSmoothedDisplayValueNotRawNoise() {
        let model = UsageHistoryChartModel(samples: hoverSeries([(0, 33), (120, 34), (240, 33)]))
        XCTAssertEqual(model.samples.map(\.remainingPercent), [33, 34, 33])
        let middle = model.nearestDisplaySample(toNormalizedX: 0.5)
        XCTAssertEqual(middle?.recordedAt, Self.hoverBase.addingTimeInterval(120))
        XCTAssertEqual(middle?.remainingPercent, 33)
    }

    func testHoverWithDuplicateTimestampsIsDeterministic() {
        let duplicates = UsageHistoryChartModel(samples: [
            UsageHistorySample(recordedAt: Self.hoverBase, remainingPercent: 50),
            UsageHistorySample(recordedAt: Self.hoverBase, remainingPercent: 44)
        ])
        // Zero displayed duration must not divide by zero; the first displayed
        // sample answers every position.
        let expected = duplicates.displaySamples.first
        XCTAssertNotNil(expected)
        for x in [CGFloat(0), 0.25, 0.5, 1, -2, 3] {
            XCTAssertEqual(duplicates.nearestDisplaySample(toNormalizedX: x), expected)
        }
    }

    func testHoverHandlesNonFiniteInputSafely() {
        let model = UsageHistoryChartModel(samples: hoverSeries([(0, 50), (120, 46), (240, 44)]))
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: .nan)?.remainingPercent, 50)
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: -.infinity)?.remainingPercent, 50)
        XCTAssertEqual(model.nearestDisplaySample(toNormalizedX: .infinity)?.remainingPercent, 44)
    }
}
