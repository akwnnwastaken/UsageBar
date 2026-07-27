using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Providers;

namespace UsageBar.Windows.Core.Policies;

/// <summary>
/// Windows has no persistent text label next to a tray icon, so the remaining
/// percentage is rendered inside the icon itself. This enumerates the states the
/// icon must be able to express.
/// </summary>
public enum TrayIconState
{
    /// <summary>A percentage within normal range.</summary>
    Normal,

    /// <summary>A percentage at or below the warning threshold.</summary>
    Warning,

    /// <summary>A percentage at or below the critical threshold.</summary>
    Critical,

    /// <summary>No provider data at all — drawn as an em dash.</summary>
    NoData,

    /// <summary>A refresh is in flight — drawn as a refresh glyph.</summary>
    Refreshing,

    /// <summary>The last known value, kept visible after a failed refresh.</summary>
    Stale
}

/// <summary>What the tray icon should draw and what its tooltip should say.</summary>
public sealed record TrayPresentation(
    TrayIconState State,
    string Label,
    int? RemainingPercent,
    string Tooltip)
{
    /// <summary>
    /// Color alone never carries meaning: the label text and the tooltip both
    /// describe the state, so the icon stays understandable in a monochrome or
    /// high-contrast setting.
    /// </summary>
    public const string NoDataLabel = "—";

    public const string RefreshingLabel = "↻";
}

public static class TrayPresentationCalculator
{
    /// <summary>Maximum tooltip length Windows shell tooltips reliably accept.</summary>
    public const int MaximumTooltipLength = 127;

    public static TrayPresentation Calculate(
        string? statusProviderName,
        IReadOnlyDictionary<string, ProviderUsage> displayUsages,
        UsageAlertPolicy alertPolicy,
        Localizer text,
        bool isRefreshing,
        bool showResetCountdown,
        DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(displayUsages);
        ArgumentNullException.ThrowIfNull(text);

        var summary = statusProviderName is null
            ? null
            : UsageSummaryCalculator.Summary(statusProviderName, displayUsages);

        if (summary is null)
        {
            var label = isRefreshing ? TrayPresentation.RefreshingLabel : TrayPresentation.NoDataLabel;
            var state = isRefreshing ? TrayIconState.Refreshing : TrayIconState.NoData;
            var tooltip = statusProviderName is null
                ? text.ConnectFirst
                : text.WaitingForUsage(statusProviderName);
            return new TrayPresentation(state, label, null, Tooltip(text, tooltip));
        }

        var usage = displayUsages.TryGetValue(summary.ProviderName, out var found) ? found : null;
        var isStale = usage?.IsStale == true;
        var remaining = summary.RemainingPercent;

        var iconState = isStale
            ? TrayIconState.Stale
            : alertPolicy.Level(remaining) switch
            {
                UsageAlertLevel.Critical => TrayIconState.Critical,
                UsageAlertLevel.Warning => TrayIconState.Warning,
                _ => TrayIconState.Normal
            };

        var lines = new List<string>(3)
        {
            text.AppName,
            isStale
                ? text.StaleTooltip(summary.ProviderName, remaining)
                : text.RemainingTooltip(summary.ProviderName, remaining)
        };

        if (showResetCountdown && summary.ResetsAt is DateTimeOffset resetsAt)
        {
            var windowLabel = text.UsageWindowLabel(
                new UsageWindow(summary.WindowKind, 100 - remaining, resetsAt, null),
                position: 0);
            lines.Add(text.WindowResetsIn(windowLabel, text.RelativeReset(resetsAt, now)));
        }

        return new TrayPresentation(
            iconState,
            remaining.ToString(System.Globalization.CultureInfo.InvariantCulture),
            remaining,
            Tooltip(text, string.Join(Environment.NewLine, lines)));
    }

    private static string Tooltip(Localizer text, string body)
    {
        var full = body.StartsWith(text.AppName, StringComparison.Ordinal)
            ? body
            : text.AppName + Environment.NewLine + body;

        return full.Length <= MaximumTooltipLength
            ? full
            : full[..MaximumTooltipLength];
    }
}
