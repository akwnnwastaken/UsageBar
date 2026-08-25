using System.Runtime.Versioning;
using System.Text;
using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Core.Settings;
using UsageBar.Windows.Infrastructure.Storage;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// Settings and history persistence: versioned, written atomically, and never
/// able to stop UsageBar from starting.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class StorageTests : IDisposable
{
    /// <summary>
    /// The one clock these tests run on. Storage takes <c>now</c> as an
    /// argument, so nothing here needs the real one — and a fixed UTC instant
    /// keeps the serialized timestamps identical across time zones, daylight
    /// saving and repeated runs.
    /// </summary>
    private static readonly DateTimeOffset TestNow = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private readonly string _root = Path.Combine(
        Path.GetTempPath(),
        "usagebar-storage-" + Guid.NewGuid().ToString("N"));

    private readonly UsageBarStorage _storage;

    public StorageTests()
    {
        Directory.CreateDirectory(_root);
        _storage = new UsageBarStorage(_root);
    }

    public void Dispose()
    {
        try
        {
            Directory.Delete(_root, recursive: true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
        }
    }

    [Fact]
    public void SettingsRoundTripThroughDisk()
    {
        var saved = _storage.SaveSettings(new UsageBarSettings
        {
            CodexConnected = true,
            Language = "turkish",
            RefreshInterval = "oneMinute",
            UsageColorsEnabled = false,
            TrayGuidanceVersionShown = 1
        });

        Assert.True(saved);

        var loaded = _storage.LoadSettings();
        Assert.True(loaded.CodexConnected);
        Assert.Equal("turkish", loaded.Language);
        Assert.Equal("oneMinute", loaded.RefreshInterval);
        Assert.False(loaded.UsageColorsEnabled);
        Assert.Equal(1, loaded.TrayGuidanceVersionShown);
        Assert.Equal(UsageBarSettings.CurrentSchemaVersion, loaded.SchemaVersion);
    }

    [Fact]
    public void MissingSettingsYieldTheDefaults()
    {
        var loaded = _storage.LoadSettings();

        Assert.False(loaded.CodexConnected);
        Assert.True(loaded.UsageColorsEnabled);
        Assert.True(loaded.UsageHistoryEnabled);
        Assert.Equal("fiveMinutes", loaded.RefreshInterval);
    }

    [Theory]
    [InlineData("")]
    [InlineData("{")]
    [InlineData("{\"codexConnected\":tru")]
    [InlineData("not json at all")]
    [InlineData("[1,2,3]")]
    [InlineData("null")]
    public void MalformedSettingsNeverThrowAndFallBackToDefaults(string content)
    {
        File.WriteAllText(_storage.SettingsPath, content);

        var loaded = _storage.LoadSettings();

        Assert.False(loaded.CodexConnected);
        Assert.Equal("fiveMinutes", loaded.RefreshInterval);
    }

    [Fact]
    public void AnOversizedSettingsFileIsIgnored()
    {
        File.WriteAllBytes(_storage.SettingsPath, new byte[AtomicJsonFile.MaximumBytes + 1]);

        Assert.False(_storage.LoadSettings().CodexConnected);
    }

    [Fact]
    public void UnknownSettingsFieldsDoNotBreakLoading()
    {
        File.WriteAllText(
            _storage.SettingsPath,
            """{"codexConnected":true,"somethingFromAFutureBuild":{"nested":42}}""");

        Assert.True(_storage.LoadSettings().CodexConnected);
    }

    [Fact]
    public void ASettingsFileWithoutCollectionStateLoadsAsCollecting()
    {
        // What every installation written before collection could be paused
        // looks like on disk. Loading it must not pause anybody.
        File.WriteAllText(
            _storage.SettingsPath,
            """{"schemaVersion":1,"codexConnected":true,"claudeConnected":true}""");

        var loaded = _storage.LoadSettings();

        Assert.True(loaded.CodexCollectionEnabled);
        Assert.True(loaded.ClaudeCollectionEnabled);
    }

    [Fact]
    public void APausedProviderStaysPausedAcrossASaveAndLoad()
    {
        _storage.SaveSettings(new UsageBarSettings
        {
            CodexConnected = true,
            ClaudeConnected = true,
            CodexCollectionEnabled = false,
            ClaudeCollectionEnabled = true
        });

        var loaded = _storage.LoadSettings();

        Assert.False(loaded.CodexCollectionEnabled);
        Assert.True(loaded.ClaudeCollectionEnabled);
        // The pause is a collection decision only — both providers stay
        // connected.
        Assert.True(loaded.CodexConnected);
        Assert.True(loaded.ClaudeConnected);
    }

    [Fact]
    public void WritingLeavesNoTemporaryFileBehind()
    {
        _storage.SaveSettings(new UsageBarSettings { CodexConnected = true });

        Assert.True(File.Exists(_storage.SettingsPath));
        Assert.False(File.Exists(_storage.SettingsPath + ".tmp"));
    }

    [Fact]
    public void AnInterruptedWriteLeavesThePreviousSettingsIntact()
    {
        _storage.SaveSettings(new UsageBarSettings { CodexConnected = true });

        // A stale temporary file from a crashed write must not be picked up.
        File.WriteAllText(_storage.SettingsPath + ".tmp", "{ truncated");

        Assert.True(_storage.LoadSettings().CodexConnected);
    }

    [Fact]
    public void HistoryRoundTripsAndIsSanitizedOnLoad()
    {
        var history = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
        {
            [UsageHistoryModel.SeriesKey(ProviderNames.Codex, UsageWindowKind.FiveHour)] = new[]
            {
                new UsageHistorySample(TestNow.AddMinutes(-10), 90),
                new UsageHistorySample(TestNow.AddMinutes(-5), 80)
            },
            // Older than the retention window: must not come back.
            ["Codex|weekly"] = new[]
            {
                new UsageHistorySample(TestNow.AddHours(-30), 50)
            }
        };

        Assert.True(_storage.SaveHistory(history, TestNow));

        var loaded = _storage.LoadHistory(TestNow);
        Assert.Equal(
            new[] { 90, 80 },
            loaded["Codex|five-hour"].Select(sample => sample.RemainingPercent));
        Assert.False(loaded.ContainsKey("Codex|weekly"));
    }

    [Fact]
    public void MalformedHistoryYieldsAnEmptyHistory()
    {
        File.WriteAllText(_storage.HistoryPath, "{\"schemaVersion\":1,\"series\":{\"Codex|weekly\":[{\"reco");

        Assert.Empty(_storage.LoadHistory(TestNow));
    }

    [Fact]
    public void ClearingHistoryRemovesTheFile()
    {
        _storage.SaveHistory(
            new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
            {
                ["Codex|weekly"] = new[] { new UsageHistorySample(TestNow, 50) }
            },
            TestNow);

        Assert.True(File.Exists(_storage.HistoryPath));
        Assert.True(_storage.ClearHistory());
        Assert.False(File.Exists(_storage.HistoryPath));
        Assert.Empty(_storage.LoadHistory(TestNow));
    }

    /// <summary>
    /// Nothing that could identify the user's work may reach the settings or
    /// history files.
    /// </summary>
    [Fact]
    public void PersistedFilesContainNoProviderOutputOrCredentials()
    {
        _storage.SaveSettings(new UsageBarSettings { CodexConnected = true, ClaudeConnected = true });
        _storage.SaveHistory(
            new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
            {
                ["Codex|five-hour"] = new[] { new UsageHistorySample(TestNow, 65) }
            },
            TestNow);

        var written = File.ReadAllText(_storage.SettingsPath, Encoding.UTF8) +
                      File.ReadAllText(_storage.HistoryPath, Encoding.UTF8);

        foreach (var forbidden in new[]
                 {
                     "sk-", "Bearer", "token", "password", "rateLimits",
                     "Current session", "usedPercent", "app-server"
                 })
        {
            Assert.DoesNotContain(forbidden, written, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void StorageLivesUnderTheApplicationsOwnFolder()
    {
        var defaultStorage = new UsageBarStorage();

        Assert.Contains("UsageBar", defaultStorage.RootDirectory, StringComparison.OrdinalIgnoreCase);
        Assert.EndsWith("settings.json", defaultStorage.SettingsPath, StringComparison.Ordinal);
        Assert.EndsWith("history.json", defaultStorage.HistoryPath, StringComparison.Ordinal);
    }
}
