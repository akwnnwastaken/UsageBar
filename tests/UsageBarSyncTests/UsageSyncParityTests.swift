import XCTest
import UsageBarCore
@testable import UsageBarSync

/// Cross-platform parity.
///
/// The five files in `shared/sync-schema/parity/` are the **oracle** for both
/// the Swift and the C# builder. Each case here builds a snapshot from
/// equivalent macOS product state and compares it, as typed values, against the
/// canonical fixture. `windows/tests/UsageBar.Windows.Sync.Tests` runs the
/// matching assertions against the very same files, so the two platforms are
/// held to one contract rather than to two descriptions of one.
///
/// Comparison is semantic, never raw JSON bytes: key order is not protocol.
final class UsageSyncParityTests: XCTestCase {

    private static let generatedAt = UsageSyncSerialization.date(from: "2026-03-04T09:00:00Z")!

    private func fixture(_ name: String) throws -> UsageSyncSnapshot {
        let url = Fixture.repositoryRoot
            .appendingPathComponent("shared/sync-schema/parity")
            .appendingPathComponent(name)
        return try UsageSyncSerialization.decode(try Data(contentsOf: url))
    }

    private func at(_ rfc3339: String) -> Date {
        UsageSyncSerialization.date(from: rfc3339)!
    }

    /// Builds, validates both sides, and asserts typed equality.
    private func assertParity(
        _ fixtureName: String,
        _ inputs: [UsageSyncProviderInput],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expected = try fixture(fixtureName)
        let built = try UsageSyncSnapshotBuilder.snapshot(
            from: inputs, generatedAt: Self.generatedAt
        )
        try UsageSyncValidator.validate(expected)
        try UsageSyncValidator.validate(built)
        XCTAssertEqual(built, expected, "\(fixtureName): Swift builder output differs", file: file, line: line)
    }

    // MARK: the five canonical cases

    func testParityBasic() throws {
        let codex = ProviderUsage(
            name: "Codex",
            windows: [
                UsageWindow(kind: .fiveHour, usedPercent: 36,
                            resetsAt: at("2026-03-04T13:00:00Z"), durationMinutes: 300),
                UsageWindow(kind: .weekly, usedPercent: 19,
                            resetsAt: at("2026-03-08T00:00:00Z"), durationMinutes: 10_080)
            ],
            error: nil
        ).markedSuccessful(at: at("2026-03-04T09:00:00Z"))

        let claude = ProviderUsage(
            name: "Claude Code",
            windows: [
                UsageWindow(kind: .fiveHour, usedPercent: 48,
                            resetsAt: at("2026-03-04T12:30:00Z"), durationMinutes: 300),
                UsageWindow(kind: .weekly, usedPercent: 24,
                            resetsAt: at("2026-03-09T19:00:00Z"), durationMinutes: 10_080)
            ],
            error: nil
        ).markedSuccessful(at: at("2026-03-04T08:55:00Z"))

        try assertParity("basic.json", [
            Fixture.input(codex, name: "Codex"),
            Fixture.input(claude, name: "Claude Code")
        ])
    }

    func testParityClaudeWeeklyScoped() throws {
        // No five-hour window, so Claude's policy falls back to the ordinary
        // all-models weekly — never to the model-qualified one.
        let claude = ProviderUsage(
            name: "Claude Code",
            windows: [
                UsageWindow(kind: .weekly, usedPercent: 26,
                            resetsAt: at("2026-03-09T19:00:00Z"), durationMinutes: 10_080),
                UsageWindow(kind: .weeklyScoped(scope: "opus"), usedPercent: 9,
                            resetsAt: at("2026-03-09T19:00:00Z"), durationMinutes: 10_080)
            ],
            error: nil
        ).markedSuccessful(at: at("2026-03-04T08:58:00Z"))

        try assertParity("claude-weekly-scoped.json", [Fixture.input(claude, name: "Claude Code")])
    }

