namespace UsageBar.Windows.Core.Policies;

public enum UsageAlertLevel
{
    Normal,
    Warning,
    Critical
}

public enum UsageAlertPreset
{
    Late,
    Balanced,
    Early
}

public static class UsageAlertPresetThresholds
{
    public static int WarningThreshold(this UsageAlertPreset preset) => preset switch
    {
        UsageAlertPreset.Late => 10,
        UsageAlertPreset.Balanced => 20,
        UsageAlertPreset.Early => 30,
        _ => 20
    };

    public static int CriticalThreshold(this UsageAlertPreset preset) => preset switch
    {
        UsageAlertPreset.Late => 5,
        UsageAlertPreset.Balanced => 10,
        UsageAlertPreset.Early => 15,
        _ => 10
    };
}

/// <summary>
/// Maps a remaining percentage to normal/warning/critical. Disabled colors
/// report everything as normal, exactly like macOS.
/// </summary>
public sealed record UsageAlertPolicy(bool IsEnabled, UsageAlertPreset Preset)
{
    public UsageAlertLevel Level(int remainingPercent)
    {
        if (!IsEnabled)
        {
            return UsageAlertLevel.Normal;
        }

        var clamped = Math.Clamp(remainingPercent, 0, 100);
        if (clamped <= Preset.CriticalThreshold())
        {
            return UsageAlertLevel.Critical;
        }

        return clamped <= Preset.WarningThreshold()
            ? UsageAlertLevel.Warning
            : UsageAlertLevel.Normal;
    }
}
