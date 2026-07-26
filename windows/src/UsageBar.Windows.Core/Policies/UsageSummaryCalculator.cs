using UsageBar.Windows.Core.Providers;

namespace UsageBar.Windows.Core.Policies;

/// <summary>The window a provider contributes to the tray icon.</summary>
public sealed record UsageSummary(
    string ProviderName,
    int RemainingPercent,
    DateTimeOffset? ResetsAt,
    UsageWindowKind WindowKind);

/// <summary>
/// Provider-specific status selection, ported unchanged from macOS:
/// Claude Code shows the five-hour window and only falls back to weekly when no
/// five-hour data came back; every other provider shows its most constrained
/// window (highest used percentage, i.e. lowest remaining).
/// </summary>
public static class UsageSummaryCalculator
{
    public static UsageSummary? Summary(string providerName, IReadOnlyDictionary<string, ProviderUsage> usages)
    {
        ArgumentNullException.ThrowIfNull(usages);

        if (!usages.TryGetValue(providerName, out var usage))
        {
            return null;
        }

        var selected = providerName == ProviderNames.ClaudeCode
            ? usage.Session ?? usage.Weekly
            : MostConstrained(usage.Windows);

        if (selected is null)
        {
            return null;
        }

        return new UsageSummary(
            providerName,
            Math.Clamp(100 - selected.UsedPercent, 0, 100),
            selected.ResetsAt,
            selected.Kind);
    }

    /// <summary>
    /// Highest used percentage wins. Ties keep the earlier window, matching the
    /// Swift <c>max(by:)</c> semantics the macOS build relies on.
    /// </summary>
    private static UsageWindow? MostConstrained(IReadOnlyList<UsageWindow> windows)
    {
        UsageWindow? best = null;
        foreach (var window in windows)
        {
            if (best is null || window.UsedPercent > best.UsedPercent)
            {
                best = window;
            }
        }

        return best;
    }
}
