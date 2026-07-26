using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

public sealed class LocalizationAndTrayPresentationTests
{
    private static readonly Localizer Turkish = new(AppLanguage.Turkish);
    private static readonly Localizer English = new(AppLanguage.English);
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_000_000);

    [Fact]
    public void RemainingStringsMatchMacOs()
    {
        Assert.Equal("%59 kaldı", Turkish.Remaining(59));
        Assert.Equal("59% remaining", English.Remaining(59));
        Assert.Equal("Codex: 59% remaining", English.RemainingTooltip("Codex", 59));
        Assert.Equal("Codex: %59 kaldı (eski veri)", Turkish.StaleTooltip("Codex", 59));
    }

    [Fact]
    public void ResetDurationsKeepEveryComponent()
    {
        Assert.Equal("1h 15m", English.RelativeReset(Now.AddMinutes(75), Now));
        Assert.Equal("6d 21h", English.RelativeReset(Now.AddDays(6).AddHours(21), Now));
        Assert.Equal("6g 21sa", Turkish.RelativeReset(Now.AddDays(6).AddHours(21), Now));
        Assert.Equal("1sa 15dk", Turkish.RelativeReset(Now.AddMinutes(75), Now));
        Assert.Equal("15m", English.RelativeReset(Now.AddMinutes(15), Now));
        Assert.Equal("now", English.RelativeReset(Now.AddSeconds(-10), Now));
        Assert.Equal("şimdi", Turkish.RelativeReset(Now, Now));
    }

    [Fact]
    public void WindowLabelsCoverEveryKind()
    {
        Assert.Equal("5 saat", Turkish.UsageWindowLabel(Window(UsageWindowKind.FiveHour, 300), 0));
        Assert.Equal("Weekly", English.UsageWindowLabel(Window(UsageWindowKind.Weekly, 10_080), 0));
        Assert.Equal(
            "3 days",
            English.UsageWindowLabel(UsageWindow.Classified(55, null, 4_320), 1));
        Assert.Equal(
            "Usage window 2",
            English.UsageWindowLabel(UsageWindow.Classified(55, null, null, 1), 1));
        Assert.Equal(
            "1 saat 30 dk",
            Turkish.UsageWindowLabel(UsageWindow.Classified(10, null, 90), 0));
    }

    [Fact]
    public void HistoryRangeAndSummaryMatchMacOs()
    {
        var samples = new[]
        {
            new UsageHistorySample(Now, 33),
            new UsageHistorySample(Now.AddMinutes(35), 31)
        };
        var model = new UsageHistoryChartModel(samples);

        Assert.Equal("Son 35 dk", Turkish.UsageHistoryRange(model.RecordedDuration));
        Assert.Equal("Last 35m", English.UsageHistoryRange(model.RecordedDuration));
        Assert.Equal("33% → 31% · change -2", English.UsageHistorySummary(model));
        Assert.Equal("%33 → %31 · değişim -2", Turkish.UsageHistorySummary(model));

        Assert.Equal("First sample", English.UsageHistoryRange(TimeSpan.FromSeconds(30)));
        Assert.Equal("Last 2h 5m", English.UsageHistoryRange(TimeSpan.FromMinutes(125)));
        Assert.Equal("Last 1d 2h", English.UsageHistoryRange(TimeSpan.FromHours(26)));
    }

    [Fact]
    public void EveryIssueHasBothTranslations()
    {
        foreach (var code in Enum.GetValues<ProviderIssueCode>())
        {
            var issue = new ProviderIssue(code, "detail");
            Assert.False(string.IsNullOrWhiteSpace(Turkish.Issue(issue)));
            Assert.False(string.IsNullOrWhiteSpace(English.Issue(issue)));
            Assert.NotEqual(Turkish.Issue(issue), English.Issue(issue));
        }
    }

    [Fact]
    public void ContextMenuAndPanelStringsExistInBothLanguages()
    {
        var strings = new (string Turkish, string English)[]
        {
            (Turkish.RefreshNow, English.RefreshNow),
            (Turkish.ShowUsageBar, English.ShowUsageBar),
            (Turkish.LaunchAtStartup, English.LaunchAtStartup),
            (Turkish.Settings, English.Settings),
            (Turkish.ExitUsageBar, English.ExitUsageBar),
            (Turkish.CopyDiagnostics, English.CopyDiagnostics),
            (Turkish.ClearUsageHistory, English.ClearUsageHistory),
            (Turkish.ThresholdProfileTitle, English.ThresholdProfileTitle)
        };

        foreach (var (turkish, english) in strings)
        {
            Assert.False(string.IsNullOrWhiteSpace(turkish));
            Assert.False(string.IsNullOrWhiteSpace(english));
            Assert.NotEqual(turkish, english);
        }

        Assert.Equal("Şimdi yenile", Turkish.RefreshNow);
        Assert.Equal("UsageBar'dan çık", Turkish.ExitUsageBar);
        Assert.Equal("Windows açılışında başlat", Turkish.LaunchAtStartup);
    }

    [Fact]
    public void TrayShowsThePercentageWithAStateThatDoesNotDependOnColor()
    {
        var usages = Usages(remaining: 42);
        var presentation = TrayPresentationCalculator.Calculate(
            ProviderNames.Codex,
            usages,
            new UsageAlertPolicy(true, UsageAlertPreset.Balanced),
            English,
            isRefreshing: false,
            showResetCountdown: true,
            Now);

        Assert.Equal(TrayIconState.Normal, presentation.State);
        Assert.Equal("42", presentation.Label);
        Assert.Equal(42, presentation.RemainingPercent);
        Assert.Contains("UsageBar", presentation.Tooltip, StringComparison.Ordinal);
        Assert.Contains("Codex: 42% remaining", presentation.Tooltip, StringComparison.Ordinal);
        Assert.Contains("5 hours window resets in 1h 18m", presentation.Tooltip, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(42, TrayIconState.Normal)]
    [InlineData(18, TrayIconState.Warning)]
    [InlineData(7, TrayIconState.Critical)]
    public void TrayStateFollowsTheThresholds(int remaining, TrayIconState expected)
    {
        var presentation = TrayPresentationCalculator.Calculate(
            ProviderNames.Codex,
            Usages(remaining),
            new UsageAlertPolicy(true, UsageAlertPreset.Balanced),
            English,
            isRefreshing: false,
            showResetCountdown: false,
            Now);

        Assert.Equal(expected, presentation.State);
        Assert.Equal(remaining.ToString(System.Globalization.CultureInfo.InvariantCulture), presentation.Label);
    }

    [Fact]
    public void TrayFallsBackToNoDataRefreshingAndStale()
    {
        var empty = new Dictionary<string, ProviderUsage>(StringComparer.Ordinal);
        var policy = new UsageAlertPolicy(true, UsageAlertPreset.Balanced);

        var noData = TrayPresentationCalculator.Calculate(
            null, empty, policy, English, isRefreshing: false, showResetCountdown: false, Now);
        Assert.Equal(TrayIconState.NoData, noData.State);
        Assert.Equal("—", noData.Label);
        Assert.Contains("Connect a provider first", noData.Tooltip, StringComparison.Ordinal);

        var refreshing = TrayPresentationCalculator.Calculate(
            ProviderNames.Codex, empty, policy, English, isRefreshing: true, showResetCountdown: false, Now);
        Assert.Equal(TrayIconState.Refreshing, refreshing.State);
        Assert.Equal("↻", refreshing.Label);
        Assert.Contains("Waiting for Codex usage", refreshing.Tooltip, StringComparison.Ordinal);

        var stale = Usages(remaining: 42, stale: true);
        var stalePresentation = TrayPresentationCalculator.Calculate(
            ProviderNames.Codex, stale, policy, English, isRefreshing: false, showResetCountdown: false, Now);
        Assert.Equal(TrayIconState.Stale, stalePresentation.State);
        Assert.Equal("42", stalePresentation.Label);
        Assert.Contains("(stale)", stalePresentation.Tooltip, StringComparison.Ordinal);
    }

    [Fact]
    public void TooltipStaysWithinTheShellLimit()
    {
        var presentation = TrayPresentationCalculator.Calculate(
            ProviderNames.ClaudeCode,
            Usages(remaining: 42, providerName: ProviderNames.ClaudeCode),
            new UsageAlertPolicy(true, UsageAlertPreset.Balanced),
            Turkish,
            isRefreshing: false,
            showResetCountdown: true,
            Now);

        Assert.True(presentation.Tooltip.Length <= TrayPresentationCalculator.MaximumTooltipLength);
    }

    private static UsageWindow Window(UsageWindowKind kind, int durationMinutes) =>
        new(kind, 10, null, durationMinutes);

    private static Dictionary<string, ProviderUsage> Usages(
        int remaining,
        bool stale = false,
        string providerName = ProviderNames.Codex)
    {
        var windows = new[]
        {
            new UsageWindow(UsageWindowKind.FiveHour, 100 - remaining, Now.AddMinutes(78), 300)
        };

        var usage = stale
            ? new ProviderUsage(providerName, windows, ProviderIssue.CodexTimedOut, Now.AddMinutes(-5))
            : new ProviderUsage(providerName, windows, error: null, lastSuccessfulAt: Now);

        return new Dictionary<string, ProviderUsage>(StringComparer.Ordinal) { [providerName] = usage };
    }
}
