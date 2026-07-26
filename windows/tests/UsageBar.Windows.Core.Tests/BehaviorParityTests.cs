using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Parsing;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Core.Settings;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// The behavior rules the Windows port must keep identical to macOS.
/// </summary>
public sealed class BehaviorParityTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    [Fact]
    public void DisplayedValueIsRemainingNotUsed()
    {
        var window = new UsageWindow(UsageWindowKind.FiveHour, 35, null, 300);
        Assert.Equal(65, window.RemainingPercent);
        Assert.Equal(35, window.UsedPercent);
    }

    [Fact]
    public void CodexShowsTheLowestRemainingWindow()
    {
        var usage = new ProviderUsage(ProviderNames.Codex, new[]
        {
            new UsageWindow(UsageWindowKind.FiveHour, 20, null, 300),
            new UsageWindow(UsageWindowKind.Weekly, 74, null, 10_080)
        }, error: null);

        var summary = UsageSummaryCalculator.Summary(
            ProviderNames.Codex,
            new Dictionary<string, ProviderUsage> { [ProviderNames.Codex] = usage });

        Assert.Equal(26, summary?.RemainingPercent);
    }

    [Fact]
    public void EveryReturnedWindowStaysVisible()
    {
        var usage = CodexResponseParser.ParseStream(
            Fixtures.ReadBytes("codex/additional-duration-window.jsonl"));

        Assert.Equal(2, usage!.Windows.Count);
    }

    [Fact]
    public void AutoModeRotatesEveryThirtySeconds()
    {
        Assert.Equal(TimeSpan.FromSeconds(30), ProviderRotation.Interval);
        Assert.Equal(1, ProviderRotation.NextIndex(0, 2));
        Assert.Equal(0, ProviderRotation.NextIndex(1, 2));
        Assert.Equal(0, ProviderRotation.NextIndex(8, 0));
    }

    [Fact]
    public void RefreshOptionsAreOneTwoAndFiveMinutesDefaultingToFive()
    {
        Assert.Equal(new[] { 1, 2, 5 }, UsageRefreshIntervals.All.Select(interval => interval.Minutes()));
        Assert.Equal(UsageRefreshInterval.FiveMinutes, UsageRefreshIntervals.Resolved(null));
        Assert.Equal(UsageRefreshInterval.FiveMinutes, UsageRefreshIntervals.Resolved(""));
        Assert.Equal(UsageRefreshInterval.FiveMinutes, UsageRefreshIntervals.Resolved("threeMinutes"));
        Assert.Equal(UsageRefreshInterval.TwoMinutes, UsageRefreshIntervals.Resolved("twoMinutes"));
        Assert.Equal(TimeSpan.FromMinutes(1), UsageRefreshInterval.OneMinute.Duration());
    }

    [Fact]
    public void PanelOpenRefreshUsesTheThirtySecondThreshold()
    {
        Assert.Equal(TimeSpan.FromSeconds(30), UsageRefreshPolicy.PanelOpenStalenessThreshold);
        Assert.False(UsageRefreshPolicy.ShouldRefreshOnPanelOpen(null, Now));
        Assert.False(UsageRefreshPolicy.ShouldRefreshOnPanelOpen(Now.AddSeconds(-30), Now));
        Assert.True(UsageRefreshPolicy.ShouldRefreshOnPanelOpen(Now.AddSeconds(-31), Now));
    }

    [Fact]
    public void ThresholdPresetsMatchMacOs()
    {
        var balanced = new UsageAlertPolicy(true, UsageAlertPreset.Balanced);
        Assert.Equal(UsageAlertLevel.Normal, balanced.Level(21));
        Assert.Equal(UsageAlertLevel.Warning, balanced.Level(20));
        Assert.Equal(UsageAlertLevel.Warning, balanced.Level(11));
        Assert.Equal(UsageAlertLevel.Critical, balanced.Level(10));
        Assert.Equal(UsageAlertLevel.Critical, balanced.Level(-1));
        Assert.Equal(UsageAlertLevel.Normal, new UsageAlertPolicy(false, UsageAlertPreset.Early).Level(0));

        Assert.Equal(10, UsageAlertPreset.Late.WarningThreshold());
        Assert.Equal(5, UsageAlertPreset.Late.CriticalThreshold());
        Assert.Equal(30, UsageAlertPreset.Early.WarningThreshold());
        Assert.Equal(15, UsageAlertPreset.Early.CriticalThreshold());
    }

    [Fact]
    public void ProviderFailurePreservesThePreviousValueAsStaleData()
    {
        var good = new ProviderUsage(
            ProviderNames.Codex,
            new[] { new UsageWindow(UsageWindowKind.FiveHour, 35, null, 300) },
            error: null);
        var accepted = ProviderUsageTransition.Accept(null, good, Now);
        Assert.Equal(Now, accepted.LastSuccessfulAt);
        Assert.False(accepted.IsStale);

        var failure = ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexTimedOut);
        var stale = ProviderUsageTransition.Accept(accepted, failure, Now.AddMinutes(5));
        Assert.True(stale.IsStale);
        Assert.Equal(Now, stale.LastSuccessfulAt);
        Assert.Equal(65, stale.Windows[0].RemainingPercent);
        Assert.Equal("codex_timed_out", stale.Error?.DiagnosticCode);

        // Without a previous good reading there is nothing to keep.
        var firstFailure = ProviderUsageTransition.Accept(null, failure, Now);
        Assert.False(firstFailure.IsStale);
        Assert.Empty(firstFailure.Windows);
    }

    [Fact]
    public void DisconnectKeepsAValidSelectionOtherwiseFallsBack()
    {
        Assert.Equal(
            ProviderNames.ClaudeCode,
            ProviderConnectionTransition.Selection(
                ProviderNames.Codex,
                new[] { ProviderNames.ClaudeCode },
                ProviderNames.ClaudeCode));
        Assert.Equal(
            ProviderNames.Codex,
            ProviderConnectionTransition.Selection(
                ProviderNames.ClaudeCode,
                new[] { ProviderNames.Codex },
                ProviderNames.ClaudeCode));
        Assert.Null(
            ProviderConnectionTransition.Selection(
                ProviderNames.Codex,
                Array.Empty<string>(),
                ProviderNames.Codex));

        Assert.False(ProviderConnectionTransition.AutoRotateStaysEnabled(1, true));
        Assert.True(ProviderConnectionTransition.AutoRotateStaysEnabled(2, true));
        Assert.False(ProviderConnectionTransition.AutoRotateStaysEnabled(2, false));
    }

    /// <summary>
    /// The filter smooths what is shown; the raw reading is what gets recorded.
    /// </summary>
    [Fact]
    public void DisplayStateSmoothsPresentationWithoutTouchingRawWindows()
    {
        var state = new UsageDisplayState();
        var first = Usages(remaining: 33);
        state.Advance(first);
        Assert.Equal(33, state.Apply(first)[ProviderNames.Codex].Windows[0].RemainingPercent);

        var rebound = Usages(remaining: 38);
        state.Advance(rebound);
        Assert.Equal(33, state.Apply(rebound)[ProviderNames.Codex].Windows[0].RemainingPercent);
        // The raw reading is untouched, so history still records 38.
        Assert.Equal(38, rebound[ProviderNames.Codex].Windows[0].RemainingPercent);
    }

    [Fact]
    public void DisplayStateForgetsADisconnectedProvider()
    {
        var state = new UsageDisplayState();
        state.Advance(Usages(remaining: 33));
        state.Forget(ProviderNames.Codex);

        var rebound = Usages(remaining: 38);
        state.Advance(rebound);
        Assert.Equal(38, state.Apply(rebound)[ProviderNames.Codex].Windows[0].RemainingPercent);
    }

    [Fact]
    public void StatusProviderFollowsRotationOrSelection()
    {
        var settings = new UsageBarSettings
        {
            CodexConnected = true,
            ClaudeConnected = true,
            AutoRotateProviders = true
        };

        Assert.Equal(ProviderNames.Codex, settings.StatusProviderName(0));
        Assert.Equal(ProviderNames.ClaudeCode, settings.StatusProviderName(1));

        settings.AutoRotateProviders = false;
        settings.SelectedProvider = ProviderNames.ClaudeCode;
        Assert.Equal(ProviderNames.ClaudeCode, settings.StatusProviderName(0));

        settings.ClaudeConnected = false;
        Assert.Equal(ProviderNames.Codex, settings.StatusProviderName(0));

        settings.CodexConnected = false;
        Assert.Null(settings.StatusProviderName(0));
    }

    [Fact]
    public void SettingsSanitizerAppliesMacOsDefaultsAndRejectsUnknownValues()
    {
        var sanitized = UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            RefreshInterval = "sevenMinutes",
            UsageAlertPreset = "nonsense",
            SelectedProvider = "Gemini",
            Language = "klingon",
            TrayGuidanceVersionShown = -3
        });

        Assert.True(sanitized.UsageColorsEnabled);
        Assert.True(sanitized.UsageHistoryEnabled);
        Assert.False(sanitized.ShowResetCountdown);
        Assert.Equal("fiveMinutes", sanitized.RefreshInterval);
        Assert.Equal("balanced", sanitized.UsageAlertPreset);
        Assert.Null(sanitized.SelectedProvider);
        Assert.Null(sanitized.Language);
        Assert.Null(sanitized.TrayGuidanceVersionShown);
        Assert.Equal(UsageBarSettings.CurrentSchemaVersion, sanitized.SchemaVersion);
    }

    [Fact]
    public void SettingsSanitizerAcceptsNullWithoutThrowing()
    {
        var sanitized = UsageBarSettingsSanitizer.Sanitize(null);

        Assert.False(sanitized.CodexConnected);
        Assert.False(sanitized.ClaudeConnected);
        Assert.Equal("fiveMinutes", sanitized.RefreshInterval);
    }

    [Fact]
    public void LanguageFollowsTheUiCultureUnlessExplicitlyChosen()
    {
        Assert.Equal(AppLanguage.Turkish, AppLanguages.Preferred(new[] { "tr-TR", "en-US" }));
        Assert.Equal(AppLanguage.English, AppLanguages.Preferred(new[] { "en-US", "tr-TR" }));
        Assert.Equal(AppLanguage.English, AppLanguages.Preferred(Array.Empty<string>()));
        Assert.Equal(AppLanguage.English, AppLanguages.Preferred(null));

        Assert.Equal(AppLanguage.English, AppLanguages.Effective("english", new[] { "tr-TR" }));
        Assert.Equal(AppLanguage.Turkish, AppLanguages.Effective(null, new[] { "tr-TR" }));
        Assert.Equal(AppLanguage.Turkish, AppLanguages.Effective("unknown", new[] { "tr" }));
    }

    private static Dictionary<string, ProviderUsage> Usages(int remaining) =>
        new(StringComparer.Ordinal)
        {
            [ProviderNames.Codex] = new(
                ProviderNames.Codex,
                new[] { new UsageWindow(UsageWindowKind.FiveHour, 100 - remaining, null, 300) },
                error: null)
        };
}
