import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// What Control Center is allowed to be told, and when.
///
/// The control provider shares `UsageSurfaceResolver` with the widget timeline
/// provider, so the revocation rule is proven once for both. These tests assert
/// the control's own behaviour on top of it: the projection onto the display
/// model, the headline source, and the fact that nothing secret can reach a
/// value the system stores.
final class ControlValueProviderTests: XCTestCase {
    private func provider(
        store: ConnectionStore,
        cache: SnapshotCaching,
        client: SnapshotFetching
    ) -> UsageControlValueProvider {
        UsageControlValueProvider(store: store, cache: cache, client: client)
    }

    // MARK: - Preview

    /// The gallery value is rendered before a control is authorized to show
    /// anything, so it must be invented outright — not a redacted real reading.
    func testPreviewValueIsSyntheticAndTouchesNothing() async throws {
        let store = CountingConnectionStore(connection: TestFixtures.connection)
        let cache = CountingSnapshotCache(snapshot: try TestFixtures.paritySnapshot("basic"))
        let fetcher = ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))

        let preview = provider(store: store, cache: cache, client: fetcher).previewValue

        XCTAssertEqual(store.loadCount, 0, "preview must not read the keychain")
        XCTAssertEqual(cache.loadCount, 0, "preview must not read the cache")
        XCTAssertEqual(fetcher.callCount, 0, "preview must not hit the network")
        XCTAssertEqual(preview.availability, .live)
        XCTAssertNil(preview.oldestMeasuredAt, "a preview has no real measurement time")
        XCTAssertEqual(preview.headlines.map(\.providerId), [UsageProviderID.codex, UsageProviderID.claude])
    }

    // MARK: - Revocation

    func testNoCredentialsYieldNotConfigured() async {
        let value = await provider(
            store: InMemoryConnectionStore(),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.notConnected))
        ).currentValueForTesting()
        XCTAssertEqual(value, .notConfigured)
    }

    /// The Phase-6 rule, applied to Control Center: a control with no shared
    /// credentials shows no usage, whatever its cache still holds.
    func testNoCredentialsNeverDisplayCachedAuthenticatedSnapshot() async throws {
        let cached = try TestFixtures.paritySnapshot("basic")
        let value = await provider(
            store: InMemoryConnectionStore(),
            cache: InMemorySnapshotCache(snapshot: cached),
            client: ScriptedFetcher(outcome: .success(cached))
        ).currentValueForTesting()

        XCTAssertEqual(value.availability, .notConfigured)
        XCTAssertTrue(value.headlines.isEmpty, "a revoked control must expose no quota")
        XCTAssertEqual(
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.codex),
            "Open UsageBar",
            "the one rendered line must say what to do, never a stale number"
        )
        XCTAssertEqual(ControlPresentation.overviewTitle(for: value), "Open UsageBar")
        XCTAssertEqual(ControlPresentation.status(for: value), "Open app to connect")
    }

    func testNoCredentialsClearTheExtensionCache() async throws {
        let cache = CountingSnapshotCache(snapshot: try TestFixtures.paritySnapshot("basic"))
        let fetcher = ScriptedFetcher(outcome: .success(try TestFixtures.paritySnapshot("basic")))
        _ = await provider(
            store: InMemoryConnectionStore(),
            cache: cache,
            client: fetcher
        ).currentValueForTesting()

        XCTAssertEqual(cache.clearCount, 1)
        XCTAssertNil(cache.storedSnapshot)
        XCTAssertEqual(fetcher.callCount, 0, "no credentials means no request at all")
    }

    // MARK: - Normal paths

    func testFetchSuccessProducesLiveValueAndUpdatesTheCache() async throws {
        let fetched = try TestFixtures.paritySnapshot("basic")
        let cache = CountingSnapshotCache()
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: cache,
            client: ScriptedFetcher(outcome: .success(fetched))
        ).currentValueForTesting()

        XCTAssertEqual(value.availability, .live)
        XCTAssertEqual(cache.storedSnapshot, fetched)
    }

    /// The value shown comes from a strictly decoded and validated snapshot —
    /// the same corpus both desktop builders are tested against.
    func testLiveValueUsesStrictlyValidatedSchemaValues() async throws {
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(try TestFixtures.paritySnapshot("basic")))
        ).currentValueForTesting()

        XCTAssertEqual(value.headline(for: UsageProviderID.codex)?.remainingPercent, 64)
        XCTAssertEqual(value.headline(for: UsageProviderID.claude)?.remainingPercent, 52)
        // Pinned against the fixture's own reset times so the countdown is exact.
        let codexResetsAt = try XCTUnwrap(value.headline(for: UsageProviderID.codex)?.resetsAt)
        let now = codexResetsAt.addingTimeInterval(-90 * 60)
        XCTAssertEqual(
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.codex, now: now),
            "Codex 5H 64% · 1h left"
        )
        XCTAssertEqual(
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.claude, now: now),
            "Claude 5H 52% · 1h left",
            "each provider counts down its own headline window"
        )
        XCTAssertEqual(ControlPresentation.overviewTitle(for: value), "Codex 64% · Claude 52%")
    }

    func testFetchFailureWithCacheShowsTheCachedReading() async throws {
        let cached = try TestFixtures.paritySnapshot("basic")
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(snapshot: cached),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))
        ).currentValueForTesting()

        XCTAssertEqual(value.availability, .cached)
        XCTAssertEqual(value.headline(for: UsageProviderID.codex)?.remainingPercent, 64)
        XCTAssertEqual(ControlPresentation.status(for: value), "Cached")
    }

    func testFetchFailureWithNoCacheIsNeutralNotAnError() async {
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))
        ).currentValueForTesting()

        XCTAssertEqual(value, .unavailable)
        XCTAssertEqual(
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.codex),
            "Codex —%"
        )
        // A status line in Control Center is not a place to explain a 502.
        XCTAssertEqual(ControlPresentation.overviewTitle(for: value), "UsageBar —%")
        XCTAssertEqual(ControlPresentation.status(for: value), "No usage data yet")
    }

    // MARK: - Headline source

    /// `headlineRemainingPercent` is the desktop's own answer. This fixture is
    /// chosen because recomputing from `windows` would give 87 rather than 45,
    /// so a control that took a second opinion would fail loudly here.
    func testDurationHeadlineUsesHeadlineRemainingPercentNotAWindow() async throws {
        let snapshot = try TestFixtures.paritySnapshot("codex-duration-headline")
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(snapshot))
        ).currentValueForTesting()

        XCTAssertEqual(value.headline(for: UsageProviderID.codex)?.remainingPercent, 45)
        XCTAssertTrue(
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.codex)
                .hasPrefix("Codex 3D 45%"),
            "the label must name the window headlineWindowId points at, not the first one"
        )
        let weeklyPercent = snapshot.providers[0].measurement?.windows
            .first { $0.kind == .weekly }?.remainingPercent
        XCTAssertEqual(weeklyPercent, 87, "fixture precondition")
    }

    func testCodexAndClaudeHeadlinesComeFromHeadlineRemainingPercent() async throws {
        let snapshot = try TestFixtures.paritySnapshot("basic")
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(snapshot))
        ).currentValueForTesting()

        for provider in snapshot.providers {
            XCTAssertEqual(
                value.headline(for: provider.providerId)?.remainingPercent,
                provider.measurement?.headlineRemainingPercent
            )
        }
    }

    /// Pausing a provider is a deliberate choice, and the desktop keeps its
    /// reading. The control keeps showing it rather than blanking.
    func testPausedProviderKeepsItsRetainedMeasurement() async throws {
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(try TestFixtures.paritySnapshot("paused-retained")))
        ).currentValueForTesting()

        XCTAssertEqual(value.headline(for: UsageProviderID.codex)?.remainingPercent, 38)
        XCTAssertTrue(
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.codex)
                .hasPrefix("Codex 5H 38%")
        )
    }

    /// A connected provider with no reading yet gets a neutral placeholder, not
    /// a zero — "0%" would mean "quota exhausted", which is a different and
    /// alarming claim.
    func testProviderWithoutMeasurementRendersNeutrally() async {
        let snapshot = UsageSyncSnapshot(
            generatedAt: Date(),
            providers: [
                UsageSyncProvider(
                    providerId: UsageProviderID.codex,
                    connected: true,
                    collecting: true,
                    measurement: nil
                )
            ]
        )
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(snapshot))
        ).currentValueForTesting()

        XCTAssertNil(value.headline(for: UsageProviderID.codex)?.remainingPercent)
        XCTAssertEqual(
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.codex),
            "Codex —%"
        )
        XCTAssertEqual(ControlPresentation.overviewTitle(for: value), "Codex —%")
    }

    // MARK: - Headline window label

    /// The window label must come from `headlineWindowId`, and the compact
    /// spellings are what fits Control Center's single line.
    func testHeadlineWindowLabelFollowsHeadlineWindowId() async throws {
        let basic = try TestFixtures.paritySnapshot("basic")
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(basic))
        ).currentValueForTesting()
        XCTAssertEqual(value.headline(for: UsageProviderID.codex)?.windowLabel, "5H")
        XCTAssertEqual(value.headline(for: UsageProviderID.claude)?.windowLabel, "5H")

        let duration = try TestFixtures.paritySnapshot("codex-duration-headline")
        let durationValue = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(duration))
        ).currentValueForTesting()
        XCTAssertEqual(durationValue.headline(for: UsageProviderID.codex)?.windowLabel, "3D")
    }

    /// This fixture's headline is the plain weekly window at 74%, while the
    /// model-scoped window beside it sits at 91%. A control that labelled or
    /// valued the wrong window would show 91 here, so the fixture proves the
    /// lookup rather than merely exercising it.
    func testWeeklyHeadlineIsLabelledAndValuedFromTheHeadlineWindow() async throws {
        let snapshot = try TestFixtures.paritySnapshot("claude-weekly-scoped")
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(snapshot))
        ).currentValueForTesting()

        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        XCTAssertEqual(measurement.headlineWindowId, "weekly", "fixture precondition")
        XCTAssertEqual(
            measurement.windows.first { $0.kind == .weeklyScoped }?.remainingPercent, 91,
            "fixture precondition"
        )

        XCTAssertEqual(value.headline(for: UsageProviderID.claude)?.windowLabel, "Weekly")
        XCTAssertEqual(value.headline(for: UsageProviderID.claude)?.remainingPercent, 74)
        XCTAssertTrue(
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.claude)
                .hasPrefix("Claude Weekly 74%")
        )
    }

    /// A model-scoped weekly window compacts to plain "Weekly": the scope has
    /// no honest short form, and the Home Screen widget shows it in full.
    func testWeeklyScopedWindowCompactsWithoutItsScope() {
        let scoped = UsageSyncWindow(
            windowId: "weekly-opus",
            kind: .weeklyScoped,
            scope: "opus",
            durationMinutes: 10080,
            remainingPercent: 91
        )
        XCTAssertEqual(WindowPresentation.compactLabel(for: scoped), "Weekly")
        // The full-width surfaces keep the scope.
        XCTAssertEqual(WindowPresentation.label(for: scoped), "Weekly · Opus")
    }

    func testCompactDurationLabelsUseTheLargestExactUnit() {
        XCTAssertEqual(WindowPresentation.compactDurationLabel(minutes: 4320), "3D")
        XCTAssertEqual(WindowPresentation.compactDurationLabel(minutes: 300), "5H")
        XCTAssertEqual(WindowPresentation.compactDurationLabel(minutes: 10080), "7D")
        XCTAssertEqual(WindowPresentation.compactDurationLabel(minutes: 90), "90M")
    }

    /// A snapshot whose `headlineWindowId` matches no window still renders a
    /// number — the percentage is the desktop's answer either way, and dropping
    /// it because a label is missing would be the wrong trade.
    func testUnresolvableHeadlineWindowStillShowsThePercentage() async {
        let snapshot = UsageSyncSnapshot(
            generatedAt: Date(),
            providers: [
                UsageSyncProvider(
                    providerId: UsageProviderID.codex,
                    connected: true,
                    collecting: true,
                    measurement: UsageSyncMeasurement(
                        measuredAt: Date(),
                        headlineRemainingPercent: 64,
                        headlineWindowId: "five-hour",
                        windows: [
                            UsageSyncWindow(
                                windowId: "five-hour",
                                kind: .fiveHour,
                                durationMinutes: 300,
                                remainingPercent: 64
                            )
                        ]
                    )
                )
            ]
        )
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(snapshot))
        ).currentValueForTesting()
        XCTAssertTrue(
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.codex)
                .hasPrefix("Codex 5H 64%")
        )

        let unlabelled = UsageControlValue(availability: .live, headlines: [
            UsageControlHeadline(
                providerId: UsageProviderID.codex,
                remainingPercent: 64,
                measuredAt: nil,
                windowLabel: nil,
                resetsAt: nil
            )
        ])
        XCTAssertEqual(
            ControlPresentation.providerTitle(for: unlabelled, providerId: UsageProviderID.codex),
            "Codex 64%"
        )
    }

    // MARK: - Freshness

    func testFreshnessComesFromMeasuredAt() async throws {
        let snapshot = try TestFixtures.paritySnapshot("basic")
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(snapshot))
        ).currentValueForTesting()

        for provider in snapshot.providers {
            XCTAssertEqual(
                value.headline(for: provider.providerId)?.measuredAt,
                provider.measurement?.measuredAt
            )
        }

        let oldest = try XCTUnwrap(snapshot.providers.compactMap(\.measurement?.measuredAt).min())
        let now = oldest.addingTimeInterval(90 * 60)
        XCTAssertEqual(ControlPresentation.status(for: value, now: now), "Updated 1 hr ago")
    }

    /// `generatedAt` advances whenever the desktop serializes, including for a
    /// reading it merely retained. If it were the freshness source, a
    /// day-old measurement would read as seconds fresh.
    func testGeneratedAtCannotSubstituteForMeasuredAt() async throws {
        let measuredAt = Date(timeIntervalSince1970: 1_772_000_000)
        let snapshot = UsageSyncSnapshot(
            generatedAt: measuredAt.addingTimeInterval(26 * 3600),
            providers: [
                UsageSyncProvider(
                    providerId: UsageProviderID.codex,
                    connected: true,
                    collecting: true,
                    measurement: UsageSyncMeasurement(
                        measuredAt: measuredAt,
                        headlineRemainingPercent: 64,
                        headlineWindowId: "five-hour",
                        windows: [
                            UsageSyncWindow(
                                windowId: "five-hour",
                                kind: .fiveHour,
                                durationMinutes: 300,
                                remainingPercent: 64
                            )
                        ]
                    )
                )
            ]
        )
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(snapshot))
        ).currentValueForTesting()

        XCTAssertEqual(value.oldestMeasuredAt, measuredAt)
        XCTAssertNotEqual(value.oldestMeasuredAt, snapshot.generatedAt)

        let now = snapshot.generatedAt
        XCTAssertEqual(ControlPresentation.status(for: value, now: now), "Updated 1 day ago")
    }

    /// One status line, possibly two providers: report the oldest, because
    /// claiming the newest would be the same lie `generatedAt` tells.
    func testStatusReportsTheOldestMeasurementNotTheNewest() {
        let recent = Date(timeIntervalSince1970: 1_772_000_000)
        let value = UsageControlValue(availability: .live, headlines: [
            UsageControlHeadline(
                providerId: UsageProviderID.codex,
                remainingPercent: 64,
                measuredAt: recent,
                windowLabel: "5H",
                resetsAt: nil
            ),
            UsageControlHeadline(
                providerId: UsageProviderID.claude,
                remainingPercent: 52,
                measuredAt: recent.addingTimeInterval(-3 * 3600),
                windowLabel: "5H",
                resetsAt: nil
            )
        ])
        XCTAssertEqual(
            ControlPresentation.status(for: value, now: recent),
            "Updated 3 hr ago"
        )
    }

    /// The countdown is last on the line precisely so a narrow control drops it
    /// first, and it is present on a cached reading too — the window keeps
    /// running whether or not the phone could reach the desktop.
    func testCachedProviderTitleStillCarriesItsCountdown() async throws {
        let cached = try TestFixtures.paritySnapshot("basic")
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(snapshot: cached),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))
        ).currentValueForTesting()

        let resetsAt = try XCTUnwrap(value.headline(for: UsageProviderID.codex)?.resetsAt)
        XCTAssertEqual(value.availability, .cached)
        XCTAssertEqual(
            ControlPresentation.providerTitle(
                for: value,
                providerId: UsageProviderID.codex,
                now: resetsAt.addingTimeInterval(-3 * 3600)
            ),
            "Codex 5H 64% · 3h left"
        )
    }

    func testCountdownUsesTheLargestWholeUnitAndFloors() {
        let reset = Date(timeIntervalSince1970: 1_772_000_000)
        func remaining(_ interval: TimeInterval) -> String? {
            FreshnessPresentation.compactTimeRemaining(until: reset, from: reset.addingTimeInterval(-interval))
        }
        XCTAssertEqual(remaining(14 * 60), "14m left")
        XCTAssertEqual(remaining(60 * 60), "1h left")
        // Floors: overstating the time left is the harmful direction.
        XCTAssertEqual(remaining(179 * 60), "2h left")
        XCTAssertEqual(remaining(3 * 24 * 3600), "3d left")
        XCTAssertEqual(remaining(30), "1m left", "a live window never reads as zero")
    }

    /// A reset that has already passed is not a countdown, and the reading it
    /// belongs to is stale by then anyway.
    func testElapsedResetProducesNoCountdown() {
        let reset = Date(timeIntervalSince1970: 1_772_000_000)
        XCTAssertNil(FreshnessPresentation.compactTimeRemaining(until: reset, from: reset))
        XCTAssertNil(
            FreshnessPresentation.compactTimeRemaining(until: reset, from: reset.addingTimeInterval(60))
        )

        let value = UsageControlValue(availability: .live, headlines: [
            UsageControlHeadline(
                providerId: UsageProviderID.codex,
                remainingPercent: 64,
                measuredAt: reset,
                windowLabel: "5H",
                resetsAt: reset
            )
        ])
        XCTAssertEqual(
            ControlPresentation.providerTitle(
                for: value, providerId: UsageProviderID.codex, now: reset.addingTimeInterval(3600)
            ),
            "Codex 5H 64%",
            "the percentage stays; only the countdown drops away"
        )
    }

    /// Schema v1 permits a window with no reset time. The control still shows
    /// the number rather than nothing.
    func testWindowWithoutResetTimeStillShowsThePercentage() {
        let value = UsageControlValue(availability: .live, headlines: [
            UsageControlHeadline(
                providerId: UsageProviderID.codex,
                remainingPercent: 64,
                measuredAt: nil,
                windowLabel: "5H",
                resetsAt: nil
            )
        ])
        XCTAssertEqual(
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.codex),
            "Codex 5H 64%"
        )
    }

    /// The countdown comes from the *headline* window's reset, not from
    /// whichever window happens to be first.
    func testCountdownFollowsTheHeadlineWindow() async throws {
        let snapshot = try TestFixtures.paritySnapshot("codex-duration-headline")
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(snapshot))
        ).currentValueForTesting()

        let measurement = try XCTUnwrap(snapshot.providers[0].measurement)
        let headlineReset = try XCTUnwrap(
            measurement.windows.first { $0.windowId == measurement.headlineWindowId }?.resetsAt
        )
        let weeklyReset = try XCTUnwrap(
            measurement.windows.first { $0.kind == .weekly }?.resetsAt
        )
        XCTAssertNotEqual(headlineReset, weeklyReset, "fixture precondition")
        XCTAssertEqual(value.headline(for: UsageProviderID.codex)?.resetsAt, headlineReset)
    }

    // MARK: - The shared network client

    /// Controls do not get their own transport. This drives the *real*
    /// `UsageSyncAPIClient` — the one whose HTTPS-only, `.ts.net`-validated,
    /// redirect-refusing, 64 KiB, JSON-only, 200-only policy is proven in
    /// `APIClientTests` — so the control inherits every one of those rules
    /// rather than restating them.
    func testControlValuesFlowThroughTheSharedHTTPSClient() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.stub.body = TestFixtures.basicSnapshotData

        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: TestFixtures.stubbedClient()
        ).currentValueForTesting()

        XCTAssertEqual(value.availability, .live)
        XCTAssertEqual(value.headline(for: UsageProviderID.codex)?.remainingPercent, 64)

        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, TestFixtures.host.value)
        for header in ["Tailscale-User-Login", "Tailscale-User-Name", "Tailscale-User-Profile-Pic"] {
            XCTAssertNil(
                request.value(forHTTPHeaderField: header),
                "a control must never assert a Tailscale identity"
            )
        }
    }

    /// A redirect would hand the bearer to whatever host answered. The shared
    /// client refuses it, and the control degrades to its cached reading.
    func testControlInheritsRedirectRefusal() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.stub.redirectTo = URL(string: "https://elsewhere.example.com/v1/usage-snapshot")

        let cached = try TestFixtures.paritySnapshot("basic")
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(snapshot: cached),
            client: TestFixtures.stubbedClient()
        ).currentValueForTesting()

        XCTAssertEqual(value.availability, .cached)
        XCTAssertEqual(StubURLProtocol.recordedRequests.count, 1, "the redirect must not be followed")
    }

    /// Whatever the value holds, it cannot hold the credential: there is no
    /// field for it. Checked against the rendered strings too, since those are
    /// what the system stores and displays.
    func testNoBearerOrHostReachesTheControlValueOrItsText() async throws {
        let value = await provider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(try TestFixtures.paritySnapshot("basic")))
        ).currentValueForTesting()

        var rendered = [
            ControlPresentation.overviewTitle(for: value),
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.codex),
            ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.claude),
            ControlPresentation.status(for: value)
        ].joined(separator: " ").lowercased()
        rendered += " " + String(describing: value).lowercased()

        for forbidden in [
            TestFixtures.accessKey.lowercased(), "bearer", "authorization",
            "ts.net", "example-tail", "usagebar-test", "tailscale", "100.", "https"
        ] {
            XCTAssertFalse(rendered.contains(forbidden), "control value leaked \"\(forbidden)\"")
        }
    }
}

private extension UsageControlValueProvider {
    /// `currentValue()` is declared `throws` by `ControlValueProvider`, but this
    /// implementation answers with a state instead of throwing — a control that
    /// threw would show the system's generic failure rather than the honest
    /// "not configured" or "cached". This keeps that expectation explicit.
    func currentValueForTesting() async -> UsageControlValue {
        do {
            return try await currentValue()
        } catch {
            XCTFail("the control provider must not throw: \(error)")
            return .unavailable
        }
    }
}
