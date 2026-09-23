import Foundation
import UsageBarCore
@testable import UsageBarSync

/// Shared fixtures. Values are synthetic throughout: no percentage, timestamp
/// or provider state here was copied from a real machine.
enum Fixture {
    /// Repository root, resolved from this file so the committed Phase-1
    /// examples are read as they actually are rather than re-inlined here,
    /// where they could silently drift from the contract they illustrate.
    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // UsageBarSyncTests
        .deletingLastPathComponent()   // tests
        .deletingLastPathComponent()   // repository root

    static func exampleData(_ name: String) throws -> Data {
        try Data(contentsOf: repositoryRoot
            .appendingPathComponent("shared/sync-schema/examples")
            .appendingPathComponent(name))
    }

    static func date(_ rfc3339: String) -> Date {
        guard let value = UsageSyncSerialization.date(from: rfc3339) else {
            preconditionFailure("test fixture timestamp is malformed: \(rfc3339)")
        }
        return value
    }

    static let generatedAt = date("2026-01-15T14:05:00Z")
    static let measuredAt = date("2026-01-15T14:00:00Z")
    static let olderMeasuredAt = date("2026-01-15T11:20:00Z")

    static func window(
        _ kind: UsageWindowKind,
        used: Int,
        resetsAt: Date? = nil,
        durationMinutes: Int? = nil
    ) -> UsageWindow {
        UsageWindow(kind: kind, usedPercent: used, resetsAt: resetsAt, durationMinutes: durationMinutes)
    }

    /// A provider whose reading the desktop accepted at `measuredAt`.
    static func accepted(
        _ name: String,
        _ windows: [UsageWindow],
        at when: Date = measuredAt
    ) -> ProviderUsage {
        ProviderUsage(name: name, windows: windows, error: nil).markedSuccessful(at: when)
    }

    static func input(
        _ usage: ProviderUsage?,
        name: String,
        connected: Bool = true,
        collecting: Bool = true
    ) -> UsageSyncProviderInput {
        UsageSyncProviderInput(
            productName: name,
            connected: connected,
            collecting: collecting,
            displayFilteredUsage: usage
        )
    }

    // Claude with an active five-hour window plus the ordinary weekly one.
    static var claudeSessionAndWeekly: ProviderUsage {
        accepted("Claude Code", [
            window(.fiveHour, used: 41, resetsAt: date("2026-01-15T17:00:00Z"), durationMinutes: 300),
            window(.weekly, used: 18, resetsAt: date("2026-01-19T22:00:00Z"), durationMinutes: 10_080)
        ])
    }

    // Claude reporting only the weekly limit, which is the documented fallback.
    static var claudeWeeklyOnly: ProviderUsage {
        accepted("Claude Code", [
            window(.weekly, used: 18, resetsAt: date("2026-01-19T22:00:00Z"), durationMinutes: 10_080)
        ])
    }

    // The ordinary all-models weekly limit beside a model-qualified one.
    static var claudeWeeklyAndScoped: ProviderUsage {
        accepted("Claude Code", [
            window(.weekly, used: 18, durationMinutes: 10_080),
            window(.weeklyScoped(scope: "opus"), used: 7, durationMinutes: 10_080)
        ])
    }

    // Codex where a three-day window is more constrained than the weekly one,
    // so the product's most-constrained rule makes it the headline.
    static var codexDurationHeadline: ProviderUsage {
        accepted("Codex", [
            window(.weekly, used: 13, durationMinutes: 10_080),
            window(.duration(minutes: 4320), used: 55, durationMinutes: 4320)
        ])
    }

    static var codexUnknownWindow: ProviderUsage {
        accepted("Codex", [window(.unknown(position: 0), used: 70)])
    }
}
