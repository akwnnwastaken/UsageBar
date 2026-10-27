using UsageBar.Windows.Core.Providers;

namespace UsageBar.Windows.Core.History;

/// <summary>
/// Turns the measurements a refresh actually accepted into new history samples.
///
/// The input is the accepted set, never the usage cache: a provider that was
/// not read this cycle — paused, disconnected, or simply not part of it — keeps
/// its last reading on screen, and re-recording that reading would draw a flat
/// line of measurements that never happened.
///
/// Two parity rules live here: a provider whose refresh failed contributes
/// nothing (a stale value is never recorded as a new sample), and the recorded
/// value is always the <b>raw</b> remaining percentage — the display noise
/// filter never touches stored history.
/// The separate seven-day archive records only the ordinary weekly quota;
/// mini history still records every window.
/// </summary>
public static class UsageHistoryRecorder
{
    public static IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> Record(
        IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> history,
        IReadOnlyDictionary<string, ProviderUsage> acceptedMeasurements,
        DateTimeOffset at,
        bool weekly = false)
    {
        ArgumentNullException.ThrowIfNull(history);
        ArgumentNullException.ThrowIfNull(acceptedMeasurements);

        var updated = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(history, StringComparer.Ordinal);

        foreach (var (providerName, usage) in acceptedMeasurements)
        {
            if (usage.Error is not null)
            {
                continue;
            }

            foreach (var window in usage.Windows)
            {
                if (weekly && window.Kind != UsageWindowKind.Weekly) continue;
                var key = UsageHistoryModel.SeriesKey(providerName, window.Kind);
                updated.TryGetValue(key, out var existing);
                updated[key] = UsageHistoryModel.Adding(
                    window.RemainingPercent,
                    at,
                    existing ?? Array.Empty<UsageHistorySample>(),
                    weekly);
            }
        }

        return UsageHistoryModel.Sanitized(updated, at, weekly);
    }

    /// <summary>
    /// Drops every series belonging to a provider. Only the explicit "clear
    /// history" action uses this — disconnecting a provider must not erase it.
    /// </summary>
    public static IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> RemovingProvider(
        IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> history,
        string providerName)
    {
        ArgumentNullException.ThrowIfNull(history);

        var prefix = providerName + "|";
        return history
            .Where(entry => !entry.Key.StartsWith(prefix, StringComparison.Ordinal))
            .ToDictionary(entry => entry.Key, entry => entry.Value, StringComparer.Ordinal);
    }
}
