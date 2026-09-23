import XCTest
@testable import UsageBarPairing

/// The pairing wire format, and what it refuses.
///
/// A QR is readable by anyone who can see the Mac's screen, so the parser's job
/// is not to be accommodating. Every rejection here is a case where a permissive
/// parser would have accepted something that means more than "which machine,
/// and this one-time code".
final class PairingPayloadTests: XCTestCase {
    private let host = "example-machine.example-tailnet.ts.net"

    private func payloadJSON(
        version: Any = 1,
        host: Any? = "example-machine.example-tailnet.ts.net",
        code: Any? = nil,
        extra: [String: Any] = [:]
    ) -> String {
        var object: [String: Any] = ["v": version]
        if let host { object["host"] = host }
        object["pairingCode"] = code ?? UsageBarPairingCode.generate().encoded
        for (key, value) in extra { object[key] = value }
        return String(
            data: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            encoding: .utf8
        )!
    }

    // MARK: - Code

    func testGeneratedCodeIs256Bits() {
        XCTAssertEqual(UsageBarPairingCode.generate().bitCount, 256)
        XCTAssertEqual(UsageBarPairingCode.byteCount, 32)
    }

    func testGeneratedCodesDiffer() {
        let codes = (0..<32).map { _ in UsageBarPairingCode.generate().encoded }
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testCodeRoundTripsThroughBase64URL() throws {
        let code = UsageBarPairingCode.generate()
        let decoded = try UsageBarPairingCode(decoding: code.encoded)
        XCTAssertTrue(code.matches(decoded))
    }

    /// base64url, so a QR can stay in a denser, easier-to-scan mode.
    func testEncodedCodeAvoidsCharactersThatWidenAQRSymbol() {
        let encoded = UsageBarPairingCode.generate().encoded
        for forbidden in ["+", "/", "="] {
            XCTAssertFalse(encoded.contains(forbidden))
        }
    }

    func testShortCodeRejected() {
        XCTAssertThrowsError(try UsageBarPairingCode(decoding: "c2hvcnQ"))
    }

    func testMalformedCodeRejected() {
        for bad in ["", "not base64!!", String(repeating: "A", count: 200), "abc$def"] {
            XCTAssertThrowsError(try UsageBarPairingCode(decoding: bad), bad)
        }
    }

    func testCodeComparisonIsConstantTimeAndRejectsPrefixes() throws {
        let code = UsageBarPairingCode.generate()
        let other = UsageBarPairingCode.generate()
        XCTAssertFalse(code.matches(other))
        // Same length, different value.
        var bytes = Array(Data(base64Encoded: paddedBase64(code.encoded))!)
        bytes[31] ^= 0xFF
        XCTAssertFalse(code.matches(UsageBarPairingCode(bytes: bytes)))
    }

    private func paddedBase64(_ text: String) -> String {
        var base64 = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return base64
    }

    func testConstantTimeComparisonRejectsEmptyExpected() {
        XCTAssertFalse(UsageBarConstantTime.equal([], []))
        XCTAssertTrue(UsageBarConstantTime.equal([1, 2, 3], [1, 2, 3]))
        XCTAssertFalse(UsageBarConstantTime.equal([1, 2, 3], [1, 2]))
        XCTAssertFalse(UsageBarConstantTime.equal([1, 2], [1, 2, 3]))
    }

    // MARK: - Payload

    func testValidV1PayloadRoundTrips() throws {
        let code = UsageBarPairingCode.generate()
        let payload = try UsageBarPairingPayload(host: host, pairingCode: code)
        let decoded = try UsageBarPairingPayload.decode(payload.encoded())
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.host, host)
        XCTAssertTrue(decoded.pairingCode.matches(code))
    }

    func testHostIsLowercasedAndTrimmed() throws {
        let payload = try UsageBarPairingPayload(
            host: "  Example-Machine.Example-Tailnet.TS.NET \n",
            pairingCode: .generate()
        )
        XCTAssertEqual(payload.host, host)
    }

    func testUnsupportedVersionRejected() {
        for version in [0, 2, 99] {
            XCTAssertThrowsError(try UsageBarPairingPayload.decode(payloadJSON(version: version))) { error in
                XCTAssertEqual(
                    error as? UsageBarPairingPayload.PayloadError,
                    .unsupportedVersion(found: version)
                )
            }
        }
    }

    func testNonIntegerVersionRejected() {
        XCTAssertThrowsError(try UsageBarPairingPayload.decode(payloadJSON(version: "1")))
    }

    func testNonTailnetHostRejected() {
        for bad in [
            "example.com",
            "machine.local",
            "example-machine.example-tailnet.ts.net.evil.com",
            "ts.net",
            "a.ts.net"
        ] {
            XCTAssertThrowsError(try UsageBarPairingPayload.decode(payloadJSON(host: bad)), bad)
        }
    }

