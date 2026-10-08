import Foundation

/// Selection for the macOS status item only; history and mobile headlines use
/// `UsageSummaryCalculator` independently.
public enum MenuBarUsageSummaryCalculator {
    public static func summary(for providerName: String, in usages: [String: ProviderUsage]) -> UsageSummary? {
        guard providerName == "Claude Code" || providerName == "Codex",
              let usage = usages[providerName], let weekly = usage.weekly else {
            return UsageSummaryCalculator.summary(for: providerName, in: usages)
        }

        let selectedWindows: [UsageWindow]
        if remainingPercent(weekly) < 10 {
            // Weekly wins ties. Other kinds do not replace the explicit
            // five-hour-versus-weekly comparison once weekly is eligible.
            if let session = usage.session, remainingPercent(session) < remainingPercent(weekly) {
                selectedWindows = [session]
            } else {
                selectedWindows = [weekly]
            }
        } else {
            // Exclude only the ordinary weekly limit, preserving the original
            // provider policy for scoped, duration and unknown windows.
            selectedWindows = usage.windows.filter { $0.kind != .weekly }
            if let nonWeeklySummary = UsageSummaryCalculator.summary(
                for: providerName,
                in: [providerName: usage.replacingWindows(selectedWindows)]
            ) {
                return nonWeeklySummary
            }
            // Weekly-only accounts (or unsupported non-weekly headline kinds)
            // still need a value, even above the weekly preference threshold.
            return UsageSummaryCalculator.summary(
                for: providerName,
                in: [providerName: usage.replacingWindows([weekly])]
            )
        }
        return UsageSummaryCalculator.summary(
            for: providerName,
            in: [providerName: usage.replacingWindows(selectedWindows)]
        )
    }

    private static func remainingPercent(_ window: UsageWindow) -> Int {
        min(100, max(0, 100 - window.usedPercent))
    }
}
