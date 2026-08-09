import Foundation
import XCTest
@testable import UsageBarCore

final class UsageSnapshotV1Tests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_893_499_200)
    private let codexSuccessAt = Date(timeIntervalSince1970: 1_893_499_140)
    private let claudeSuccessAt = Date(timeIntervalSince1970: 1_893_499_080)

    func testSchemaVersionAndProviderIdentifiersAreStable() throws {
        let snapshot = try project(codexEnabled: false, claudeEnabled: false)
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.providers.map(\.id), [.codex, .claude])

        let object = try jsonObject(snapshot)
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        let providers = try XCTUnwrap(object["providers"] as? [[String: Any]])
        XCTAssertEqual(providers.compactMap { $0["id"] as? String }, ["codex", "claude"])
    }

    func testProjectionExportsEveryRawWindowInsteadOfDisplaySelection() throws {
        let codex = ProviderUsage(
            name: "Codex",
            windows: [
                window(.fiveHour, used: 20, duration: 300),
                window(.weekly, used: 82, duration: 10_080),
                window(.duration(minutes: 4_320), used: 47, duration: 4_320)
            ],
            error: nil,
            lastSuccessfulAt: codexSuccessAt
        )
        let claude = ProviderUsage(
            name: "Claude Code",
            windows: [
                window(.fiveHour, used: 31, duration: 300),
                window(.weekly, used: 91, duration: 10_080)
            ],
            error: nil,
            lastSuccessfulAt: claudeSuccessAt
        )
        let usages = ["Codex": codex, "Claude Code": claude]

        XCTAssertEqual(UsageSummaryCalculator.summary(for: "Codex", in: usages)?.windowKind, .weekly)
        XCTAssertEqual(UsageSummaryCalculator.summary(for: "Claude Code", in: usages)?.windowKind, .fiveHour)

        let snapshot = try project(usages: usages)
        XCTAssertEqual(snapshot.provider(.codex).windows.count, 3)
        XCTAssertEqual(snapshot.provider(.claude).windows.count, 2)
        XCTAssertEqual(snapshot.provider(.codex).windows.map(\.usedPercent), [20, 82, 47])
        XCTAssertEqual(snapshot.provider(.claude).windows.map(\.usedPercent), [31, 91])
    }

    func testWindowKindsDurationsPercentagesAndResetOptionalsAreStable() throws {
        let resetAt = Date(timeIntervalSince1970: 1_893_502_800)
        let codex = ProviderUsage(
            name: "Codex",
            windows: [
                window(.fiveHour, used: 12, duration: 300, resetAt: resetAt),
                window(.weekly, used: 34, duration: 10_080),
                window(.duration(minutes: 720), used: 56, duration: 720),
                window(.unknown(position: 3), used: 78, duration: nil)
            ],
            error: nil,
            lastSuccessfulAt: codexSuccessAt
        )
        let snapshot = try project(codexEnabled: true, claudeEnabled: false, usages: ["Codex": codex])
        let windows = snapshot.provider(.codex).windows

        XCTAssertEqual(windows.map(\.kind), [.fiveHour, .weekly, .duration, .unknown])
        XCTAssertEqual(windows.map(\.durationMinutes), [300, 10_080, 720, nil])
        XCTAssertEqual(windows.map(\.usedPercent), [12, 34, 56, 78])
        XCTAssertEqual(windows.first?.resetAt, resetAt)
        XCTAssertNil(windows.last?.resetAt)

        let object = try jsonObject(snapshot)
        let encodedWindows = try providerObject(.codex, in: object)["windows"] as? [[String: Any]]
        XCTAssertEqual(encodedWindows?.map { $0["kind"] as? String }, ["fiveHour", "weekly", "duration", "unknown"])
        XCTAssertEqual(encodedWindows?.first?["resetAt"] as? String, "2030-01-01T13:00:00.000Z")
        XCTAssertTrue(encodedWindows?.last?["resetAt"] is NSNull)
        XCTAssertTrue(encodedWindows?.last?["durationMinutes"] is NSNull)
    }

    func testObservationTimeDoesNotReplaceProviderLastSuccess() throws {
        let codex = ProviderUsage(
            name: "Codex",
            windows: [window(.weekly, used: 40, duration: 10_080)],
            error: nil,
            lastSuccessfulAt: codexSuccessAt
        )
        let snapshot = try project(codexEnabled: true, claudeEnabled: false, usages: ["Codex": codex])

        XCTAssertEqual(snapshot.observedAt, observedAt)
        XCTAssertEqual(snapshot.provider(.codex).lastSuccessfulAt, codexSuccessAt)
        XCTAssertNotEqual(snapshot.provider(.codex).lastSuccessfulAt, snapshot.observedAt)

        let object = try jsonObject(snapshot)
        XCTAssertEqual(object["observedAt"] as? String, "2030-01-01T12:00:00.000Z")
        XCTAssertEqual(
            try providerObject(.codex, in: object)["lastSuccessfulAt"] as? String,
            "2030-01-01T11:59:00.000Z"
        )
    }

    func testStaleStateRetainsWindowsAndDropsRawErrorDetail() throws {
        let privateDetail = "internal-detail-must-never-cross-the-wire"
        let codex = ProviderUsage(
            name: "Codex",
            windows: [window(.weekly, used: 73, duration: 10_080)],
            error: .codexLaunchFailed(privateDetail),
            lastSuccessfulAt: codexSuccessAt
        )
        let snapshot = try project(codexEnabled: true, claudeEnabled: false, usages: ["Codex": codex])
        let provider = snapshot.provider(.codex)

        XCTAssertEqual(provider.state, .stale)
        XCTAssertEqual(provider.windows.map(\.usedPercent), [73])
        XCTAssertEqual(provider.lastSuccessfulAt, codexSuccessAt)
        XCTAssertEqual(provider.error?.code, .launchFailed)

        let json = String(decoding: try UsageSnapshotV1JSON.encode(snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains(privateDetail))
        XCTAssertFalse(json.contains("codexLaunchFailed"))
        XCTAssertTrue(json.contains("\"code\":\"launch_failed\""))
    }

    func testDisabledAndNeverSuccessfulUnavailableAreDistinct() throws {
        let snapshot = try project(codexEnabled: false, claudeEnabled: true)
        let disabled = snapshot.provider(.codex)
        let unavailable = snapshot.provider(.claude)

        XCTAssertEqual(disabled.state, .disabled)
        XCTAssertNil(disabled.lastSuccessfulAt)
        XCTAssertNil(disabled.error)
        XCTAssertTrue(disabled.windows.isEmpty)

        XCTAssertEqual(unavailable.state, .unavailable)
        XCTAssertNil(unavailable.lastSuccessfulAt)
        XCTAssertEqual(unavailable.error?.code, .noData)
        XCTAssertTrue(unavailable.windows.isEmpty)

        let object = try jsonObject(snapshot)
        XCTAssertTrue(try providerObject(.codex, in: object)["error"] is NSNull)
        XCTAssertTrue(try providerObject(.claude, in: object)["lastSuccessfulAt"] is NSNull)
    }

    func testUnavailableProviderMapsInternalFailuresToAllowlistedCodes() throws {
        let claude = ProviderUsage.unavailable("Claude Code", .claudeNotLoggedIn)
        let snapshot = try project(codexEnabled: false, claudeEnabled: true, usages: ["Claude Code": claude])
        XCTAssertEqual(snapshot.provider(.claude).state, .unavailable)
        XCTAssertEqual(snapshot.provider(.claude).error?.code, .notAuthenticated)
    }

    func testInvalidPercentageIsRejectedWithoutClamping() {
        let usage = ProviderUsage(
            name: "Codex",
            windows: [window(.weekly, used: 101, duration: 10_080)],
            error: nil,
            lastSuccessfulAt: codexSuccessAt
        )

        XCTAssertThrowsError(
            try project(codexEnabled: true, claudeEnabled: false, usages: ["Codex": usage])
        ) { error in
            XCTAssertEqual(error as? UsageSnapshotV1ValidationError, .invalidUsedPercent(101))
        }
    }

    func testInvalidDurationIsRejected() {
        let usage = ProviderUsage(
            name: "Codex",
            windows: [window(.duration(minutes: 0), used: 10, duration: 0)],
            error: nil,
            lastSuccessfulAt: codexSuccessAt
        )

        XCTAssertThrowsError(
            try project(codexEnabled: true, claudeEnabled: false, usages: ["Codex": usage])
        ) { error in
            XCTAssertEqual(error as? UsageSnapshotV1ValidationError, .invalidDurationMinutes(0))
        }
    }

    func testSerializationOmitsDerivedSchedulingAndImplementationFields() throws {
        let codex = ProviderUsage(
            name: "Codex",
            windows: [window(.fiveHour, used: 66, duration: 300)],
            error: nil,
            lastSuccessfulAt: codexSuccessAt
        )
        let data = try UsageSnapshotV1JSON.encode(
            project(codexEnabled: true, claudeEnabled: false, usages: ["Codex": codex])
        )
        let json = String(decoding: data, as: UTF8.self)

        for forbidden in [
            "remainingPercent", "windowId", "nearLimit", "exhausted", "agentAvailable",
            "shouldRun", "scheduler", "job", "command", "source", "Codex", "Claude Code"
        ] {
            XCTAssertFalse(json.contains(forbidden), "Unexpected public field or implementation detail: \(forbidden)")
        }
    }

    func testSerializationIsDeterministicAndSemanticallyStable() throws {
        let codex = ProviderUsage(
            name: "Codex",
            windows: [window(.weekly, used: 44, duration: 10_080)],
            error: nil,
            lastSuccessfulAt: codexSuccessAt
        )
        let snapshot = try project(codexEnabled: true, claudeEnabled: false, usages: ["Codex": codex])
        let first = try UsageSnapshotV1JSON.encode(snapshot)
        let second = try UsageSnapshotV1JSON.encode(snapshot)

        XCTAssertEqual(first, second)
        XCTAssertEqual(try UsageSnapshotV1JSON.decode(first), snapshot)
        XCTAssertTrue(try semanticJSONEqual(first, second))
    }

    func testDecoderRequiresNullableFieldsToBePresentAndAcceptsExplicitNull() throws {
        let explicitNull = Data("""
        {
          "schemaVersion": 1,
          "observedAt": "2030-01-01T12:00:00.000Z",
          "providers": [
            {
              "id": "codex",
              "state": "disabled",
              "lastSuccessfulAt": null,
              "error": null,
              "windows": []
            },
            {
              "id": "claude",
              "state": "fresh",
              "lastSuccessfulAt": "2030-01-01T11:59:00.000Z",
              "error": null,
              "windows": [
                {
                  "kind": "unknown",
                  "durationMinutes": null,
                  "usedPercent": 10,
                  "resetAt": null
                }
              ]
            }
          ]
        }
        """.utf8)
        XCTAssertNoThrow(try UsageSnapshotV1JSON.decode(explicitNull))

        let missingResetAt = Data(
            String(decoding: explicitNull, as: UTF8.self)
                .replacingOccurrences(of: "\"resetAt\": null", with: "\"resetAtOmitted\": null")
                .utf8
        )
        XCTAssertThrowsError(try UsageSnapshotV1JSON.decode(missingResetAt))
    }

    func testSharedFixturesAreValidV1JSONAndDecode() throws {
        for name in fixtureNames {
            let data = try Data(contentsOf: fixtureURL(name))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["schemaVersion"] as? Int, 1, name)

            let decoded = try UsageSnapshotV1JSON.decode(data)
            XCTAssertEqual(decoded.schemaVersion, 1, name)
            XCTAssertEqual(decoded.providers.map(\.id), [.codex, .claude], name)

            let encoded = try UsageSnapshotV1JSON.encode(decoded)
            XCTAssertTrue(try semanticJSONEqual(data, encoded), name)

            let text = String(decoding: data, as: UTF8.self)
            for forbidden in [
                "remainingPercent", "windowId", "rawError", "message", "command", "session",
                "credential", "token", "password", "session-link"
            ] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), "\(name): \(forbidden)")
            }
        }
    }

    func testSharedFixturesCoverRequiredStatesKindsAndNullReset() throws {
        let snapshots = try fixtureNames.map { name in
            try UsageSnapshotV1JSON.decode(Data(contentsOf: fixtureURL(name)))
        }
        let providers = snapshots.flatMap(\.providers)
        XCTAssertEqual(Set(providers.map(\.state)), Set([.disabled, .unavailable, .fresh, .stale]))
        XCTAssertEqual(
            Set(providers.flatMap(\.windows).map(\.kind)),
            Set([.fiveHour, .weekly, .duration, .unknown])
        )
        XCTAssertTrue(providers.contains { $0.state == .stale && !$0.windows.isEmpty && $0.error != nil })
        XCTAssertTrue(providers.contains { $0.state == .unavailable && $0.lastSuccessfulAt == nil })
        XCTAssertTrue(providers.flatMap(\.windows).contains { $0.resetAt == nil })
    }

    private var fixtureNames: [String] {
        ["fresh-multiple-windows.json", "stale-and-disabled.json", "unavailable.json"]
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/contract/v1")
            .appendingPathComponent(name)
    }

    private func project(
        codexEnabled: Bool = true,
        claudeEnabled: Bool = true,
        usages: [String: ProviderUsage] = [:]
    ) throws -> UsageSnapshotV1 {
        try UsageSnapshotV1Projection.project(
            UsageSnapshotV1ProjectionInput(
                codexIsEnabled: codexEnabled,
                claudeIsEnabled: claudeEnabled,
                usages: usages
            ),
            observedAt: observedAt
        )
    }

    private func window(
        _ kind: UsageWindowKind,
        used: Int,
        duration: Int?,
        resetAt: Date? = nil
    ) -> UsageWindow {
        UsageWindow(kind: kind, usedPercent: used, resetsAt: resetAt, durationMinutes: duration)
    }

    private func jsonObject(_ snapshot: UsageSnapshotV1) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: UsageSnapshotV1JSON.encode(snapshot)) as? [String: Any]
        )
    }

    private func providerObject(
        _ id: UsageProviderIDV1,
        in object: [String: Any]
    ) throws -> [String: Any] {
        let providers = try XCTUnwrap(object["providers"] as? [[String: Any]])
        return try XCTUnwrap(providers.first { $0["id"] as? String == id.rawValue })
    }

    private func semanticJSONEqual(_ lhs: Data, _ rhs: Data) throws -> Bool {
        let left = try JSONSerialization.jsonObject(with: lhs) as AnyObject
        let right = try JSONSerialization.jsonObject(with: rhs) as AnyObject
        return left.isEqual(right)
    }
}

private extension UsageSnapshotV1 {
    func provider(_ id: UsageProviderIDV1) -> ProviderSnapshotV1 {
        providers.first { $0.id == id }!
    }
}
