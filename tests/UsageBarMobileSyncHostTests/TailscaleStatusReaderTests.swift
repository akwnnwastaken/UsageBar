import XCTest
@testable import UsageBarMobileSyncHost

/// The read-only Tailscale reader: what it extracts, and what it refuses.
final class TailscaleStatusReaderTests: XCTestCase {
    private func reader(returning data: Data?) -> MobileSyncTailscaleStatusReader {
        MobileSyncTailscaleStatusReader(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            runner: { _, _, _ in data }
        )
    }

    private func statusJSON(backend: String = "Running", dnsName: String?) -> Data {
        var object: [String: Any] = ["BackendState": backend]
        if let dnsName { object["Self"] = ["DNSName": dnsName] }
        // Realistic noise that must never leave the reader.
        object["TailscaleIPs"] = ["100.64.0.1"]
        object["Peer"] = ["nodekey:abc": ["DNSName": "phone.example-tailnet.ts.net."]]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    func testExtractsOnlyBackendStateAndSelfHost() {
        let status = reader(returning: statusJSON(dnsName: "example-machine.example-tailnet.ts.net.")).read()
        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.host, "example-machine.example-tailnet.ts.net")
        XCTAssertTrue(status.isPairable)
    }

    func testTrailingDotIsStrippedAndHostLowercased() {
        XCTAssertEqual(
            MobileSyncTailscaleStatusReader.tailnetHost("Example-Machine.Example-Tailnet.TS.NET."),
            "example-machine.example-tailnet.ts.net"
        )
    }

    func testNonTailnetOrMalformedHostRejected() {
        for bad in [
            "machine.local.", "example.com", "", ".", "ts.net",
            "https://example-machine.example-tailnet.ts.net",
            "example-machine.example-tailnet.ts.net:443",
            "example-machine.example-tailnet.ts.net/path"
        ] {
            XCTAssertNil(MobileSyncTailscaleStatusReader.tailnetHost(bad), bad)
        }
    }

    func testStoppedBackendIsNotPairable() {
        let status = reader(returning: statusJSON(backend: "Stopped", dnsName: "m.t.ts.net")).read()
        XCTAssertFalse(status.isRunning)
        XCTAssertFalse(status.isPairable)
    }

    func testMissingSelfHostIsNotPairable() {
        let status = reader(returning: statusJSON(dnsName: nil)).read()
        XCTAssertTrue(status.isRunning)
        XCTAssertNil(status.host)
        XCTAssertFalse(status.isPairable)
    }

    /// The CLI can fail while exiting 0, writing a human sentence to stdout.
    /// Anything that is not JSON is not an answer.
    func testNonJSONOutputIsNotAnAnswer() {
        for output in ["The Tailscale GUI failed to start.", "", "null", "[]"] {
            let status = reader(returning: Data(output.utf8)).read()
            XCTAssertFalse(status.isPairable, output)
        }
        XCTAssertFalse(reader(returning: nil).read().isPairable)
    }

    func testMissingExecutableIsNotPairable() {
        let absent = MobileSyncTailscaleStatusReader(executableURL: nil, runner: { _, _, _ in nil })
        XCTAssertFalse(absent.read().isPairable)
    }

    /// Only absolute, fixed paths — never a PATH lookup, which would let
    /// whatever a user has installed decide what this process executes.
    func testExecutableCandidatesAreAbsoluteAndFixed() {
        XCTAssertFalse(MobileSyncTailscaleStatusReader.candidateExecutables.isEmpty)
        for path in MobileSyncTailscaleStatusReader.candidateExecutables {
            XCTAssertTrue(path.hasPrefix("/"), path)
        }
    }

    /// The reader holds the status in memory and returns only two fields;
    /// nothing else from the JSON survives the call.
    func testAddressesAndPeersNeverLeaveTheReader() {
        let status = reader(returning: statusJSON(dnsName: "example-machine.example-tailnet.ts.net.")).read()
        let described = String(describing: status)
        XCTAssertFalse(described.contains("100.64.0.1"))
        XCTAssertFalse(described.contains("nodekey"))
        XCTAssertFalse(described.contains("phone.example-tailnet"))
    }

    func testTimeoutAndOutputCeilingAreBounded() {
        XCTAssertLessThanOrEqual(MobileSyncTailscaleStatusReader.timeout, 5)
        XCTAssertLessThanOrEqual(MobileSyncTailscaleStatusReader.maximumOutputBytes, 1024 * 1024)
    }
}
