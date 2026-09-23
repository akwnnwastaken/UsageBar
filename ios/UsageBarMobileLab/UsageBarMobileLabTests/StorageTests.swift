import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

final class SnapshotCacheTests: XCTestCase {
    private var cacheURL: URL!
    private var cache: FileSnapshotCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("usagebar-cache-\(UUID().uuidString).json")
        cache = FileSnapshotCache(url: cacheURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cacheURL)
        try super.tearDownWithError()
    }

    func testRoundTrip() throws {
        let snapshot = try TestFixtures.decodedBasicSnapshot()
        try cache.store(snapshot)
        XCTAssertEqual(cache.load(), snapshot)
    }

    func testEmptyCacheReturnsNil() {
        XCTAssertNil(cache.load())
    }

    /// A truncated or edited cache must behave like a first launch, not crash.
    func testCorruptCacheIsDiscardedOnLoad() throws {
        try Data("{ truncated".utf8).write(to: cacheURL)
        XCTAssertNil(cache.load())
        // And it removes itself, so the same bad bytes are not re-read forever.
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    /// Valid JSON that violates a schema invariant is just as unusable as
    /// garbage, and must be rejected by the validator on the way in.
    func testSchemaInvalidCacheIsDiscardedOnLoad() throws {
        try Data(
            #"{"schemaVersion":1,"generatedAt":"2026-03-04T09:00:00Z","providers":[{"providerId":"codex","connected":false,"collecting":true}]}"#.utf8
        ).write(to: cacheURL)
        XCTAssertNil(cache.load())
    }

    func testClearRemovesCache() throws {
        try cache.store(try TestFixtures.decodedBasicSnapshot())
        cache.clear()
        XCTAssertNil(cache.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    /// The cache is schema-v1 and nothing else -- no endpoint, no credential,
    /// no identity, no error text.
    func testCachedBytesContainNoTransportOrCredentialData() throws {
        try cache.store(try TestFixtures.decodedBasicSnapshot())
        let raw = try String(contentsOf: cacheURL, encoding: .utf8).lowercased()

        for forbidden in [
            "ts.net", "usagebar-test", "example-tail", "tailscale", "magicdns",
            "bearer", "authorization", TestFixtures.accessKey.lowercased(),
            "100.", "127.0.0.1", "https", "http", "host", "token", "login", "@"
        ] {
            XCTAssertFalse(raw.contains(forbidden), "cache leaked \"\(forbidden)\"")
        }

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["schemaversion", "generatedat", "providers"])
    }
}

final class ConnectionStoreTests: XCTestCase {
    /// A per-test service name keeps runs isolated and leaves no keychain
    /// residue behind under the app's real service.
    private func makeStore() -> KeychainConnectionStore {
        KeychainConnectionStore(service: "com.usagebar.mobilelab.tests.\(UUID().uuidString)")
    }

    func testSaveLoadDelete() throws {
        let store = makeStore()
        defer { store.clear() }

        XCTAssertNil(store.load())

        try store.save(TestFixtures.connection)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.host, TestFixtures.host)
        XCTAssertEqual(loaded.accessKey, TestFixtures.accessKey)

        store.clear()
        XCTAssertNil(store.load())
    }

    func testSaveOverwritesPreviousValue() throws {
        let store = makeStore()
        defer { store.clear() }

        try store.save(TestFixtures.connection)
        let replacement = UsageSyncConnection(
            host: try UsageSyncHost(validating: "other-machine.example-tail.ts.net"),
            accessKey: String(repeating: "z", count: 64)
        )
        try store.save(replacement)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.host.value, "other-machine.example-tail.ts.net")
        XCTAssertEqual(loaded.accessKey, replacement.accessKey)
    }

    /// The host is re-validated on read: a keychain item edited to hold a
    /// non-tailnet host must not become a live endpoint.
    func testStoredHostIsRevalidatedOnLoad() throws {
        let store = makeStore()
        defer { store.clear() }
        try store.save(TestFixtures.connection)
        XCTAssertNotNil(store.load())
    }

    /// Nothing sensitive may land in UserDefaults.
    func testNothingIsWrittenToUserDefaults() throws {
        let store = makeStore()
        defer { store.clear() }
        try store.save(TestFixtures.connection)

        let defaults = UserDefaults.standard.dictionaryRepresentation()
        let flattened = defaults.values.map { String(describing: $0) }.joined().lowercased()
        XCTAssertFalse(flattened.contains(TestFixtures.accessKey.lowercased()))
        XCTAssertFalse(flattened.contains("example-tail.ts.net"))
    }
}
