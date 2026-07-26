using UsageBar.Windows.Core.Parsing;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

public sealed class ClaudeUsageParserTests
{
    private static readonly DateTimeOffset Now = new(2026, 7, 20, 12, 0, 0, TimeSpan.FromHours(3));

    private static ProviderUsage ParseFixture(string name) =>
        ClaudeUsageParser.Parse(Fixtures.ReadText($"claude/{name}"), Now);

    [Fact]
    public void ParsesBothWindowsFromPrintModeOutput()
    {
        var usage = ParseFixture("print-usage-both-windows.txt");

        Assert.Null(usage.Error);
        Assert.Equal(100, usage.Session?.UsedPercent);
        Assert.Equal(53, usage.Weekly?.UsedPercent);
        Assert.Equal(UsageWindowKind.FiveHour, usage.Session?.Kind);
        Assert.Equal(UsageWindowKind.Weekly, usage.Weekly?.Kind);
        Assert.NotNull(usage.Session?.ResetsAt);
        Assert.NotNull(usage.Weekly?.ResetsAt); // minute-less "10pm" still parses
    }

    [Fact]
    public void RoundsFractionalPercentAndToleratesAMissingReset()
    {
        var usage = ParseFixture("print-usage-fractional-and-partial.txt");

        Assert.Null(usage.Error);
        Assert.Equal(9, usage.Session?.UsedPercent); // 8.6 rounds up
        Assert.Equal(47, usage.Weekly?.UsedPercent);
        Assert.Null(usage.Weekly?.ResetsAt);
    }

    [Fact]
    public void FallsBackToWeeklyWhenNoSessionWindowIsReturned()
    {
        var usage = ParseFixture("print-usage-weekly-only.txt");

        Assert.Null(usage.Error);
        Assert.Null(usage.Session);
        Assert.Equal(26, usage.Weekly?.UsedPercent);

        var summary = UsageSummaryCalculator.Summary(
            ProviderNames.ClaudeCode,
            new Dictionary<string, ProviderUsage> { [ProviderNames.ClaudeCode] = usage });
        Assert.Equal(74, summary?.RemainingPercent);
        Assert.Equal(UsageWindowKind.Weekly, summary?.WindowKind);
    }

    [Fact]
    public void DistinguishesNotLoggedInFromUnreadable()
    {
        Assert.Equal("claude_not_logged_in", ParseFixture("print-usage-not-logged-in.txt").Error?.DiagnosticCode);
        Assert.Equal("claude_usage_unreadable", ParseFixture("print-usage-unreadable.txt").Error?.DiagnosticCode);
        Assert.Equal("claude_usage_unreadable", ClaudeUsageParser.Parse(string.Empty, Now).Error?.DiagnosticCode);
    }

    /// <summary>
    /// A partially written read must not silently drop the weekly window: the
    /// adapter waits for process exit, and this documents what the parser sees if
    /// it ever did not.
    /// </summary>
    [Fact]
    public void TruncatedOutputKeepsOnlyTheCompleteWindow()
    {
        var usage = ParseFixture("print-usage-truncated.txt");

        Assert.Null(usage.Error);
        Assert.Equal(12, usage.Session?.UsedPercent);
        Assert.Null(usage.Weekly);
    }

    [Fact]
    public void ParsesTheLegacyInteractivePanelShape()
    {
        var usage = ParseFixture("screen-usage-panel.txt");

        Assert.Equal(41, usage.Session?.UsedPercent);
        Assert.Equal(18, usage.Weekly?.UsedPercent);
        Assert.NotNull(usage.Session?.ResetsAt);
        Assert.NotNull(usage.Weekly?.ResetsAt);
    }

    [Fact]
    public void SummaryPrefersTheFiveHourWindow()
    {
        var usage = new ProviderUsage(ProviderNames.ClaudeCode, new[]
        {
            new UsageWindow(UsageWindowKind.FiveHour, 41, null, 300),
            new UsageWindow(UsageWindowKind.Weekly, 74, null, 10_080)
        }, error: null);

        var summary = UsageSummaryCalculator.Summary(
            ProviderNames.ClaudeCode,
            new Dictionary<string, ProviderUsage> { [ProviderNames.ClaudeCode] = usage });

        Assert.Equal(59, summary?.RemainingPercent);
    }
}
