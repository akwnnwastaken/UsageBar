import Foundation
import XCTest
@testable import UsageBarSync
@testable import UsageBarSyncTransport

/// Policy tests: request in, response out, no sockets involved.
final class TransportServiceTests: XCTestCase {
    private func makeService(
        source: any UsageSyncSnapshotSource = UsageSyncSyntheticSnapshotSource()
    ) throws -> UsageSyncTransportService {
        UsageSyncTransportService(secret: try makeTestSecret(), source: source)
    }

    private func request(
        method: String = "GET",
        path: String = UsageSyncTransportService.snapshotPath,
        identity: String? = "tester@example.invalid",
        bearer: String? = testSecretValue
    ) -> UsageSyncTransportRequest {
        var headers: [String: String] = [:]
        if let identity { headers[UsageSyncTransportService.identityHeader] = identity }
        if let bearer { headers["Authorization"] = "Bearer \(bearer)" }
        return UsageSyncTransportRequest(method: method, path: path, headers: headers)
    }

    func testAuthenticatedGetReturnsSnapshot() throws {
        let response = try makeService().respond(to: request())
        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(response.contentType.hasPrefix("application/json"))
    }

    func testMissingBearerIsUnauthorized() throws {
        let response = try makeService().respond(to: request(bearer: nil))
        XCTAssertEqual(response.status, 401)
    }

    func testWrongBearerIsUnauthorized() throws {
        let wrong = String(repeating: "b", count: 64)
        let response = try makeService().respond(to: request(bearer: wrong))
        XCTAssertEqual(response.status, 401)
    }

    /// A correct secret with a wrong prefix must not be accepted: the scheme is
    /// part of the credential, not decoration.
    func testNonBearerAuthorizationSchemeIsRejected() throws {
        let headers = [
            UsageSyncTransportService.identityHeader: "tester@example.invalid",
            "Authorization": "Basic \(testSecretValue)"
        ]
        let response = try makeService().respond(
            to: UsageSyncTransportRequest(
                method: "GET",
                path: UsageSyncTransportService.snapshotPath,
                headers: headers
            )
        )
        XCTAssertEqual(response.status, 401)
    }

    func testMissingIdentityHeaderIsUnauthorized() throws {
        let response = try makeService().respond(to: request(identity: nil))
        XCTAssertEqual(response.status, 401)
    }

    func testBlankIdentityHeaderIsUnauthorized() throws {
        let response = try makeService().respond(to: request(identity: "   "))
        XCTAssertEqual(response.status, 401)
    }

    /// Both factors are required together. Holding the secret without an
    /// identity header — the shape a direct caller bypassing Serve would have —
    /// is refused.
    func testSecretWithoutIdentityIsRefused() throws {
        let response = try makeService().respond(to: request(identity: nil))
        XCTAssertEqual(response.status, 401)
    }

    func testWrongPathIsNotFound() throws {
        let response = try makeService().respond(to: request(path: "/v1/nope"))
        XCTAssertEqual(response.status, 404)
    }

    func testNonGetIsMethodNotAllowed() throws {
        let response = try makeService().respond(to: request(method: "POST"))
        XCTAssertEqual(response.status, 405)
    }

    /// Authentication precedes routing, so an unauthenticated caller cannot
    /// map the surface by comparing 404 against 401.
    func testUnauthenticatedWrongPathStillReturns401() throws {
        let response = try makeService().respond(to: request(path: "/v1/nope", bearer: nil))
        XCTAssertEqual(response.status, 401)
    }

    func testUnauthenticatedNonGetStillReturns401() throws {
        let response = try makeService().respond(to: request(method: "DELETE", bearer: nil))
        XCTAssertEqual(response.status, 401)
    }

    /// Failure bodies must not describe the failure.
    func testRejectionBodiesAreGeneric() throws {
        let service = try makeService()
        for candidate in [request(bearer: nil), request(path: "/x"), request(method: "PUT")] {
            let response = service.respond(to: candidate)
            let body = String(decoding: response.body, as: UTF8.self)
            XCTAssertEqual(body, "\(response.status)\n")
            XCTAssertFalse(body.lowercased().contains("bearer"))
            XCTAssertFalse(body.lowercased().contains("secret"))
            XCTAssertFalse(body.lowercased().contains("tailscale"))
        }
    }

    func testServedBodyIsValidSchemaV1() throws {
        let response = try makeService().respond(to: request())
        let decoded = try UsageSyncSerialization.decode(response.body)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded, UsageSyncSyntheticSnapshotSource.fixture)
    }

    /// A snapshot that would fail validation must never reach the wire.
    func testInvalidSnapshotBecomes503() throws {
        struct BrokenSource: UsageSyncSnapshotSource {
            func currentSnapshot() throws -> UsageSyncSnapshot {
                UsageSyncSnapshot(
                    schemaVersion: 99,
                    generatedAt: Date(timeIntervalSince1970: 0),
                    providers: []
                )
            }
        }
        let response = try makeService(source: BrokenSource()).respond(to: request())
        XCTAssertEqual(response.status, 503)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "503\n")
    }

    /// The response must carry no transport or identity metadata back out.
    func testResponseCarriesNoIdentityEcho() throws {
        let response = try makeService().respond(to: request())
        let rendered = String(decoding: response.serialized(), as: UTF8.self)
        XCTAssertFalse(rendered.contains("tester@example.invalid"))
        XCTAssertFalse(rendered.lowercased().contains("tailscale-user"))
        XCTAssertFalse(rendered.contains(testSecretValue))
    }
}
