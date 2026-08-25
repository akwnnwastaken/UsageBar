using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Providers;

namespace UsageBar.Windows.Core.Policies;

/// <summary>
/// Holds the per-window state the display noise filter needs and produces the
/// smoothed copy of the provider readings used by the tray icon and the panel.
///
/// <see cref="Advance"/> must be called exactly once per completed refresh, and
/// only with the measurements that refresh newly accepted: calling it on every
/// redraw, or handing it the whole usage cache, would count a single reading
/// several times and accept a held rise too early.
/// </summary>
public sealed class UsageDisplayState
{
    private readonly Dictionary<string, int> _displayedRemaining = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _pendingRise = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _pendingCount = new(StringComparer.Ordinal);

    public void Advance(IReadOnlyDictionary<string, ProviderUsage> acceptedMeasurements)
    {
        ArgumentNullException.ThrowIfNull(acceptedMeasurements);

        foreach (var (providerName, usage) in acceptedMeasurements)
        {
            if (usage.Error is not null)
            {
                continue;
            }

            foreach (var window in usage.Windows)
            {
                var key = UsageHistoryModel.SeriesKey(providerName, window.Kind);
                var decision = UsageDisplayNoiseFilter.Decide(
                    window.RemainingPercent,
                    _displayedRemaining.TryGetValue(key, out var displayed) ? displayed : null,
                    _pendingRise.TryGetValue(key, out var pending) ? pending : null,
                    _pendingCount.TryGetValue(key, out var count) ? count : 0);

                _displayedRemaining[key] = decision.Displayed;
                if (decision.PendingRise is int rise)
                {
                    _pendingRise[key] = rise;
                }
                else
                {
                    _pendingRise.Remove(key);
                }

                _pendingCount[key] = decision.PendingCount;
            }
        }
    }

    /// <summary>
    /// The smoothed copy used for presentation only. History recording always
    /// works from the raw readings.
    /// </summary>
    public IReadOnlyDictionary<string, ProviderUsage> Apply(IReadOnlyDictionary<string, ProviderUsage> usages)
    {
        ArgumentNullException.ThrowIfNull(usages);

        var result = new Dictionary<string, ProviderUsage>(StringComparer.Ordinal);
        foreach (var (providerName, usage) in usages)
        {
            if (usage.Error is not null)
            {
                result[providerName] = usage;
                continue;
            }

            var windows = usage.Windows.Select(window =>
            {
                var key = UsageHistoryModel.SeriesKey(usage.Name, window.Kind);
                if (!_displayedRemaining.TryGetValue(key, out var displayed) ||
                    displayed == window.RemainingPercent)
                {
                    return window;
                }

                return window.WithRemainingPercent(displayed);
            }).ToList();

            result[providerName] = usage.ReplacingWindows(windows);
        }

        return result;
    }

    /// <summary>Forgets a provider's display state; used when it is disconnected.</summary>
    public void Forget(string providerName)
    {
        Remove(providerName, _displayedRemaining, _pendingRise, _pendingCount);
    }

    /// <summary>
    /// Drops a provider's half-proven rise while keeping what is on screen.
    ///
    /// This is the pause case, and it is deliberately not <see cref="Forget"/>:
    /// the measurements that would have confirmed the rise are not coming, so a
    /// pause of any length must not later be treated as though they had arrived
    /// consecutively — but the value the user is still looking at stays.
    /// </summary>
    public void ClearPendingRise(string providerName)
    {
        Remove(providerName, _pendingRise, _pendingCount);
    }

    private static void Remove(string providerName, params Dictionary<string, int>[] maps)
    {
        var prefix = providerName + "|";
        foreach (var map in maps)
        {
            foreach (var key in map.Keys.Where(key => key.StartsWith(prefix, StringComparison.Ordinal)).ToList())
            {
                map.Remove(key);
            }
        }
    }
}
