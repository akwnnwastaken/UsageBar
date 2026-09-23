import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

final class APIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Request shape

    func testRequestTargetsHTTPSSnapshotEndpoint() async throws {
        StubURLProtocol.stub.body = TestFixtures.basicSnapshotData
        _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)

        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.path, "/v1/snapshot")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testAuthorizationBearerHeaderIsSent() async throws {
        StubURLProtocol.stub.body = TestFixtures.basicSnapshotData
        _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)

        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer \(TestFixtures.accessKey)"
        )
    }

    /// Serve owns the identity headers. A client that set one would merely be
    /// asserting an identity, and the desktop would be trusting a value the
    /// caller chose.
    func testAppNeverSendsTailscaleIdentityHeaders() async throws {
        StubURLProtocol.stub.body = TestFixtures.basicSnapshotData
        _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)

        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        for header in ["Tailscale-User-Login", "Tailscale-User-Name", "Tailscale-User-Profile-Pic"] {
            XCTAssertNil(
                request.value(forHTTPHeaderField: header),
                "app must never set \(header)"
            )
        }
        let names = (request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }
        XCTAssertFalse(names.contains { $0.hasPrefix("tailscale-") })
    }

    // MARK: - Redirects

    /// Following a redirect would re-send the Authorization header to whatever
    /// host the response named.
    func testRedirectIsRefusedAndBearerNotForwarded() async throws {
        for statusCode in [301, 302, 307, 308] {
            StubURLProtocol.reset()
            StubURLProtocol.stub.redirectTo = URL(string: "https://attacker.example.invalid/v1/snapshot")!
            StubURLProtocol.stub.redirectStatusCode = statusCode

            do {
                _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
                XCTFail("redirect \(statusCode) should have been refused")
            } catch {
                XCTAssertEqual(error as? SnapshotFetchError, .redirectRefused)
            }

            // Exactly one request: the original. No second request means the
            // bearer never reached the redirect target.
            XCTAssertEqual(StubURLProtocol.recordedRequests.count, 1, "status \(statusCode)")
            let hosts = StubURLProtocol.recordedRequests.compactMap(\.url?.host)
            XCTAssertFalse(hosts.contains("attacker.example.invalid"))
        }
    }

    // MARK: - Status and content type

    func testStatus200WithJSONIsAccepted() async throws {
        StubURLProtocol.stub.body = TestFixtures.basicSnapshotData
        let snapshot = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.providers.count, 2)
    }

    func testUnauthorizedStatusesReportUnauthorized() async {
        for statusCode in [401, 403] {
            StubURLProtocol.reset()
            StubURLProtocol.stub.statusCode = statusCode
            StubURLProtocol.stub.body = TestFixtures.basicSnapshotData
            do {
                _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
                XCTFail("status \(statusCode) should fail")
            } catch {
                XCTAssertEqual(error as? SnapshotFetchError, .authenticationRejected)
            }
        }
    }

    func testNonSuccessStatusesAreRejected() async {
        for statusCode in [400, 404, 405, 413, 431, 500, 503] {
            StubURLProtocol.reset()
            StubURLProtocol.stub.statusCode = statusCode
            StubURLProtocol.stub.body = TestFixtures.basicSnapshotData
            do {
                _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
                XCTFail("status \(statusCode) should fail")
            } catch {
                XCTAssertEqual(error as? SnapshotFetchError, .rejectedByServer)
            }
        }
    }

    func testNonJSONContentTypeIsRejected() async {
        StubURLProtocol.stub.headers = ["Content-Type": "text/html; charset=utf-8"]
        StubURLProtocol.stub.body = TestFixtures.basicSnapshotData
        do {
            _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
            XCTFail("non-JSON content type should fail")
        } catch {
            XCTAssertEqual(error as? SnapshotFetchError, .unexpectedContentType)
        }
    }

    func testJSONContentTypeWithCharsetIsAccepted() async throws {
        StubURLProtocol.stub.headers = ["Content-Type": "application/json; charset=utf-8"]
        StubURLProtocol.stub.body = TestFixtures.basicSnapshotData
        let snapshot = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
        XCTAssertEqual(snapshot.providers.count, 2)
    }

    // MARK: - Size bound

    func testOversizedResponseIsRejected() async {
        // Larger than the ceiling, and not valid JSON either -- the point is
        // that it is refused on size before anything tries to parse it.
        StubURLProtocol.stub.body = Data(
            repeating: UInt8(ascii: "a"),
            count: UsageSyncAPIClient.maximumResponseBytes + 1_024
        )
        do {
            _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
            XCTFail("oversized response should fail")
        } catch {
            XCTAssertEqual(error as? SnapshotFetchError, .responseTooLarge)
        }
    }

    func testMaximumResponseSizeIsSixtyFourKiB() {
        XCTAssertEqual(UsageSyncAPIClient.maximumResponseBytes, 65_536)
    }

    // MARK: - Payload validation

    func testMalformedJSONIsRejected() async {
        StubURLProtocol.stub.body = Data("{ not json".utf8)
        do {
            _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
            XCTFail("malformed JSON should fail")
        } catch {
            XCTAssertEqual(error as? SnapshotFetchError, .malformedSnapshot)
        }
    }

    /// Well-formed JSON that breaks a schema invariant must be refused by the
    /// validator, not merely by the decoder.
    func testSchemaInvalidSnapshotIsRejected() async {
        StubURLProtocol.stub.body = Data("""
        {
          "schemaVersion": 1,
          "generatedAt": "2026-03-04T09:00:00Z",
          "providers": [
            {
              "providerId": "codex",
              "connected": true,
              "collecting": true,
              "measurement": {
                "measuredAt": "2026-03-04T09:00:00Z",
                "headlineRemainingPercent": 64,
                "headlineWindowId": "does-not-exist",
                "windows": [
                  { "windowId": "five-hour", "kind": "fiveHour", "durationMinutes": 300, "remainingPercent": 64 }
                ]
              }
            }
          ]
        }
        """.utf8)
        do {
            _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
            XCTFail("schema-invalid snapshot should fail")
        } catch {
            XCTAssertEqual(error as? SnapshotFetchError, .malformedSnapshot)
        }
    }

    func testUnsupportedSchemaVersionIsRejected() async {
        StubURLProtocol.stub.body = Data(
            #"{"schemaVersion":99,"generatedAt":"2026-03-04T09:00:00Z","providers":[]}"#.utf8
        )
        do {
            _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
            XCTFail("unsupported schema version should fail")
        } catch {
            XCTAssertEqual(error as? SnapshotFetchError, .malformedSnapshot)
        }
    }

    func testTransportFailureIsReportedGenerically() async {
        StubURLProtocol.stub.error = URLError(.cannotConnectToHost)
        do {
            _ = try await TestFixtures.stubbedClient().fetchSnapshot(using: TestFixtures.connection)
            XCTFail("transport failure should fail")
        } catch {
            XCTAssertEqual(error as? SnapshotFetchError, .transportFailure)
        }
    }

    /// No error the user can see names a host, a header or a server body.
    func testErrorDescriptionsLeakNothing() {
        let messages = [
            SnapshotFetchError.notConnected, .authenticationRejected, .rejectedByServer,
            .redirectRefused, .responseTooLarge, .unexpectedContentType,
            .malformedSnapshot, .transportFailure
        ].map(\.description)

        for message in messages {
            XCTAssertFalse(message.contains("ts.net"))
            XCTAssertFalse(message.lowercased().contains("bearer"))
            XCTAssertFalse(message.lowercased().contains("authorization"))
            XCTAssertFalse(message.contains(TestFixtures.accessKey))
        }
    }

    // MARK: - Session privacy

    func testPrivateConfigurationStoresNothing() {
        let configuration = UsageSyncAPIClient.privateConfiguration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertGreaterThan(configuration.timeoutIntervalForRequest, 0)
        XCTAssertGreaterThan(configuration.timeoutIntervalForResource, 0)
    }
}
