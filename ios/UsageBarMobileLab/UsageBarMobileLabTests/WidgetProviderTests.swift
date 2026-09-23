import XCTest
import WidgetKit
import UsageBarSync
@testable import UsageBarMobileLab

/// The widget's timeline logic, including the rule that makes credential
/// revocation work without an App Group.
final class WidgetProviderTests: XCTestCase {
    private func makeProvider(
        store: ConnectionStore,
        cache: SnapshotCaching,
        client: SnapshotFetching
    ) -> UsageTimelineProvider {
        UsageTimelineProvider(store: store, cache: cache, client: client)
    }

    // MARK: - Revocation

    /// The core of the no-App-Group design. The app cannot reach into the
    /// extension's sandbox to delete its cache, so the widget must refuse to
    /// display an authenticated snapshot once the shared credentials are gone.
    func testMissingCredentialsYieldNotConfiguredEvenWithCache() async throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        let cache = InMemorySnapshotCache(snapshot: cached)
        let provider = makeProvider(
            store: InMemoryConnectionStore(),          // no credentials
            cache: cache,
            client: ScriptedFetcher(outcome: .success(cached))
        )

        let entry = await provider.currentEntry()
        XCTAssertEqual(entry.state, .notConfigured)
        XCTAssertNil(entry.snapshot, "a widget without credentials must show no usage")
    }

    /// And it clears the stale cache on the way past, so the data does not sit
    /// on disk indefinitely after the user disconnected.
    func testMissingCredentialsClearWidgetCache() async throws {
        let cache = InMemorySnapshotCache(snapshot: try TestFixtures.decodedBasicSnapshot())
        let provider = makeProvider(
            store: InMemoryConnectionStore(),
            cache: cache,
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.notConnected))
        )
        _ = await provider.currentEntry()
        XCTAssertNil(cache.load())
    }

    /// The fetcher must not even be consulted without credentials.
    func testNoCredentialsMeansNoRequest() async {
        let fetcher = ScriptedFetcher(outcome: .failure(SnapshotFetchError.notConnected))
        let provider = makeProvider(
            store: InMemoryConnectionStore(),
            cache: InMemorySnapshotCache(),
            client: fetcher
        )
        _ = await provider.currentEntry()
        XCTAssertEqual(fetcher.callCount, 0)
    }

    // MARK: - Normal paths

    func testSuccessfulFetchLoadsAndCaches() async throws {
        let fetched = try TestFixtures.decodedBasicSnapshot()
        let cache = InMemorySnapshotCache()
        let provider = makeProvider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: cache,
            client: ScriptedFetcher(outcome: .success(fetched))
        )

        let entry = await provider.currentEntry()
        XCTAssertEqual(entry.state, .loaded(fetched))
        XCTAssertEqual(cache.load(), fetched, "a successful fetch updates the widget's own cache")
        XCTAssertFalse(entry.isStale)
    }

    func testFailedFetchFallsBackToWidgetCache() async throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        let cache = InMemorySnapshotCache(snapshot: cached)
        let provider = makeProvider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: cache,
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))
        )

        let entry = await provider.currentEntry()
        XCTAssertEqual(entry.state, .cached(cached))
        XCTAssertTrue(entry.isStale)
        XCTAssertEqual(cache.load(), cached, "a failed fetch must not erase the cache")
    }

    func testFailedFetchWithNoCacheIsUnavailable() async {
        let provider = makeProvider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure))
        )
        let entry = await provider.currentEntry()
        XCTAssertEqual(entry.state, .unavailable)
        XCTAssertNil(entry.snapshot)
    }

    /// A schema-invalid response is a failed fetch, so the previous good
    /// reading survives it.
    func testInvalidSnapshotDoesNotOverwriteCache() async throws {
        let cached = try TestFixtures.decodedBasicSnapshot()
        let cache = InMemorySnapshotCache(snapshot: cached)
        let provider = makeProvider(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: cache,
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.malformedSnapshot))
        )
        _ = await provider.currentEntry()
        XCTAssertEqual(cache.load(), cached)
    }

    // MARK: - Scheduling

    /// A floor, not a promise: WidgetKit decides when refreshes actually run.
    func testRefreshIntervalIsConservative() {
        XCTAssertGreaterThanOrEqual(UsageTimelineProvider.refreshInterval, 15 * 60)
    }

    // MARK: - Placeholder privacy

    /// The placeholder renders before the widget is authorized to show
    /// anything, and appears in the system widget gallery.
    func testPlaceholderUsesSyntheticDataOnly() async throws {
        let real = try TestFixtures.decodedBasicSnapshot()
        let preview = WidgetPreviewData.snapshot
        XCTAssertNotEqual(preview, real)
        // Synthetic values are generated relative to "now", never decoded from
        // a stored account reading.
        XCTAssertEqual(preview.providers.map(\.providerId), ["codex", "claude-code"])
        let encoded = try UsageSyncSerialization.encode(preview)
        let text = String(decoding: encoded, as: UTF8.self).lowercased()
        for forbidden in ["ts.net", "bearer", "token", "tailscale", TestFixtures.accessKey.lowercased()] {
            XCTAssertFalse(text.contains(forbidden))
        }
    }
}
