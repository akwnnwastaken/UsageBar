using System.Text.Json.Serialization;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;

namespace UsageBar.Windows.Core.Settings;

/// <summary>
/// The persisted settings document. This is a pure model: reading and writing
/// the file lives in the Infrastructure project.
///
/// Every field is nullable so a truncated or partially written file still loads
/// — <see cref="UsageBarSettingsSanitizer.Sanitize"/> fills in the defaults.
/// Nothing here identifies the user: no paths, no tokens, no account data.
/// </summary>
public sealed class UsageBarSettings
{
    public const int CurrentSchemaVersion = 1;

    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; } = CurrentSchemaVersion;

    [JsonPropertyName("codexConnected")]
    public bool CodexConnected { get; set; }

    [JsonPropertyName("claudeConnected")]
    public bool ClaudeConnected { get; set; }

    [JsonPropertyName("selectedProvider")]
    public string? SelectedProvider { get; set; }

    [JsonPropertyName("autoRotateProviders")]
    public bool AutoRotateProviders { get; set; }

    /// <summary>Null means "follow the Windows UI culture".</summary>
    [JsonPropertyName("language")]
    public string? Language { get; set; }

    [JsonPropertyName("refreshInterval")]
    public string? RefreshInterval { get; set; }

    [JsonPropertyName("usageColorsEnabled")]
    public bool? UsageColorsEnabled { get; set; }

    [JsonPropertyName("usageAlertPreset")]
    public string? UsageAlertPreset { get; set; }

    [JsonPropertyName("showResetCountdown")]
    public bool? ShowResetCountdown { get; set; }

    [JsonPropertyName("usageHistoryEnabled")]
    public bool? UsageHistoryEnabled { get; set; }

    [JsonPropertyName("trayGuidanceVersionShown")]
    public int? TrayGuidanceVersionShown { get; set; }

    /// <summary>
    /// Optional user-selected provider executable. Stored because the user chose
    /// it explicitly; it is never included in diagnostics.
    /// </summary>
    [JsonPropertyName("codexExecutablePath")]
    public string? CodexExecutablePath { get; set; }

    [JsonPropertyName("claudeExecutablePath")]
    public string? ClaudeExecutablePath { get; set; }

    /// <summary>Which Claude installation form to use: automatic, native or WSL.</summary>
    [JsonPropertyName("claudeAdapterMode")]
    public string? ClaudeAdapterMode { get; set; }

    /// <summary>
    /// The WSL distribution to run Claude in. Null means "choose automatically".
    /// Only the distribution name is stored — never a path inside it.
    /// </summary>
    [JsonPropertyName("claudeWslDistribution")]
    public string? ClaudeWslDistribution { get; set; }

    /// <summary>
    /// The adapter kind that last worked, so discovery can start with it instead
    /// of probing everything again. A safe token such as "native_exe" or "wsl".
    /// </summary>
    [JsonPropertyName("claudeLastAdapterKind")]
    public string? ClaudeLastAdapterKind { get; set; }

    public UsageBarSettings Clone() => (UsageBarSettings)MemberwiseClone();
}

/// <summary>
/// Resolves raw settings into typed values, applying the macOS defaults:
/// colors on, history on, reset countdown off, five-minute refresh, balanced
/// thresholds.
/// </summary>
public static class UsageBarSettingsSanitizer
{
    public static UsageBarSettings Sanitize(UsageBarSettings? settings)
    {
        var value = settings?.Clone() ?? new UsageBarSettings();
        value.SchemaVersion = UsageBarSettings.CurrentSchemaVersion;

        value.UsageColorsEnabled ??= true;
        value.UsageHistoryEnabled ??= true;
        value.ShowResetCountdown ??= false;
        value.RefreshInterval = UsageRefreshIntervals
            .Resolved(value.RefreshInterval)
            .StorageValue();
        value.UsageAlertPreset = ResolvePreset(value.UsageAlertPreset).ToStorageValue();
        value.ClaudeAdapterMode = ClaudeAdapterModes
            .Resolved(value.ClaudeAdapterMode)
            .StorageValue();

        // A distribution name is a short identifier. Anything longer, or
        // containing a separator, is not one and is dropped rather than stored.
        if (value.ClaudeWslDistribution is { } distribution &&
            (distribution.Length is 0 or > 64 ||
             distribution.IndexOfAny(new[] { '/', '\\', '\0', '\n', '\r' }) >= 0))
        {
            value.ClaudeWslDistribution = null;
        }

        if (value.ClaudeLastAdapterKind is { } adapter &&
            !Diagnostics.DiagnosticsSanitizer.IsSafeToken(adapter))
        {
            value.ClaudeLastAdapterKind = null;
        }

        if (value.SelectedProvider is not null &&
            !Providers.ProviderNames.All.Contains(value.SelectedProvider))
        {
            value.SelectedProvider = null;
        }

        if (value.Language is not null && AppLanguages.Resolve(value.Language) is null)
        {
            value.Language = null;
        }

        if (value.TrayGuidanceVersionShown is int shown && shown < 0)
        {
            value.TrayGuidanceVersionShown = null;
        }

        return value;
    }

    public static UsageAlertPreset ResolvePreset(string? storedValue) => storedValue switch
    {
        "late" => UsageAlertPreset.Late,
        "early" => UsageAlertPreset.Early,
        _ => UsageAlertPreset.Balanced
    };

    public static string ToStorageValue(this UsageAlertPreset preset) => preset switch
    {
        UsageAlertPreset.Late => "late",
        UsageAlertPreset.Early => "early",
        _ => "balanced"
    };

    /// <summary>The connected providers, in a stable order.</summary>
    public static IReadOnlyList<string> ConnectedProviderNames(this UsageBarSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        var names = new List<string>(2);
        if (settings.CodexConnected)
        {
            names.Add(Providers.ProviderNames.Codex);
        }

        if (settings.ClaudeConnected)
        {
            names.Add(Providers.ProviderNames.ClaudeCode);
        }

        return names;
    }

    /// <summary>
    /// The provider whose value the tray icon shows: the rotating one in auto
    /// mode, otherwise the fixed selection, falling back to whatever is
    /// connected.
    /// </summary>
    public static string? StatusProviderName(
        this UsageBarSettings settings,
        int rotatingProviderIndex)
    {
        var providers = settings.ConnectedProviderNames();
        if (providers.Count == 0)
        {
            return null;
        }

        if (settings.AutoRotateProviders && providers.Count > 1)
        {
            return providers[Math.Abs(rotatingProviderIndex) % providers.Count];
        }

        if (settings.SelectedProvider is { } selected && providers.Contains(selected))
        {
            return selected;
        }

        return providers[0];
    }
}