    func testParityPausedRetained() throws {
        // Paused: still connected, not collecting, and the reading it was
        // holding survives with its original measurement time.
        let codex = ProviderUsage(
            name: "Codex",
            windows: [
                UsageWindow(kind: .fiveHour, usedPercent: 62,
                            resetsAt: at("2026-03-04T10:00:00Z"), durationMinutes: 300)
            ],
            error: nil
        ).markedSuccessful(at: at("2026-03-04T06:15:00Z"))

        try assertParity("paused-retained.json", [
            Fixture.input(codex, name: "Codex", connected: true, collecting: false)
        ])
    }

    func testParityCodexDurationHeadline() throws {
        // The three-day window is more constrained than the weekly one, so the
        // product's most-constrained rule makes it the headline.
        let codex = ProviderUsage(
            name: "Codex",
            windows: [
                UsageWindow(kind: .weekly, usedPercent: 13,
                            resetsAt: at("2026-03-08T00:00:00Z"), durationMinutes: 10_080),
                UsageWindow(kind: .duration(minutes: 4320), usedPercent: 55,
                            resetsAt: at("2026-03-06T06:00:00Z"), durationMinutes: 4320)
            ],
            error: nil
        ).markedSuccessful(at: at("2026-03-04T09:00:00Z"))

        try assertParity("codex-duration-headline.json", [Fixture.input(codex, name: "Codex")])
    }

    func testParityUnknownWindow() throws {
        let codex = ProviderUsage(
            name: "Codex",
            windows: [UsageWindow(kind: .unknown(position: 2), usedPercent: 70,
                                  resetsAt: nil, durationMinutes: nil)],
            error: nil
        ).markedSuccessful(at: at("2026-03-04T08:45:00Z"))

        try assertParity("unknown-window.json", [Fixture.input(codex, name: "Codex")])
    }

    // MARK: the fixtures themselves

    func testEveryParityFixtureDecodesAndValidates() throws {
        for name in ["basic.json", "claude-weekly-scoped.json", "paused-retained.json",
                     "codex-duration-headline.json", "unknown-window.json"] {
            let snapshot = try fixture(name)
            XCTAssertEqual(snapshot.schemaVersion, 1, "\(name)")
            XCTAssertEqual(snapshot.generatedAt, Self.generatedAt, "\(name)")
            XCTAssertFalse(snapshot.providers.isEmpty, "\(name)")
        }
    }

    func testParityFixturesRoundTripThroughTheSwiftModel() throws {
        for name in ["basic.json", "claude-weekly-scoped.json", "paused-retained.json",
                     "codex-duration-headline.json", "unknown-window.json"] {
            let decoded = try fixture(name)
            let reDecoded = try UsageSyncSerialization.decode(try UsageSyncSerialization.encode(decoded))
            XCTAssertEqual(reDecoded, decoded, "\(name) lost meaning through the Swift model")
        }
    }

    // MARK: identity table, mirrored case for case in the C# suite

    func testProviderIdentityTable() {
        let cases: [(String, String?)] = [
            ("Codex", "codex"),
            ("Claude Code", "claude-code"),
            ("  Claude---Code  ", "claude-code"),
            ("Claude.Code!", "claude-code"),
            ("Claude — Code", "claude-code"),
            ("GPT 4o", "gpt-4o"),
            ("", nil),
            ("   ", nil),
            ("—", nil),
            ("!!!", nil)
        ]
        for (input, expected) in cases {
            XCTAssertEqual(UsageSyncIdentity.providerId(forProductName: input), expected,
                           "provider identity for '\(input)'")
        }
    }

    func testWindowIdentityTable() {
        let cases: [(UsageWindowKind, String)] = [
            (.fiveHour, "five-hour"),
            (.weekly, "weekly"),
            (.weeklyScoped(scope: "opus"), "weekly-opus"),
            (.duration(minutes: 4320), "duration-4320"),
            (.unknown(position: 2), "unknown-2")
        ]
        for (kind, expected) in cases {
            XCTAssertEqual(UsageSyncIdentity.windowId(for: kind), expected)
        }
    }
}