    /// A QR that names a URL rather than a host is trying to say how the phone
    /// should connect, not just where.
    func testURLInsteadOfHostRejected() {
        for bad in [
            "https://example-machine.example-tailnet.ts.net",
            "example-machine.example-tailnet.ts.net/v1/snapshot",
            "example-machine.example-tailnet.ts.net:8443",
            "user@example-machine.example-tailnet.ts.net",
            "example-machine.example-tailnet.ts.net?x=1",
            "example-machine.example-tailnet.ts.net#f"
        ] {
            XCTAssertThrowsError(try UsageBarPairingPayload.decode(payloadJSON(host: bad)), bad)
        }
    }

    /// A routable address cannot end in `.ts.net`, so the suffix rule already
    /// excludes one. Asserted explicitly because that is the property the
    /// design relies on to keep a raw `100.x` tailnet address out of a QR.
    func testRawIPAddressRejected() {
        for bad in ["100.64.0.1", "192.168.1.10", "::1", "100.64.0.1:443"] {
            XCTAssertThrowsError(try UsageBarPairingPayload.decode(payloadJSON(host: bad)), bad)
        }
    }

    /// A `.ts.net` name whose labels happen to be numeric is still a DNS name
    /// the tailnet resolves, not an address the phone dials — so it is accepted
    /// here, exactly as the client's own endpoint validator accepts it. Pinned
    /// so the two cannot quietly diverge on it.
    func testNumericLookingTailnetNameIsStillAName() throws {
        let payload = try UsageBarPairingPayload.decode(payloadJSON(host: "100.64.0.1.ts.net"))
        XCTAssertEqual(payload.host, "100.64.0.1.ts.net")
    }

    func testControlCharactersAndWhitespaceInHostRejected() {
        for bad in ["exa mple.example-tailnet.ts.net", "example\u{0}.example-tailnet.ts.net"] {
            XCTAssertThrowsError(try UsageBarPairingPayload.decode(payloadJSON(host: bad)), bad)
        }
    }

    func testShortPairingCodeInPayloadRejected() {
        XCTAssertThrowsError(try UsageBarPairingPayload.decode(payloadJSON(code: "c2hvcnQ"))) { error in
            XCTAssertEqual(error as? UsageBarPairingPayload.PayloadError, .malformedCode)
        }
    }

    func testMalformedPairingCodeInPayloadRejected() {
        XCTAssertThrowsError(try UsageBarPairingPayload.decode(payloadJSON(code: "!!!!")))
    }

    func testOversizedPayloadRejectedBeforeParsing() {
        let padded = String(repeating: "a", count: UsageBarPairingPayload.maximumEncodedBytes + 1)
        XCTAssertThrowsError(try UsageBarPairingPayload.decode(padded)) { error in
            XCTAssertEqual(error as? UsageBarPairingPayload.PayloadError, .tooLarge)
        }
    }

    /// The important one. A permissive parser that ignored unknown keys would
    /// happily accept a QR carrying a long-lived credential or an identity
    /// claim beside the fields it understands.
    func testUnknownFieldsRejected() {
        for extra in [
            ["accessKey": "leaked"],
            ["identity": "someone@example.com"],
            ["tailscaleIP": "100.64.0.1"],
            ["port": 8443]
        ] as [[String: Any]] {
            XCTAssertThrowsError(
                try UsageBarPairingPayload.decode(payloadJSON(extra: extra))
            ) { error in
                XCTAssertEqual(error as? UsageBarPairingPayload.PayloadError, .unexpectedFields)
            }
        }
    }

    func testMissingFieldsRejected() {
        XCTAssertThrowsError(try UsageBarPairingPayload.decode(#"{"v":1}"#))
        XCTAssertThrowsError(try UsageBarPairingPayload.decode(payloadJSON(host: nil)))
    }

    func testNonObjectPayloadRejected() {
        for bad in ["[]", "\"string\"", "null", "", "{"] {
            XCTAssertThrowsError(try UsageBarPairingPayload.decode(bad), bad)
        }
    }

    /// The payload carries exactly three fields, so the encoded form cannot
    /// contain a credential even if this type later gains a property.
    func testEncodedPayloadCarriesNothingDurable() throws {
        let payload = try UsageBarPairingPayload(host: host, pairingCode: .generate())
        let encoded = payload.encoded()
        let object = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
        XCTAssertEqual(Set(try XCTUnwrap(object).keys), ["v", "host", "pairingCode"])
        for forbidden in ["accessKey", "bearer", "identity", "token", "100.", "@"] {
            XCTAssertFalse(encoded.contains(forbidden), "payload leaked \"\(forbidden)\"")
        }
    }

    func testEncodedPayloadStaysWellWithinTheSizeCeiling() throws {
        let payload = try UsageBarPairingPayload(host: host, pairingCode: .generate())
        XCTAssertLessThan(payload.encoded().utf8.count, UsageBarPairingPayload.maximumEncodedBytes)
    }

    func testConstructingAPayloadWithANonTailnetHostThrows() {
        XCTAssertThrowsError(
            try UsageBarPairingPayload(host: "example.com", pairingCode: .generate())
        )
    }
}
