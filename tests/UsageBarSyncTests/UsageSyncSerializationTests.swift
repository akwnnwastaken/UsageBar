import XCTest
@testable import UsageBarSync

/// Serialization, round-tripping, compatibility with the committed Phase-1
/// examples, and the structural proof that prohibited data has nowhere to go.
final class UsageSyncSerializationTests: XCTestCase {

    /// Exactly the property names schema v1 allows, at each level. Asserting
    /// against the *encoded* key set rather than grepping the source is what
    /// makes this a real guarantee: anything a future field added to the model
    /// would emit shows up here immediately.
    private static let allowedTopLevelKeys: Set<String> = ["schemaVersion", "generatedAt", "providers"]
    private static let allowedProviderKeys: Set<String> = ["providerId", "connected", "collecting", "measurement"]
    private static let allowedMeasurementKeys: Set<String> = [
        "measuredAt", "headlineRemainingPercent", "headlineWindowId", "windows"
    ]
    private static let allowedWindowKeys: Set<String> = [
        "windowId", "kind", "scope", "durationMinutes", "position", "remainingPercent", "resetsAt"
    ]

    private func assertOnlyAllowedKeys(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line
        )
        XCTAssertTrue(Set(object.keys).isSubset(of: Self.allowedTopLevelKeys),
                      "unexpected top-level keys: \(Set(object.keys).subtracting(Self.allowedTopLevelKeys))",
                      file: file, line: line)

