import XCTest
import UsageBarPairing
import UsageBarSync
@testable import UsageBarMobileLab

/// The QR exchange: what the phone will accept from a scanned code, and what it
/// insists on before anything reaches the keychain.
final class PairingClientTests: XCTestCase {
    private let host = "usagebar-test.example-tail.ts.net"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func client() -> UsageSyncPairingClient {
        let configuration = UsageSyncAPIClient.privateConfiguration()
        configuration.protocolClasses = [StubURLProtocol.self]
        return UsageSyncPairingClient(configuration: configuration)
    }

    private func payload(host: String? = nil) throws -> UsageBarPairingPayload {
        try UsageBarPairingPayload(host: host ?? self.host, pairingCode: .generate())
    }

    private func issued(_ key: String = String(repeating: "k", count: 43)) -> Data {
        Data(#"{"schemaVersion":1,"accessKey":"\#(key)"}"#.utf8)
    }

    // MARK: - Request shape

    func testPairRequestUsesPostToThePairingPath() async throws {
        StubURLProtocol.stub.body = issued()
        _ = try await client().exchange(payload: try payload())

        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, host)
        XCTAssertEqual(request.url?.path, "/v1/pair")
    }

    /// The code goes in a header under its own scheme. A URL, a query string or
    /// a path would put a live secret into proxy logs and request history.
    func testPairingCodeTravelsOnlyInTheAuthorizationHeader() async throws {
        StubURLProtocol.stub.body = issued()
        let payload = try payload()
        _ = try await client().exchange(payload: payload)

        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        let encoded = payload.pairingCode.encoded
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "UsageBar-Pair \(encoded)"
        )
        XCTAssertFalse(request.url?.absoluteString.contains(encoded) ?? true)
        XCTAssertNil(request.url?.query)
        XCTAssertNil(request.httpBody, "pairing needs no body at all")
    }

    func testPairRequestEmitsNoTailscaleIdentityHeader() async throws {
        StubURLProtocol.stub.body = issued()
        _ = try await client().exchange(payload: try payload())

        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        for header in ["Tailscale-User-Login", "Tailscale-User-Name", "Tailscale-User-Profile-Pic"] {
            XCTAssertNil(request.value(forHTTPHeaderField: header))
        }
    }

    // MARK: - Response policy

    func testValidResponseYieldsTheAccessKey() async throws {
        let key = String(repeating: "a", count: 43)
        StubURLProtocol.stub.body = issued(key)
        let paired = try await client().exchange(payload: try payload())
        XCTAssertEqual(paired.accessKey, key)
        XCTAssertEqual(paired.host.value, host)
    }

    /// A redirect would re-issue the request — carrying the live pairing code —
    /// at whatever host answered.
    func testRedirectIsRefused() async throws {
        StubURLProtocol.stub.redirectTo = URL(string: "https://elsewhere.example.com/v1/pair")
        await assertFails(try await client().exchange(payload: try payload()))
        XCTAssertEqual(StubURLProtocol.recordedRequests.count, 1)
    }

    func testNonSuccessStatusRejected() async throws {
        for status in [201, 302, 400, 401, 403, 404, 500, 503] {
            StubURLProtocol.reset()
            StubURLProtocol.stub.statusCode = status
            StubURLProtocol.stub.body = issued()
            await assertFails(try await client().exchange(payload: try payload()), "\(status)")
        }
    }

    func testOversizedResponseRejected() async throws {
        StubURLProtocol.stub.body = Data(
            repeating: 0x20,
            count: UsageSyncPairingClient.maximumResponseBytes + 1
        )
        await assertFails(try await client().exchange(payload: try payload()))
    }

    func testPairingResponseCeilingIsFourKiB() {
        XCTAssertEqual(UsageSyncPairingClient.maximumResponseBytes, 4 * 1024)
    }

    func testNonJSONContentTypeRejected() async throws {
        StubURLProtocol.stub.headers = ["Content-Type": "text/html"]
        StubURLProtocol.stub.body = issued()
        await assertFails(try await client().exchange(payload: try payload()))
    }

    func testMalformedOrIncompleteJSONRejected() async throws {
        for body in [
            "not json",
            "{}",
            #"{"schemaVersion":2,"accessKey":"aaa"}"#,
            #"{"schemaVersion":1}"#,
            #"{"schemaVersion":1,"accessKey":""}"#,
            #"{"schemaVersion":1,"accessKey":123}"#
        ] {
            StubURLProtocol.reset()
            StubURLProtocol.stub.body = Data(body.utf8)
            await assertFails(try await client().exchange(payload: try payload()), body)
        }
    }

    func testOverlongAccessKeyRejected() async throws {
        StubURLProtocol.stub.body = issued(String(repeating: "k", count: 300))
        await assertFails(try await client().exchange(payload: try payload()))
    }

    func testTransportFailureReported() async throws {
        StubURLProtocol.stub.error = URLError(.cannotConnectToHost)
        await assertFails(try await client().exchange(payload: try payload()))
    }

    /// Every pairing failure reads the same on screen. Telling the user which
    /// part of a forged or stale QR nearly worked helps a bystander more.
    func testEveryPairingErrorRendersTheSameSentence() {
        let descriptions = Set(
            [PairingError.invalidCode, .refused, .transportFailure, .malformedResponse]
                .map(\.description)
        )
        XCTAssertEqual(descriptions.count, 1)
        let text = try! XCTUnwrap(descriptions.first).lowercased()
        for forbidden in ["401", "http", "json", "token", "expired", "replay", "identity"] {
            XCTAssertFalse(text.contains(forbidden))
        }
    }

    // MARK: - The endpoint validator is authoritative

    /// The payload's own check is structural. Before a URL is built, the real
    /// endpoint validator runs — and this is what keeps a hostile QR from
    /// deciding where the pairing code is sent.
    func testHostIsRevalidatedByTheEndpointValidatorBeforeAnyRequest() async {
        // A host the payload accepts structurally but that the endpoint
        // validator must still be the one to approve.
        let structurallyValid = "a-b.c-d.ts.net"
        XCTAssertNoThrow(try UsageBarPairingPayload(host: structurallyValid, pairingCode: .generate()))
        XCTAssertNoThrow(try UsageSyncHost(validating: structurallyValid))

        // And nothing is requested when the validator refuses.
        StubURLProtocol.reset()
        XCTAssertThrowsError(try UsageBarPairingPayload(host: "evil.example.com", pairingCode: .generate()))
        XCTAssertTrue(StubURLProtocol.recordedRequests.isEmpty)
    }

    func testPairingURLIsBuiltFromTheValidatedHostOnly() throws {
        let validated = try UsageSyncHost(validating: host)
        XCTAssertEqual(validated.pairingURL.absoluteString, "https://\(host)/v1/pair")
        XCTAssertEqual(validated.snapshotURL.absoluteString, "https://\(host)/v1/snapshot")
    }

    // MARK: - Nothing persists before the credential is proven

    /// The bearer is held in memory, used for a real snapshot fetch, and only
    /// written to the keychain once that fetch decodes and validates. A
    /// credential that cannot fetch would otherwise leave the app looking
    /// configured and permanently failing.
    @MainActor
    func testAccessKeyIsNotPersistedUntilASnapshotVerifies() async throws {
        let connectionStore = InMemoryConnectionStore()
        let cache = InMemorySnapshotCache()
        let store = AppSnapshotStore(
            store: connectionStore,
            cache: cache,
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.authenticationRejected)),
            surfaces: RecordingSurfaceReloader()
        )
        let paired = PairedConnection(
            host: try UsageSyncHost(validating: host),
            accessKey: String(repeating: "k", count: 43)
        )

        guard case .failure = await store.completePairing(paired) else {
            return XCTFail("verification must fail")
        }
        XCTAssertNil(connectionStore.load(), "an unproven key must not be stored")
        XCTAssertNil(cache.load())
        XCTAssertEqual(store.phase, .needsConnection)
    }

    @MainActor
    func testSuccessfulPairingPersistsAndReloadsSurfaces() async throws {
        let connectionStore = InMemoryConnectionStore()
        let reloader = RecordingSurfaceReloader()
        let fetched = try TestFixtures.decodedBasicSnapshot()
        let store = AppSnapshotStore(
            store: connectionStore,
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(fetched)),
            surfaces: reloader
        )
        let paired = PairedConnection(
            host: try UsageSyncHost(validating: host),
            accessKey: String(repeating: "k", count: 43)
        )

        guard case .success = await store.completePairing(paired) else {
            return XCTFail("pairing should succeed")
        }
        XCTAssertEqual(connectionStore.load()?.accessKey, paired.accessKey)
        XCTAssertEqual(store.snapshot, fetched)
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(reloader.widgetReloadCount, 1)
        XCTAssertEqual(reloader.controlReloadCount, 1)
    }

    private func assertFails<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("expected failure \(message)", file: file, line: line)
        } catch {
            // Expected.
        }
    }
}
