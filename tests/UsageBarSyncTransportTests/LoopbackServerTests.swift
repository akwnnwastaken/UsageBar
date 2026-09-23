import Foundation
import XCTest
@testable import UsageBarSync
@testable import UsageBarSyncTransport

/// End-to-end over a real socket on localhost.
final class LoopbackServerTests: XCTestCase {
    func testBindsToLoopbackAddressOnly() throws {
        try withRunningServer { server, _ in
            XCTAssertEqual(server.boundAddressDescription(), "127.0.0.1")
            XCTAssertGreaterThan(server.boundPort, 0)
        }
    }

    /// The kernel must refuse a connection to the same port on a non-loopback
    /// local address. This is the property that makes the injected identity
    /// header trustworthy, so it is asserted rather than assumed.
    func testNonLoopbackLocalAddressIsNotReachable() throws {
        try withRunningServer { server, _ in
            guard let routable = Self.firstNonLoopbackIPv4() else {
                throw XCTSkip("no non-loopback IPv4 interface available")
            }
            var client = RawHTTPClient(port: server.boundPort)
            client.host = routable
            XCTAssertThrowsError(try client.request(headers: validHeaders()))
        }
    }

    func testAuthenticatedRequestReturnsSnapshotOverSocket() throws {
        try withRunningServer { _, client in
            let response = try client.request(headers: validHeaders())
            XCTAssertEqual(response.status, 200)
            let snapshot = try UsageSyncSerialization.decode(response.body)
            XCTAssertEqual(snapshot, UsageSyncSyntheticSnapshotSource.fixture)
        }
    }

    func testMissingBearerOverSocketIs401() throws {
        try withRunningServer { _, client in
            let headers = [(UsageSyncTransportService.identityHeader, "tester@example.invalid")]
            XCTAssertEqual(try client.request(headers: headers).status, 401)
        }
    }

    func testWrongBearerOverSocketIs401() throws {
        try withRunningServer { _, client in
            let headers = validHeaders(bearer: String(repeating: "z", count: 64))
            XCTAssertEqual(try client.request(headers: headers).status, 401)
        }
    }

    func testWrongPathOverSocketIs404() throws {
        try withRunningServer { _, client in
            let response = try client.request(path: "/v1/not-a-route", headers: validHeaders())
            XCTAssertEqual(response.status, 404)
        }
    }

    func testNonGetOverSocketIs405() throws {
        try withRunningServer { _, client in
            let response = try client.request(
                method: "POST",
                headers: validHeaders(),
                body: "{}"
            )
            XCTAssertEqual(response.status, 405)
        }
    }

    func testQueryStringIsIgnoredForRouting() throws {
        try withRunningServer { _, client in
            let response = try client.request(
                path: UsageSyncTransportService.snapshotPath + "?cache=0",
                headers: validHeaders()
            )
            XCTAssertEqual(response.status, 200)
        }
    }

    func testResponseCarriesHardeningHeaders() throws {
        try withRunningServer { _, client in
            let response = try client.request(headers: validHeaders())
            XCTAssertEqual(response.headers["cache-control"], "no-store")
            XCTAssertEqual(response.headers["x-content-type-options"], "nosniff")
            XCTAssertEqual(response.headers["connection"], "close")
        }
    }

    // MARK: - Limits

    func testOversizedHeadIsRejected() throws {
        let limits = UsageSyncTransportLimits(maxRequestBytes: 2_048)
        try withRunningServer(limits: limits) { _, client in
            let padding = String(repeating: "x", count: 4_096)
            let response = try client.request(
                headers: validHeaders() + [("X-Padding", padding)]
            )
            XCTAssertEqual(response.status, 413)
        }
    }

    func testOversizedSingleHeaderLineIsRejected() throws {
        let limits = UsageSyncTransportLimits(maxHeaderLineBytes: 64)
        try withRunningServer(limits: limits) { _, client in
            let response = try client.request(
                headers: validHeaders() + [("X-Padding", String(repeating: "y", count: 256))]
            )
            XCTAssertEqual(response.status, 413)
        }
    }

