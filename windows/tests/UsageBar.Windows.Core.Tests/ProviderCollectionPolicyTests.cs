using System.Text.Json;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Settings;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// Collection eligibility and the settings it reads. The eligibility rule is
/// the same one macOS applies, and the stored form defaults to enabled so an
/// upgrade from a build without these fields never pauses a provider.
/// </summary>
public sealed class ProviderCollectionPolicyTests
{
    [Theory]
    [InlineData(false, false, false)]
    [InlineData(false, true, false)]
    [InlineData(true, false, false)]
    [InlineData(true, true, true)]
    public void OnlyAConnectedAndCollectionEnabledProviderIsEligible(
        bool connected,
        bool collectionEnabled,
        bool expected)
    {
        Assert.Equal(expected, ProviderCollectionPolicy.IsEligible(connected, collectionEnabled));
    }

    [Fact]
    public void MissingCollectionSettingsDefaultToEnabled()
    {
        var sanitized = UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings());

        Assert.True(sanitized.CodexCollectionEnabled);
        Assert.True(sanitized.ClaudeCollectionEnabled);
    }

    [Fact]
    public void SanitizingNeverOverwritesAStoredPause()
    {
        var sanitized = UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            CodexCollectionEnabled = false,
            ClaudeCollectionEnabled = false
        });

        Assert.False(sanitized.CodexCollectionEnabled);
        Assert.False(sanitized.ClaudeCollectionEnabled);
    }

    [Fact]
    public void SanitizingKeepsAnExplicitlyEnabledProviderEnabled()
    {
        var sanitized = UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            CodexCollectionEnabled = true,
            ClaudeCollectionEnabled = true
        });

        Assert.True(sanitized.CodexCollectionEnabled);
        Assert.True(sanitized.ClaudeCollectionEnabled);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void CollectionStateSurvivesAClone(bool collectionEnabled)
    {
        var clone = new UsageBarSettings
        {
            CodexCollectionEnabled = collectionEnabled,
            ClaudeCollectionEnabled = collectionEnabled
        }.Clone();

        Assert.Equal(collectionEnabled, clone.CodexCollectionEnabled);
        Assert.Equal(collectionEnabled, clone.ClaudeCollectionEnabled);
    }

    [Fact]
    public void TheStoredFieldNamesAreTheOnesTheDocumentUses()
    {
        var json = JsonSerializer.Serialize(new UsageBarSettings
        {
            CodexCollectionEnabled = false,
            ClaudeCollectionEnabled = true
        });

        Assert.Contains("\"codexCollectionEnabled\":false", json, StringComparison.Ordinal);
        Assert.Contains("\"claudeCollectionEnabled\":true", json, StringComparison.Ordinal);
    }

    [Fact]
    public void ADocumentWrittenBeforeCollectionCouldBePausedLoadsAsEnabled()
    {
        var settings = JsonSerializer.Deserialize<UsageBarSettings>(
            """{"schemaVersion":1,"codexConnected":true,"claudeConnected":true}""");

        Assert.NotNull(settings);
        Assert.Null(settings!.CodexCollectionEnabled);
        Assert.Null(settings.ClaudeCollectionEnabled);

        var sanitized = UsageBarSettingsSanitizer.Sanitize(settings);
        Assert.True(sanitized.CodexCollectionEnabled);
        Assert.True(sanitized.ClaudeCollectionEnabled);
    }

    [Theory]
    [InlineData("false", false)]
    [InlineData("true", true)]
    public void AStoredCollectionStateIsReadBackUnchanged(string storedValue, bool expected)
    {
        var settings = JsonSerializer.Deserialize<UsageBarSettings>(
            $$"""{"codexCollectionEnabled":{{storedValue}},"claudeCollectionEnabled":{{storedValue}}}""");

        Assert.NotNull(settings);

        var sanitized = UsageBarSettingsSanitizer.Sanitize(settings);
        Assert.Equal(expected, sanitized.CodexCollectionEnabled);
        Assert.Equal(expected, sanitized.ClaudeCollectionEnabled);
    }
}
