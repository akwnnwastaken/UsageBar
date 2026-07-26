using UsageBar.Windows.Core.Providers;

namespace UsageBar.Windows.Core.History;

/// <summary>
/// Turns a completed refresh into new history samples.
///
/// Two parity rules live here: a provider whose refresh failed contributes
/// nothing (a stale value is never recorded as a new sample), and the recorded
/// value is always the <b>raw</b> remaining percentage — the display noise
/// filter never touches stored history.
/// </summary>
public static class UsageHistoryRecorder
{
    public static IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> Record(
        IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> history,
        IReadOnlyDictionary<string, ProviderUsage> usages,
        IReadOnlyList<string> connectedProviderNames,
        DateTimeOffset at)
    {
        ArgumentNullException.ThrowIfNull(history);
        ArgumentNullException.ThrowIfNull(usages);
        ArgumentNullException.ThrowIfNull(connectedProviderNames);

        var updated = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(history, StringComparer.Ordinal);

        foreach (var providerName in connectedProviderNames)
        {
            if (!usages.TryGetValue(providerName, out var usage) || usage.Error is not null)
            {
                continue;
            }

            foreach (var window in usage.Windows)
            {
                var key = UsageHistoryModel.SeriesKey(providerName, window.Kind);
                updated.TryGetValue(key, out var existing);
                updated[key] = UsageHistoryModel.Adding(
                    window.RemainingPercent,
                    at,
                    existing ?? Array.Empty<UsageHistorySample>());
            }
        }

        return UsageHistoryModel.Sanitized(updated, at);
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