    func testTooManyHeadersIsRejected() throws {
        let limits = UsageSyncTransportLimits(maxHeaderCount: 6)
        try withRunningServer(limits: limits) { _, client in
            var headers = validHeaders()
            for index in 0..<20 { headers.append(("X-Pad-\(index)", "1")) }
            let response = try client.request(headers: headers)
            XCTAssertEqual(response.status, 431)
        }
    }

    func testOversizedRequestLineIsRejected() throws {
        let limits = UsageSyncTransportLimits(maxRequestLineBytes: 64)
        try withRunningServer(limits: limits) { _, client in
            let response = try client.request(
                path: "/v1/" + String(repeating: "p", count: 256),
                headers: validHeaders()
            )
            XCTAssertEqual(response.status, 413)
        }
    }

    func testOversizedDeclaredBodyIsRejected() throws {
        let limits = UsageSyncTransportLimits(maxRequestBytes: 1_024)
        try withRunningServer(limits: limits) { _, client in
            var text = "POST \(UsageSyncTransportService.snapshotPath) HTTP/1.1\r\n"
            text += "Host: 127.0.0.1\r\n"
            for (name, value) in validHeaders() { text += "\(name): \(value)\r\n" }
            text += "Content-Length: 99999\r\n\r\n"
            XCTAssertEqual(try client.send(raw: text).status, 413)
        }
    }

    // MARK: - Malformed input

    func testMalformedRequestLineIsRejected() throws {
        try withRunningServer { _, client in
            XCTAssertEqual(try client.send(raw: "NOT-HTTP\r\n\r\n").status, 400)
        }
    }

    func testUnsupportedHTTPVersionIsRejected() throws {
        try withRunningServer { _, client in
            let raw = "GET \(UsageSyncTransportService.snapshotPath) HTTP/9.9\r\nHost: x\r\n\r\n"
            XCTAssertEqual(try client.send(raw: raw).status, 400)
        }
    }

    func testRelativeTargetWithoutLeadingSlashIsRejected() throws {
        try withRunningServer { _, client in
            XCTAssertEqual(try client.send(raw: "GET v1/snapshot HTTP/1.1\r\nHost: x\r\n\r\n").status, 400)
        }
    }

    func testHeaderWithoutColonIsRejected() throws {
        try withRunningServer { _, client in
            let raw = "GET \(UsageSyncTransportService.snapshotPath) HTTP/1.1\r\nBrokenHeader\r\n\r\n"
            XCTAssertEqual(try client.send(raw: raw).status, 400)
        }
    }

    /// A duplicated Authorization header is ambiguous. Choosing one silently is
    /// how request-smuggling and header-confusion bugs start, so it is refused.
    func testDuplicateAuthorizationHeaderIsRejected() throws {
        try withRunningServer { _, client in
            var text = "GET \(UsageSyncTransportService.snapshotPath) HTTP/1.1\r\n"
            text += "Host: 127.0.0.1\r\n"
            text += "\(UsageSyncTransportService.identityHeader): tester@example.invalid\r\n"
            text += "Authorization: Bearer \(testSecretValue)\r\n"
            text += "Authorization: Bearer \(String(repeating: "z", count: 64))\r\n\r\n"
            XCTAssertEqual(try client.send(raw: text).status, 400)
        }
    }

    func testHeaderLookupIsCaseInsensitive() throws {
        try withRunningServer { _, client in
            let headers = [
                ("tailscale-user-login", "tester@example.invalid"),
                ("AUTHORIZATION", "Bearer \(testSecretValue)")
            ]
            XCTAssertEqual(try client.request(headers: headers).status, 200)
        }
    }

    // MARK: - Helpers

    private static func firstNonLoopbackIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return nil }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = start
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let rawAddress = current.pointee.ifa_addr,
                  rawAddress.pointee.sa_family == UInt8(AF_INET) else { continue }
            var storage = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                rawAddress,
                socklen_t(rawAddress.pointee.sa_len),
                &storage,
                socklen_t(storage.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            let address = String(cString: storage)
            if address != "127.0.0.1" && !address.hasPrefix("169.254.") {
                return address
            }
        }
        return nil
    }
}
