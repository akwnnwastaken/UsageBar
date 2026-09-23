import Foundation
import XCTest
@testable import UsageBarSync
@testable import UsageBarSyncTransport

/// Guards the properties that make this a *sync boundary* rather than just a
/// small web server.
final class TransportBoundaryTests: XCTestCase {
    /// Transport metadata must not appear in the payload. The typed model has
    /// no field for it, but a future careless change could add one, so the
    /// encoded key set is asserted directly.
    func testServedPayloadCarriesNoTransportMetadata() throws {
        let service = UsageSyncTransportService(
            secret: try makeTestSecret(),
            source: UsageSyncSyntheticSnapshotSource()
        )
        let response = service.respond(
            to: UsageSyncTransportRequest(
                method: "GET",
                path: UsageSyncTransportService.snapshotPath,
                headers: [
                    UsageSyncTransportService.identityHeader: "tester@example.invalid",
                    "Authorization": "Bearer \(testSecretValue)"
                ]
            )
        )
        let text = String(decoding: response.body, as: UTF8.self).lowercased()
        for forbidden in [
            "tailscale", "magicdns", "ts.net", "100.", "127.0.0.1", "localhost",
            "port", "host", "url", "token", "bearer", "authorization",
            "login", "email", "/users/", "node", "tailnet"
        ] {
            XCTAssertFalse(text.contains(forbidden), "payload leaked \"\(forbidden)\"")
        }
    }

    /// The whole key vocabulary of the wire format, asserted explicitly.
    func testServedPayloadKeysAreSchemaV1Only() throws {
        let json = try UsageSyncSerialization.encode(UsageSyncSyntheticSnapshotSource.fixture)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: json) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "generatedAt", "providers"])

        let providers = try XCTUnwrap(object["providers"] as? [[String: Any]])
        for provider in providers {
            XCTAssertTrue(
                Set(provider.keys).isSubset(of: ["providerId", "connected", "collecting", "measurement"])
            )
            guard let measurement = provider["measurement"] as? [String: Any] else { continue }
            XCTAssertTrue(
                Set(measurement.keys).isSubset(
                    of: ["measuredAt", "headlineRemainingPercent", "headlineWindowId", "windows"]
                )
            )
            let windows = try XCTUnwrap(measurement["windows"] as? [[String: Any]])
            for window in windows {
                XCTAssertTrue(
                    Set(window.keys).isSubset(
                        of: [
                            "windowId", "kind", "scope", "durationMinutes",
                            "position", "remainingPercent", "resetsAt"
                        ]
                    )
                )
            }
        }
    }

    /// The transport serves the same corpus the two platform builders are
    /// tested against, so the bytes on the wire are the proven wire format and
    /// not a shape invented here.
    func testEveryParityFixtureCanBeServedAndDecoded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/sync-schema/parity")

        let fixtures = [
            "basic", "claude-weekly-scoped", "paused-retained",
            "codex-duration-headline", "unknown-window"
        ]

        for name in fixtures {
            let path = root.appendingPathComponent("\(name).json").path
            let source = try UsageSyncFileSnapshotSource(contentsOfFile: path)
            let service = UsageSyncTransportService(
                secret: try makeTestSecret(),
                source: source
            )
            let response = service.respond(
                to: UsageSyncTransportRequest(
                    method: "GET",
                    path: UsageSyncTransportService.snapshotPath,
                    headers: [
                        UsageSyncTransportService.identityHeader: "tester@example.invalid",
                        "Authorization": "Bearer \(testSecretValue)"
                    ]
                )
            )
            XCTAssertEqual(response.status, 200, "fixture \(name) did not serve")
            let decoded = try UsageSyncSerialization.decode(response.body)
            XCTAssertEqual(decoded, try source.currentSnapshot(), "fixture \(name) round-trip differed")
        }
    }

    /// An invalid fixture must be refused at load, not served and rejected later.
    func testInvalidFixtureIsRefusedAtLoad() throws {
        let path = NSTemporaryDirectory() + "/usagebar-bad-fixture-\(UUID().uuidString).json"
        try #"{"schemaVersion":7,"generatedAt":"2026-03-04T09:00:00Z","providers":[]}"#
            .write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertThrowsError(try UsageSyncFileSnapshotSource(contentsOfFile: path))
    }

    /// The transport module must not have pulled in the desktop product.
    /// UsageBar's own behaviour cannot regress because of a sync change if the
    /// dependency does not exist.
    func testTransportDoesNotLinkTheDesktopApplication() {
        let bundle = Bundle(for: type(of: self))
        XCTAssertNil(
            bundle.classNamed("UsageBar.AppDelegate"),
            "transport tests must not link the UsageBar application"
        )
    }

    /// Route and header names are part of the contract; pin them so a rename
    /// is a deliberate, reviewed change rather than a silent one.
    func testContractConstants() {
        XCTAssertEqual(UsageSyncTransportService.snapshotPath, "/v1/snapshot")
        XCTAssertEqual(UsageSyncTransportService.identityHeader, "Tailscale-User-Login")
        XCTAssertEqual(UsageSyncLoopbackHTTPServer.loopbackAddress, "127.0.0.1")
    }
}
