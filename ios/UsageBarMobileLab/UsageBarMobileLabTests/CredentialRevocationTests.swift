import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// Two failures that look alike from a distance and must never be confused:
/// the desktop refusing a credential, and the keychain being briefly
/// unreadable because the phone is locked.
final class CredentialRevocationTests: XCTestCase {
    private func resolver(
        store: ConnectionStore,
        cache: SnapshotCaching,
        client: SnapshotFetching
    ) -> UsageSurfaceResolver {
        UsageSurfaceResolver(store: store, cache: cache, client: client)
    }

    // MARK: - Transient failures preserve everything

    /// Every failure except a definitive rejection leaves the credential and
    /// the cache alone. The Mac being asleep is the accepted tradeoff of a
    /// direct overlay, not a reason to log the user out.
    func testTransientFailuresPreserveCredentialAndCache() async throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        for failure: SnapshotFetchError in [
            .transportFailure, .rejectedByServer, .redirectRefused,
            .responseTooLarge, .unexpectedContentType, .malformedSnapshot
        ] {
            let store = InMemoryConnectionStore(connection: TestFixtures.connection)
            let cache = InMemorySnapshotCache(snapshot: cached)
            let state = await resolver(
                store: store,
                cache: cache,
                client: ScriptedFetcher(outcome: .failure(failure))
            ).resolve()

            XCTAssertEqual(state, .cached(cached), "\(failure)")
            XCTAssertNotNil(store.load(), "\(failure) must not revoke")
            XCTAssertNotNil(cache.load(), "\(failure) must not clear the cache")
            XCTAssertFalse(failure.revokesStoredCredential, "\(failure)")
        }
    }

    func testOnlyAuthenticationRejectionIsDefinitive() {
        XCTAssertTrue(SnapshotFetchError.authenticationRejected.revokesStoredCredential)
        for other: SnapshotFetchError in [
            .notConnected, .rejectedByServer, .redirectRefused, .responseTooLarge,
            .unexpectedContentType, .malformedSnapshot, .transportFailure
        ] {
            XCTAssertFalse(other.revokesStoredCredential, "\(other)")
        }
    }

    // MARK: - Definitive rejection revokes

    /// The Mac's "Revoke Paired iPhone", seen from the extension.
    func testExtensionClearsCredentialAndCacheOn401() async throws {
        let store = InMemoryConnectionStore(connection: TestFixtures.connection)
        let cache = InMemorySnapshotCache(snapshot: try TestFixtures.decodedBasicSnapshot())
        let state = await resolver(
            store: store,
            cache: cache,
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.authenticationRejected))
        ).resolve()

        XCTAssertEqual(state, .notConfigured)
        XCTAssertNil(store.load(), "the shared connection must be gone")
        XCTAssertNil(cache.load(), "the extension cache must be gone")
    }

    /// And the surfaces that read that state fall back accordingly.
    func testWidgetAndControlBecomeNotConfiguredAfter401() async throws {
        let store = InMemoryConnectionStore(connection: TestFixtures.connection)
        let cache = InMemorySnapshotCache(snapshot: try TestFixtures.decodedBasicSnapshot())
        let client = ScriptedFetcher(outcome: .failure(SnapshotFetchError.authenticationRejected))

        let entry = await UsageTimelineProvider(store: store, cache: cache, client: client)
            .currentEntry()
        XCTAssertEqual(entry.state, .notConfigured)
        XCTAssertNil(entry.snapshot)

        let freshStore = InMemoryConnectionStore(connection: TestFixtures.connection)
        let freshCache = InMemorySnapshotCache(snapshot: try TestFixtures.decodedBasicSnapshot())
        let value = try await UsageControlValueProvider(
            store: freshStore, cache: freshCache, client: client
        ).currentValue()
        XCTAssertEqual(value.availability, .notConfigured)
        XCTAssertTrue(value.headlines.isEmpty)
        XCTAssertEqual(ControlPresentation.overviewTitle(for: value), "Open UsageBar")
    }

    /// The main app, same event.
    @MainActor
    func testMainAppClearsConnectionAndCacheOn401() async throws {
        let connectionStore = InMemoryConnectionStore(connection: TestFixtures.connection)
        let cache = InMemorySnapshotCache(snapshot: try TestFixtures.decodedBasicSnapshot())
        let reloader = RecordingSurfaceReloader()
        let store = AppSnapshotStore(
            store: connectionStore,
            cache: cache,
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.authenticationRejected)),
            surfaces: reloader
        )
        await store.refresh()

        XCTAssertNil(connectionStore.load())
        XCTAssertNil(cache.load())
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.phase, .needsConnection)
        XCTAssertEqual(reloader.widgetReloadCount, 1)
        XCTAssertEqual(reloader.controlReloadCount, 1)
    }

    @MainActor
    func testMainAppKeepsEverythingOnATransientFailure() async throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        let connectionStore = InMemoryConnectionStore(connection: TestFixtures.connection)
        let cache = InMemorySnapshotCache(snapshot: cached)
        let store = AppSnapshotStore(
            store: connectionStore,
            cache: cache,
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure)),
            surfaces: RecordingSurfaceReloader()
        )
        await store.refresh()

        XCTAssertNotNil(connectionStore.load())
        XCTAssertEqual(store.snapshot, cached)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertTrue(store.lastRefreshFailed)
    }

    // MARK: - Locked is not revoked

    /// The failure this distinction exists to prevent: a widget evaluated while
    /// the phone is locked must not conclude the user disconnected and delete
    /// their data.
    func testTemporarilyUnavailableIsNotTreatedAsRevocation() async throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        let store = CountingConnectionStore(
            connection: TestFixtures.connection,
            isTemporarilyUnavailable: true
        )
        let cache = InMemorySnapshotCache(snapshot: cached)
        let fetcher = ScriptedFetcher(outcome: .success(cached))

        let state = await resolver(store: store, cache: cache, client: fetcher).resolve()

        XCTAssertEqual(state, .cached(cached), "the last validated reading stays visible")
        XCTAssertEqual(store.clearCount, 0, "the connection must not be cleared")
        XCTAssertNotNil(cache.load(), "the cache must survive a locked device")
    }

    /// And with no cache it is simply unavailable — still not revocation.
    func testTemporarilyUnavailableWithNoCacheIsUnavailable() async {
        let store = CountingConnectionStore(
            connection: TestFixtures.connection,
            isTemporarilyUnavailable: true
        )
        let cache = InMemorySnapshotCache()
        let state = await resolver(
            store: store,
            cache: cache,
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))
        ).resolve()

        XCTAssertEqual(state, .unavailable)
        XCTAssertEqual(store.clearCount, 0)
    }

    /// No credential in hand means no request. An unauthenticated fetch would
    /// be answered 401, which this surface would then correctly — and
    /// disastrously — treat as revocation.
    func testNoRequestIsMadeWithoutAnAvailableCredential() async throws {
        let fetcher = ScriptedFetcher(outcome: .success(try TestFixtures.decodedBasicSnapshot()))
        _ = await resolver(
            store: CountingConnectionStore(
                connection: TestFixtures.connection,
                isTemporarilyUnavailable: true
            ),
            cache: InMemorySnapshotCache(),
            client: fetcher
        ).resolve()
        XCTAssertEqual(fetcher.callCount, 0)

        _ = await resolver(
            store: CountingConnectionStore(),
            cache: InMemorySnapshotCache(),
            client: fetcher
        ).resolve()
        XCTAssertEqual(fetcher.callCount, 0)
    }

    /// Missing, on the other hand, *is* revocation.
    func testMissingCredentialStillRevokes() async throws {
        let store = CountingConnectionStore()
        let cache = InMemorySnapshotCache(snapshot: try TestFixtures.decodedBasicSnapshot())
        let state = await resolver(
            store: store,
            cache: cache,
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.notConnected))
        ).resolve()

        XCTAssertEqual(state, .notConfigured)
        XCTAssertNil(cache.load())
    }

    func testWidgetsAndControlsRetainCachedValuesWhileLocked() async throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        let client = ScriptedFetcher(outcome: .success(cached))

        let entry = await UsageTimelineProvider(
            store: InMemoryConnectionStore(
                connection: TestFixtures.connection, isTemporarilyUnavailable: true
            ),
            cache: InMemorySnapshotCache(snapshot: cached),
            client: client
        ).currentEntry()
        XCTAssertEqual(entry.state, .cached(cached))

        let value = try await UsageControlValueProvider(
            store: InMemoryConnectionStore(
                connection: TestFixtures.connection, isTemporarilyUnavailable: true
            ),
            cache: InMemorySnapshotCache(snapshot: cached),
            client: client
        ).currentValue()
        XCTAssertEqual(value.availability, .cached)
        XCTAssertEqual(value.headline(for: UsageProviderID.codex)?.remainingPercent, 64)
    }

    // MARK: - Accessibility is not weakened

    /// Phase 8 hardens the *interpretation* of a locked keychain. It must not
    /// loosen the protection class to avoid the problem.
    func testKeychainAccessibilityRemainsWhenUnlockedThisDeviceOnly() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Shared/KeychainConnectionStore.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("kSecAttrAccessibleWhenUnlockedThisDeviceOnly"))
        XCTAssertFalse(source.contains("AfterFirstUnlock"))
        XCTAssertFalse(source.contains("kSecAttrAccessibleAlways"))
    }
}
