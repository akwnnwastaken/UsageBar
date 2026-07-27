namespace UsageBar.Windows.Core.Policies;

public enum UsageRefreshInterval
{
    OneMinute,
    TwoMinutes,
    FiveMinutes
}

public static class UsageRefreshIntervals
{
    public const UsageRefreshInterval Fallback = UsageRefreshInterval.FiveMinutes;

    public static IReadOnlyList<UsageRefreshInterval> All { get; } = new[]
    {
        UsageRefreshInterval.OneMinute,
        UsageRefreshInterval.TwoMinutes,
        UsageRefreshInterval.FiveMinutes
    };

    public static int Minutes(this UsageRefreshInterval interval) => interval switch
    {
        UsageRefreshInterval.OneMinute => 1,
        UsageRefreshInterval.TwoMinutes => 2,
        _ => 5
    };

    public static TimeSpan Duration(this UsageRefreshInterval interval) =>
        TimeSpan.FromMinutes(interval.Minutes());

    /// <summary>Stored preference value; unknown or missing falls back to 5 minutes.</summary>
    public static string StorageValue(this UsageRefreshInterval interval) => interval switch
    {
        UsageRefreshInterval.OneMinute => "oneMinute",
        UsageRefreshInterval.TwoMinutes => "twoMinutes",
        _ => "fiveMinutes"
    };

    public static UsageRefreshInterval Resolved(string? storedValue) => storedValue switch
    {
        "oneMinute" => UsageRefreshInterval.OneMinute,
        "twoMinutes" => UsageRefreshInterval.TwoMinutes,
        "fiveMinutes" => UsageRefreshInterval.FiveMinutes,
        _ => Fallback
    };
}

/// <summary>
/// On macOS this governs opening the menu; on Windows it governs opening the
/// tray popup. Same threshold, same rule.
/// </summary>
public static class UsageRefreshPolicy
{
    public static TimeSpan PanelOpenStalenessThreshold { get; } = TimeSpan.FromSeconds(30);

    public static bool ShouldRefreshOnPanelOpen(DateTimeOffset? lastUpdated, DateTimeOffset now)
    {
        if (lastUpdated is not DateTimeOffset updated)
        {
            return false;
        }

        return now - updated > PanelOpenStalenessThreshold;
    }
}

/// <summary>Auto mode rotates the tray provider every 30 seconds.</summary>
public static class ProviderRotation
{
    public static TimeSpan Interval { get; } = TimeSpan.FromSeconds(30);

    public static int NextIndex(int currentIndex, int providerCount)
    {
        if (providerCount <= 0)
        {
            return 0;
        }

        return (Math.Max(0, currentIndex) + 1) % providerCount;
    }
}

/// <summary>
/// Pure state transition for disconnecting a provider, so the selection and
/// auto-rotate rules are testable without any UI.
/// </summary>
public static class ProviderConnectionTransition
{
    public static string? Selection(
        string disconnected,
        IReadOnlyList<string> remaining,
        string? previousSelection)
    {
        ArgumentNullException.ThrowIfNull(remaining);

        if (previousSelection is not null &&
            previousSelection != disconnected &&
            remaining.Contains(previousSelection))
        {
            return previousSelection;
        }

        return remaining.Count > 0 ? remaining[0] : null;
    }

    public static bool AutoRotateStaysEnabled(int remainingCount, bool wasEnabled) =>
        wasEnabled && remainingCount > 1;
}
