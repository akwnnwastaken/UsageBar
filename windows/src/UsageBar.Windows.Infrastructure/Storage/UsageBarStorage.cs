using System.Runtime.Versioning;
using System.Text.Json.Serialization;
using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Settings;

namespace UsageBar.Windows.Infrastructure.Storage;

/// <summary>
/// Where UsageBar keeps its own data: <c>%LOCALAPPDATA%\UsageBar\</c>.
///
/// Only settings and the local usage history live here. No provider output, no
/// tokens, no credentials, no project paths — nothing that could identify what
/// the user was working on.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class UsageBarStorage
{
    public UsageBarStorage(string? rootDirectory = null)
    {
        RootDirectory = rootDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "UsageBar");
        SettingsPath = Path.Combine(RootDirectory, "settings.json");
        HistoryPath = Path.Combine(RootDirectory, "history.json");
    }

    public string RootDirectory { get; }

    public string SettingsPath { get; }

    public string HistoryPath { get; }

    /// <summary>
    /// Loads settings, applying every default. A missing, truncated or
    /// malformed file yields the defaults instead of an error.
    /// </summary>
    public UsageBarSettings LoadSettings() =>
        UsageBarSettingsSanitizer.Sanitize(AtomicJsonFile.Read<UsageBarSettings>(SettingsPath));

    public bool SaveSettings(UsageBarSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return AtomicJsonFile.Write(SettingsPath, UsageBarSettingsSanitizer.Sanitize(settings));
    }

    /// <summary>
    /// Loads history and immediately enforces every retention limit: maximum
    /// age, maximum samples per series and maximum number of series.
    /// </summary>
    public IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> LoadHistory(DateTimeOffset now)
    {
        var document = AtomicJsonFile.Read<UsageHistoryDocument>(HistoryPath);
        if (document?.Series is null)
        {
            return new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal);
        }

        var series = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal);
        foreach (var (key, samples) in document.Series)
        {
            if (samples is not null)
            {
                series[key] = samples.Where(sample => sample is not null).ToList();
            }
        }

        return UsageHistoryModel.Sanitized(series, now);
    }

    public bool SaveHistory(
        IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> history,
        DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(history);

        var sanitized = UsageHistoryModel.Sanitized(history, now);
        return AtomicJsonFile.Write(HistoryPath, new UsageHistoryDocument
        {
            SchemaVersion = UsageHistoryDocument.CurrentSchemaVersion,
            Series = sanitized.ToDictionary(
                entry => entry.Key,
                entry => (List<UsageHistorySample>?)entry.Value.ToList(),
                StringComparer.Ordinal)
        });
    }

    public bool ClearHistory()
    {
        try
        {
            File.Delete(HistoryPath);
            return true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}

/// <summary>Versioned on-disk shape of the history file.</summary>
public sealed class UsageHistoryDocument
{
    public const int CurrentSchemaVersion = 1;

    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; } = CurrentSchemaVersion;

    [JsonPropertyName("series")]
    public Dictionary<string, List<UsageHistorySample>?>? Series { get; set; }
}
