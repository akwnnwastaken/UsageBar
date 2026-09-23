import XCTest
@testable import UsageBarMobileLab

/// Host validation is the app's outermost input boundary: whatever survives it
/// becomes the URL the bearer token is sent to.
final class HostValidationTests: XCTestCase {
    /// Deliberately fake. No real tailnet name appears anywhere in this repo.
    private let validHost = "usagebar-test.example-tail.ts.net"

    func testValidTailnetHostAccepted() throws {
        let host = try UsageSyncHost(validating: validHost)
        XCTAssertEqual(host.value, validHost)
    }

    func testHostIsLowercased() throws {
        let host = try UsageSyncHost(validating: "UsageBar-Test.Example-Tail.TS.NET")
        XCTAssertEqual(host.value, validHost)
    }

    func testSurroundingWhitespaceIsTrimmed() throws {
        let host = try UsageSyncHost(validating: "  \(validHost)  ")
        XCTAssertEqual(host.value, validHost)
    }

    func testSchemeRejected() {
        assertRejects("https://\(validHost)")
        assertRejects("http://\(validHost)")
    }

    func testPathRejected() {
        assertRejects("\(validHost)/v1/snapshot")
        assertRejects("\(validHost)/")
    }

    func testPortRejected() {
        assertRejects("\(validHost):443")
        assertRejects("\(validHost):8443")
    }

    func testCredentialsRejected() {
        assertRejects("user:password@\(validHost)")
        assertRejects("user@\(validHost)")
    }

    func testQueryOrFragmentRejected() {
        assertRejects("\(validHost)?cache=0")
        assertRejects("\(validHost)#fragment")
    }

    /// The raw tailnet address must never become the endpoint: it bypasses the
    /// MagicDNS name the certificate is issued for.
    func testRawIPAddressRejected() {
        assertRejects("100.64.0.1")
        assertRejects("127.0.0.1")
        assertRejects("192.168.1.10")
    }

    func testNonTailnetHostRejected() {
        assertRejects("example.com")
        assertRejects("usagebar.example.org")
        assertRejects("evil.ts.net.attacker.com")
    }

    func testWhitespaceOrControlCharactersRejected() {
        assertRejects("usagebar test.example-tail.ts.net")
        assertRejects("usagebar\u{0000}.example-tail.ts.net")
        assertRejects("usagebar\n.example-tail.ts.net")
    }

    func testEmptyRejected() {
        assertRejects("")
        assertRejects("    ")
    }

    func testMalformedLabelsRejected() {
        assertRejects("-leading.example-tail.ts.net")
        assertRejects("trailing-.example-tail.ts.net")
        assertRejects("under_score.example-tail.ts.net")
        assertRejects("..example-tail.ts.net")
        // Too few labels to be <machine>.<tailnet>.ts.net
        assertRejects("ts.net")
        assertRejects("example-tail.ts.net")
    }

    /// The app builds the URL; the user never supplies one.
    func testSnapshotURLIsConstructedExactly() throws {
        let host = try UsageSyncHost(validating: validHost)
        XCTAssertEqual(
            host.snapshotURL.absoluteString,
            "https://usagebar-test.example-tail.ts.net/v1/snapshot"
        )
        XCTAssertEqual(host.snapshotURL.scheme, "https")
        XCTAssertEqual(host.snapshotURL.path, "/v1/snapshot")
        XCTAssertNil(host.snapshotURL.port)
        XCTAssertNil(host.snapshotURL.query)
    }

    private func assertRejects(_ raw: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(
            try UsageSyncHost(validating: raw),
            "expected rejection of a malformed host",
            file: file,
            line: line
        )
    }
}
