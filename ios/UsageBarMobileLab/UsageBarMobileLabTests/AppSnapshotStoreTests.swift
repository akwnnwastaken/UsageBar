import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

@MainActor
final class AppSnapshotStoreTests: XCTestCase {
    func testStartsInSetupWhenNoConnectionSaved() {
        let store = AppSnapshotStore(
            store: InMemoryConnectionStore(),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.notConnected))
        )
        XCTAssertEqual(store.phase, .needsConnection)
        XCTAssertFalse(store.isConnected)
        XCTAssertNil(store.snapshot)
    }

    /// Cached data is on screen before any network call happens.
    func testCachedSnapshotIsShownImmediatelyOnLaunch() throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        let store = AppSnapshotStore(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(snapshot: cached),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))
        )
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.snapshot, cached)
    }

    func testSuccessfulConnectSavesCredentialAndCaches() async throws {
        let fetched = try TestFixtures.decodedBasicSnapshot()
        let connectionStore = InMemoryConnectionStore()
        let cache = InMemorySnapshotCache()
        let store = AppSnapshotStore(
            store: connectionStore,
            cache: cache,
            client: ScriptedFetcher(outcome: .success(fetched))
        )

        let result = await store.connect(host: TestFixtures.host, accessKey: TestFixtures.accessKey)
        guard case .success = result else { return XCTFail("connect should succeed") }

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.snapshot, fetched)
        XCTAssertEqual(cache.load(), fetched)
        XCTAssertEqual(connectionStore.load()?.host, TestFixtures.host)
    }

    /// A credential that does not work is not persisted, so the app cannot end
    /// up looking configured while never loading.
    func testFailedConnectDoesNotPersistCredential() async {
        let connectionStore = InMemoryConnectionStore()
        let store = AppSnapshotStore(
            store: connectionStore,
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.authenticationRejected))
        )

        let result = await store.connect(host: TestFixtures.host, accessKey: TestFixtures.accessKey)
        guard case .failure = result else { return XCTFail("connect should fail") }

        XCTAssertNil(connectionStore.load())
        XCTAssertEqual(store.phase, .needsConnection)
        XCTAssertNil(store.snapshot)
    }

    /// The behaviour that matters when the Mac is asleep.
    func testFailedRefreshPreservesCachedSnapshot() async throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        let cache = InMemorySnapshotCache(snapshot: cached)
        let store = AppSnapshotStore(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: cache,
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))
        )

        await store.refresh()

        XCTAssertEqual(store.snapshot, cached, "a failed refresh must not clear good data")
        XCTAssertEqual(cache.load(), cached)
        XCTAssertTrue(store.lastRefreshFailed)
        XCTAssertEqual(store.phase, .ready)
    }

    func testSuccessfulRefreshClearsFailureFlag() async throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        let fetcher = ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))
        let store = AppSnapshotStore(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(snapshot: cached),
            client: fetcher
        )

        await store.refresh()
        XCTAssertTrue(store.lastRefreshFailed)

        fetcher.outcome = .success(cached)
        await store.refresh()
        XCTAssertFalse(store.lastRefreshFailed)
    }

    func testRefreshDoesNothingWithoutConnection() async {
        let fetcher = ScriptedFetcher(outcome: .failure(SnapshotFetchError.notConnected))
        let store = AppSnapshotStore(
            store: InMemoryConnectionStore(),
            cache: InMemorySnapshotCache(),
            client: fetcher
        )
        await store.refresh()
        XCTAssertEqual(fetcher.callCount, 0)
    }

    /// Forgetting must take the credential, the host *and* the cached usage
    /// together -- a leftover cache would keep showing usage after disconnect.
    func testForgetConnectionClearsCredentialHostAndCache() async throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        let connectionStore = InMemoryConnectionStore(connection: TestFixtures.connection)
        let cache = InMemorySnapshotCache(snapshot: cached)
        let store = AppSnapshotStore(
            store: connectionStore,
            cache: cache,
            client: ScriptedFetcher(outcome: .success(cached))
        )

        store.forgetConnection()

        XCTAssertNil(connectionStore.load())
        XCTAssertNil(cache.load())
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isConnected)
        XCTAssertEqual(store.phase, .needsConnection)
        XCTAssertFalse(store.lastRefreshFailed)
    }
}
