import Foundation
import XCTest
@testable import UsageBarSyncTransport

final class TransportSecretTests: XCTestCase {
    func testGeneratedSecretMeetsMinimumEntropy() {
        let secret = UsageSyncTransportSecret.generate()
        XCTAssertGreaterThanOrEqual(secret.byteCount, 32)
    }

    func testGeneratedSecretsDiffer() {
        let first = UsageSyncTransportSecret.generateHexString()
        let second = UsageSyncTransportSecret.generateHexString()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.count, 64)
    }

    func testShortSecretIsRejected() {
        XCTAssertThrowsError(try UsageSyncTransportSecret.fromString("tooshort")) { error in
            XCTAssertEqual(
                error as? UsageSyncTransportSecret.LoadFailure,
                .tooShort(found: 8, minimum: 32)
            )
        }
    }

    func testMatchesAcceptsExactValue() throws {
        let secret = try UsageSyncTransportSecret.fromString(testSecretValue)
        XCTAssertTrue(secret.matches(testSecretValue))
    }

    func testMatchesRejectsWrongValueOfSameLength() throws {
        let secret = try UsageSyncTransportSecret.fromString(testSecretValue)
        XCTAssertFalse(secret.matches(String(repeating: "b", count: 64)))
    }

    /// A correct prefix must not be accepted. This is the case a
    /// short-circuiting comparison would leak through timing.
    func testMatchesRejectsCorrectPrefix() throws {
        let secret = try UsageSyncTransportSecret.fromString(testSecretValue)
        XCTAssertFalse(secret.matches(String(repeating: "a", count: 63)))
        XCTAssertFalse(secret.matches(String(repeating: "a", count: 65)))
        XCTAssertFalse(secret.matches(""))
    }

    func testFileWithLoosePermissionsIsRejected() throws {
        let path = NSTemporaryDirectory() + "/usagebar-secret-\(UUID().uuidString)"
        try testSecretValue.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertThrowsError(try UsageSyncTransportSecret.load(contentsOfFile: path)) { error in
            XCTAssertEqual(
                error as? UsageSyncTransportSecret.LoadFailure,
                .insecurePermissions(found: 0o644)
            )
        }
    }

    func testFileWithOwnerOnlyPermissionsLoads() throws {
        let path = NSTemporaryDirectory() + "/usagebar-secret-\(UUID().uuidString)"
        try testSecretValue.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let secret = try UsageSyncTransportSecret.load(contentsOfFile: path)
        XCTAssertTrue(secret.matches(testSecretValue))
    }

    func testMissingFileIsRejected() {
        XCTAssertThrowsError(
            try UsageSyncTransportSecret.load(contentsOfFile: "/nonexistent/usagebar-secret")
        ) { error in
            XCTAssertEqual(error as? UsageSyncTransportSecret.LoadFailure, .unreadable)
        }
    }
}
