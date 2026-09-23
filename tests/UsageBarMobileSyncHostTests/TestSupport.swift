import Foundation
import UsageBarCore
import UsageBarSync
@testable import UsageBarMobileSyncHost

/// Synthetic desktop state. Every number here is invented; nothing in this file
/// corresponds to a real account or a real measurement.
enum HostFixtures {
    static let measuredAt = Date(timeIntervalSince1970: 1_772_000_000)
    static let generatedAt = measuredAt.addingTimeInterval(120)

    static func window(
        _ kind: UsageWindowKind,
        usedPercent: Int,
        durationMinutes: Int?,
        resetsAt: Date? = measuredAt.addingTimeInterval(3600)
    ) -> UsageWindow {
        UsageWindow(
            kind: kind,
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            durationMinutes: durationMinutes
        )
    }

    /// A Codex reading with a five-hour and a weekly window.
    static func codexUsage(
        fiveHourUsed: Int = 36,
        weeklyUsed: Int = 19,
        measuredAt: Date = HostFixtures.measuredAt,
        error: ProviderIssue? = nil
    ) -> ProviderUsage {
        ProviderUsage(
            name: "Codex",
            windows: [
                window(.fiveHour, usedPercent: fiveHourUsed, durationMinutes: 300),
                window(.weekly, usedPercent: weeklyUsed, durationMinutes: 10_080)
            ],
            error: error,
            lastSuccessfulAt: measuredAt
        )
    }

    static func claudeUsage(
        fiveHourUsed: Int = 48,
        weeklyUsed: Int = 24,
        measuredAt: Date = HostFixtures.measuredAt,
        error: ProviderIssue? = nil
    ) -> ProviderUsage {
        ProviderUsage(
            name: "Claude Code",
            windows: [
                window(.fiveHour, usedPercent: fiveHourUsed, durationMinutes: 300),
                window(.weekly, usedPercent: weeklyUsed, durationMinutes: 10_080)
            ],
            error: error,
            lastSuccessfulAt: measuredAt
        )
    }

    static func state(
        _ productName: String,
        connected: Bool = true,
        collecting: Bool = true,
        usage: ProviderUsage?
    ) -> MobileSyncLiveSnapshot.ProviderState {
        MobileSyncLiveSnapshot.ProviderState(
            productName: productName,
            connected: connected,
            collecting: collecting,
            displayFilteredUsage: usage
        )
    }

    static var bothCollecting: [MobileSyncLiveSnapshot.ProviderState] {
        [
            state("Codex", usage: codexUsage()),
            state("Claude Code", usage: claudeUsage())
        ]
    }

    static func snapshot(
        _ states: [MobileSyncLiveSnapshot.ProviderState] = HostFixtures.bothCollecting
    ) throws -> UsageSyncSnapshot {
        try MobileSyncLiveSnapshot.build(from: states, generatedAt: generatedAt)
    }

    static let identity = "owner@example.invalid"
    static let otherIdentity = "someone-else@example.invalid"
    static let host = "example-machine.example-tailnet.ts.net"
}
