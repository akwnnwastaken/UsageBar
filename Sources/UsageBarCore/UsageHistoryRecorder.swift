import Foundation

/// Turns the measurements a refresh actually accepted into history samples.
///
/// The input is the accepted set, never the usage cache. A provider that was
/// not read this cycle — paused, disconnected, or simply not part of it — keeps
/// its last reading on screen, and re-recording that reading would draw a flat
/// line of measurements that never happened. A provider whose read failed
/// contributes nothing either: the stale value it still shows is not a new
/// measurement.
public enum UsageHistoryRecorder {
    /// Series are keyed by provider and window, so one provider's series share
    /// a `provider|` prefix.
    public static func seriesKey(providerName: String, windowKind: UsageWindowKind) -> String {
        "\(providerName)|\(windowKind.historyKey)"
    }

    /// Adds one sample per window of every accepted measurement, then applies
    /// retention to the whole history.
    public static func recording(
        _ history: [String: [UsageHistorySample]],
        measurements: [String: ProviderUsage],
        at date: Date
    ) -> [String: [UsageHistorySample]] {
        var updated = history

        for (providerName, usage) in measurements where usage.error == nil {
            // Series recorded before windows were separated were keyed by the
            // provider alone. Move such a series onto the key its primary
            // window now uses, so an upgrade keeps its chart instead of
            // starting an empty one beside the old data.
            if let legacySamples = updated.removeValue(forKey: providerName),
               let summary = UsageSummaryCalculator.summary(for: providerName, in: measurements) {
                let migratedKey = seriesKey(providerName: providerName, windowKind: summary.windowKind)
                if updated[migratedKey] == nil {
                    updated[migratedKey] = legacySamples
                }
            }

            for window in usage.windows {
                let key = seriesKey(providerName: providerName, windowKind: window.kind)
                updated[key] = UsageHistoryModel.adding(
                    remainingPercent: min(100, max(0, 100 - window.usedPercent)),
                    at: date,
                    to: updated[key] ?? []
                )
            }
        }

        return UsageHistoryModel.sanitized(updated, now: date)
    }
}