        for provider in (object["providers"] as? [[String: Any]]) ?? [] {
            XCTAssertTrue(Set(provider.keys).isSubset(of: Self.allowedProviderKeys),
                          "unexpected provider keys: \(Set(provider.keys).subtracting(Self.allowedProviderKeys))",
                          file: file, line: line)
            guard let measurement = provider["measurement"] as? [String: Any] else { continue }
            XCTAssertTrue(Set(measurement.keys).isSubset(of: Self.allowedMeasurementKeys),
                          "unexpected measurement keys: \(Set(measurement.keys).subtracting(Self.allowedMeasurementKeys))",
                          file: file, line: line)
            for window in (measurement["windows"] as? [[String: Any]]) ?? [] {
                XCTAssertTrue(Set(window.keys).isSubset(of: Self.allowedWindowKeys),
                              "unexpected window keys: \(Set(window.keys).subtracting(Self.allowedWindowKeys))",
                              file: file, line: line)
            }
        }
    }

    private func richSnapshot() throws -> UsageSyncSnapshot {
        try UsageSyncSnapshotBuilder.snapshot(
            from: [
                Fixture.input(Fixture.codexDurationHeadline, name: "Codex"),
                Fixture.input(Fixture.claudeSessionAndWeekly, name: "Claude Code"),
                Fixture.input(Fixture.codexUnknownWindow, name: "Paused Example", collecting: false),
                Fixture.input(nil, name: "Gone Example", connected: false, collecting: false)
            ],
            generatedAt: Fixture.generatedAt
        )
    }

    // MARK: round trip

    func testEncodeDecodeRoundTripPreservesEverything() throws {
        let original = try richSnapshot()
        let decoded = try UsageSyncSerialization.decode(try UsageSyncSerialization.encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testEncodingIsDeterministic() throws {
        let snapshot = try richSnapshot()
        let first = try UsageSyncSerialization.encode(snapshot)
        let second = try UsageSyncSerialization.encode(snapshot)
        XCTAssertEqual(first, second)
    }

    func testTimestampsEncodeAsRFC3339UTC() throws {
        let data = try UsageSyncSerialization.encode(try richSnapshot())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"generatedAt\":\"2026-01-15T14:05:00Z\""))
        XCTAssertTrue(text.contains("\"measuredAt\":\"2026-01-15T14:00:00Z\""))
    }

    func testSchemaVersionIsSerializedAsOne() throws {
        let data = try UsageSyncSerialization.encode(try richSnapshot())
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
    }

    func testNonUTCOffsetAndFractionalSecondsDecode() throws {
        XCTAssertEqual(
            UsageSyncSerialization.date(from: "2026-01-15T17:00:00+03:00"),
            UsageSyncSerialization.date(from: "2026-01-15T14:00:00Z")
        )
        XCTAssertNotNil(UsageSyncSerialization.date(from: "2026-01-15T14:00:00.250Z"))
        XCTAssertNil(UsageSyncSerialization.date(from: "15/01/2026 14:00"))
    }

    func testInvalidSnapshotIsNeverEncoded() {
        let invalid = UsageSyncSnapshot(generatedAt: Fixture.generatedAt, providers: [
            UsageSyncProvider(providerId: "codex", connected: false, collecting: true)
        ])
        XCTAssertThrowsError(try UsageSyncSerialization.encode(invalid))
    }

    func testDecodingValidatesBeforeReturning() throws {
        let hostile = Data("""
        {"schemaVersion":1,"generatedAt":"2026-01-15T14:05:00Z","providers":[
          {"providerId":"codex","connected":false,"collecting":true}]}
        """.utf8)
        XCTAssertThrowsError(try UsageSyncSerialization.decode(hostile)) { error in
            XCTAssertEqual(error as? UsageSyncValidationError,
                           .disconnectedProviderIsCollecting(providerId: "codex"))
        }
        // The same payload decodes structurally; only validation rejects it.
        XCTAssertNoThrow(try UsageSyncSerialization.decodeWithoutValidation(hostile))
    }

    func testWritingAndReadingATemporaryFileRoundTrips() throws {
        // Local serialization only: a temporary test file, never UserDefaults
        // and never a network cache.
        let snapshot = try richSnapshot()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("usagebar-sync-\(UUID().uuidString).json")
        try UsageSyncSerialization.encode(snapshot).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try UsageSyncSerialization.decode(try Data(contentsOf: url)), snapshot)
    }

    // MARK: Phase-1 example compatibility

    func testMinimalPhase1ExampleDecodesAndValidates() throws {
        let snapshot = try UsageSyncSerialization.decode(try Fixture.exampleData("minimal.json"))
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.providers.count, 1)

        let provider = snapshot.providers[0]
        XCTAssertEqual(provider.providerId, "codex")
        XCTAssertTrue(provider.connected)
        XCTAssertTrue(provider.collecting)

        let measurement = try XCTUnwrap(provider.measurement)
        XCTAssertEqual(measurement.headlineRemainingPercent, 72)
        XCTAssertEqual(measurement.headlineWindowId, "five-hour")
        XCTAssertEqual(measurement.windows.count, 1)
        XCTAssertEqual(measurement.windows[0].durationMinutes, 300)
    }

    func testFullPhase1ExampleDecodesWithoutSemanticLoss() throws {
        let snapshot = try UsageSyncSerialization.decode(try Fixture.exampleData("full.json"))
        XCTAssertEqual(snapshot.providers.map(\.providerId),
                       ["codex", "claude-code", "example-paused-provider"])

        // Codex: a duration window is the headline.
        let codex = try XCTUnwrap(snapshot.providers.first { $0.providerId == "codex" }?.measurement)
        XCTAssertEqual(codex.headlineWindowId, "duration-4320")
        XCTAssertEqual(codex.headlineRemainingPercent, 45)

        // Claude: ordinary weekly beside a model-qualified one.
        let claude = try XCTUnwrap(snapshot.providers.first { $0.providerId == "claude-code" }?.measurement)
        XCTAssertEqual(claude.windows.map(\.windowId), ["five-hour", "weekly", "weekly-opus"])
        XCTAssertEqual(claude.windows.first { $0.kind == .weeklyScoped }?.scope, "opus")
        XCTAssertEqual(claude.headlineWindowId, "five-hour")

        // The freshness case the contract exists for.
        XCTAssertLessThan(claude.measuredAt, snapshot.generatedAt)
        XCTAssertEqual(codex.measuredAt, snapshot.generatedAt)

        // A paused provider keeping an older reading, on an unknown window.
        let paused = try XCTUnwrap(snapshot.providers.first { $0.providerId == "example-paused-provider" })
        XCTAssertTrue(paused.connected)
        XCTAssertFalse(paused.collecting)
        XCTAssertEqual(paused.measurement?.windows.first?.position, 0)
    }

    func testPhase1ExamplesRoundTripThroughTheSwiftModel() throws {
        for name in ["minimal.json", "full.json"] {
            let decoded = try UsageSyncSerialization.decode(try Fixture.exampleData(name))
            let reDecoded = try UsageSyncSerialization.decode(try UsageSyncSerialization.encode(decoded))
            XCTAssertEqual(reDecoded, decoded, "\(name) lost meaning through the Swift model")
        }
    }

    // MARK: prohibited data has nowhere to go

    func testBuiltSnapshotEmitsOnlySchemaApprovedKeys() throws {
        try assertOnlyAllowedKeys(try UsageSyncSerialization.encode(try richSnapshot()))
    }

    func testPhase1ExamplesContainOnlySchemaApprovedKeys() throws {
        for name in ["minimal.json", "full.json"] {
            try assertOnlyAllowedKeys(try Fixture.exampleData(name))
        }
    }

    func testNoProhibitedPropertyCanAppearInAnEncodedSnapshot() throws {
        // Credentials, raw provider material, local machine detail, identity —
        // and the transport metadata the selected Tailscale overlay will have,
        // which must never reach the payload.
        let prohibited = [
            "accessToken", "refreshToken", "apiKey", "token", "cookie", "sessionId", "authorization",
            "rawOutput", "stdout", "stderr", "error", "command", "commandLine", "environment",
            "homeDirectory", "executablePath", "hostname", "userName", "accountId", "email",
            "url", "host", "port", "tailscaleIP", "magicDNS", "tailnet", "nodeKey", "apnsToken"
        ]
        let encoded = try UsageSyncSerialization.encode(try richSnapshot())
        let allKeys = Self.allowedTopLevelKeys
            .union(Self.allowedProviderKeys)
            .union(Self.allowedMeasurementKeys)
            .union(Self.allowedWindowKeys)

        for name in prohibited {
            XCTAssertFalse(allKeys.contains(name), "'\(name)' is a schema-approved key")
            XCTAssertFalse(
                try XCTUnwrap(String(data: encoded, encoding: .utf8)).contains("\"\(name)\":"),
                "'\(name)' appears as a property in an encoded snapshot"
            )
        }
    }

    func testDecodingIgnoresNothingAndAcceptsNoExtraFields() throws {
        // An unexpected property is not silently carried along: the typed model
        // has no storage for it, so it cannot survive a round trip.
        let withExtra = Data("""
        {"schemaVersion":1,"generatedAt":"2026-01-15T14:05:00Z","providers":[
          {"providerId":"codex","connected":true,"collecting":true,"accessToken":"x"}]}
        """.utf8)
        let decoded = try UsageSyncSerialization.decode(withExtra)
        let reEncoded = try XCTUnwrap(String(data: try UsageSyncSerialization.encode(decoded), encoding: .utf8))
        XCTAssertFalse(reEncoded.contains("accessToken"))
    }
}
