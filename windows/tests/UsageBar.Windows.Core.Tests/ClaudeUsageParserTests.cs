using UsageBar.Windows.Core.History;
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

    /// <summary>
    /// The canonical fixture carries a model-specific weekly row beside the
    /// all-models one. Every row must survive, each with its own identity.
    /// </summary>
    [Fact]
    public void KeepsModelSpecificWeeklyWindowsFromTheCanonicalFixture()
    {
        var usage = ParseFixture("print-usage-extra-window.txt");

        Assert.Null(usage.Error);
        Assert.Equal(3, usage.Windows.Count);
        Assert.Equal(
            new[] { UsageWindowKind.FiveHour, UsageWindowKind.Weekly, UsageWindowKind.WeeklyScoped("opus") },
            usage.Windows.Select(window => window.Kind).ToArray());
        Assert.Equal(new[] { 41, 18, 7 }, usage.Windows.Select(window => window.UsedPercent).ToArray());
        Assert.Equal(10_080, usage.Windows[2].DurationMinutes);
        Assert.NotNull(usage.Windows[2].ResetsAt);
    }

    /// <summary>
    /// The qualifier, not the row order, decides which row is the ordinary
    /// weekly limit — so the tray fallback can never silently switch to Opus.
    /// </summary>
    [Fact]
    public void OrdinaryWeeklyIsTheAllModelsRowRegardlessOfOrder()
    {
        var opusFirst = ClaudeUsageParser.Parse(
            "Current week (Opus): 92% used · resets Jul 26 at 10pm (Europe/Istanbul)\n" +
            "Current week (all models): 18% used · resets Jul 26 at 10pm (Europe/Istanbul)\n",
            Now);

        Assert.Equal(2, opusFirst.Windows.Count);
        Assert.Null(opusFirst.Session);
        Assert.Equal(18, opusFirst.Weekly?.UsedPercent);
        Assert.Equal(UsageWindowKind.Weekly, opusFirst.Weekly?.Kind);

        var summary = UsageSummaryCalculator.Summary(
            ProviderNames.ClaudeCode,
            new Dictionary<string, ProviderUsage> { [ProviderNames.ClaudeCode] = opusFirst });
        Assert.Equal(82, summary?.RemainingPercent);
        Assert.Equal(UsageWindowKind.Weekly, summary?.WindowKind);

        var withSession = ClaudeUsageParser.Parse(
            "Current week (Opus): 92% used\n" +
            "Current session: 41% used · resets Jul 23 at 5pm (Europe/Istanbul)\n" +
            "Current week (all models): 18% used\n",
            Now);
        var sessionSummary = UsageSummaryCalculator.Summary(
            ProviderNames.ClaudeCode,
            new Dictionary<string, ProviderUsage> { [ProviderNames.ClaudeCode] = withSession });
        Assert.Equal(59, sessionSummary?.RemainingPercent);
        Assert.Equal(UsageWindowKind.FiveHour, sessionSummary?.WindowKind);
    }

    [Theory]
    [InlineData(null, "weekly")]
    [InlineData("  ", "weekly")]
    [InlineData("all models", "weekly")]
    [InlineData(" All Models ", "weekly")]
    [InlineData("Opus", "weekly-opus")]
    [InlineData("Opus only", "weekly-opus")]
    [InlineData("Sonnet only", "weekly-sonnet")]
    [InlineData("Fable", "weekly-fable")]
    [InlineData("Premium models", "weekly-premium-models")]
    [InlineData("--Opus / 4.x--", "weekly-opus-4-x")]
    [InlineData("only", "weekly-only")] // a lone "only" is the whole qualifier, not a suffix
    [InlineData("Ünlü", "weekly-nl")] // non-ASCII letters are unsupported characters
    public void NormalizesWeeklyQualifiersToStableScopes(string? qualifier, string expectedHistoryKey)
    {
        Assert.Equal(expectedHistoryKey, UsageWindowKind.WeeklyKind(qualifier)?.HistoryKey);
    }

    /// <summary>
    /// The bound is the last step of normalization, so it holds at every
    /// separator and "only" boundary — not only for one unbroken token.
    /// </summary>
    [Fact]
    public void WeeklyScopeNeverExceedsTheMaximumLength()
    {
        var limit = UsageWindowKind.MaximumWeeklyScopeLength;
        Assert.Equal(32, limit);
        static string? Scope(string qualifier) =>
            UsageWindowKind.WeeklyKind(qualifier) is { CategoryKind: UsageWindowKind.Category.WeeklyScoped } kind ? kind.Scope : null;
        static string A(int count) => new('a', count);

        // A. One unbroken token is cut to the bound.
        Assert.Equal(A(32), Scope(A(100)));

        // B. A separator right at the bound: the cut lands on the "-", which
        // is dropped rather than left dangling — never 33 characters.
        Assert.Equal(A(31), Scope(A(31) + " b"));
        Assert.Equal(A(30) + "-b", Scope(A(30) + " bc"));

        // C. A trailing "only" around the bound is removed whole, never cut to
        // a partial "-on" / "-onl".
        Assert.Equal(A(27), Scope(A(27) + " only"));
        Assert.Equal(A(28), Scope(A(28) + " only"));
        Assert.Equal(A(30), Scope(A(30) + " only"));
        Assert.Equal(A(31), Scope(A(31) + " only"));
        Assert.Equal(A(32), Scope(A(40) + " only"));

        // D. Separator-heavy: leading/trailing/multiple separators collapse,
        // and the cut never leaves a trailing "-".
        Assert.Equal(A(30) + "-b", Scope("--" + A(30) + " / _ " + "bcd!!"));
        Assert.Equal(A(31), Scope("--" + A(31) + " / _ " + "bcd!!"));

        // E. The ordinary cases are untouched by the ordering.
        Assert.Equal("opus", Scope("Opus"));
        Assert.Equal("opus", Scope("Opus only"));
        Assert.Equal("sonnet", Scope("Sonnet only"));
        Assert.Equal("fable", Scope("Fable"));
        Assert.Equal("premium-models", Scope("Premium models"));
        Assert.Equal(UsageWindowKind.Weekly, UsageWindowKind.WeeklyKind("all models"));
        Assert.Null(UsageWindowKind.WeeklyKind("???"));

        // Every case above, plus every prefix of a long mixed input, stays
        // within the bound and never ends with a separator.
        var mixed = "--" + A(31) + " only / " + A(40) + " only";
        for (var length = 0; length <= mixed.Length; length++)
        {
            if (Scope(mixed[..length]) is not { } value)
            {
                continue;
            }

            Assert.True(value.Length <= limit, $"prefix {length}: {value}");
            Assert.False(value.EndsWith('-'), $"prefix {length}: {value}");
        }
    }

    /// <summary>
    /// A qualifier with nothing safe left is skipped: it must never become the
    /// all-models limit, and the slug never grows with the provider's text.
    /// </summary>
    [Fact]
    public void UnusableQualifiersAreSkippedAndScopesAreBounded()
    {
        Assert.Null(UsageWindowKind.WeeklyKind("???"));
        Assert.Null(UsageWindowKind.WeeklyKind("( )"));

        var bounded = UsageWindowKind.WeeklyKind(new string('a', 100));
        Assert.Equal(UsageWindowKind.MaximumWeeklyScopeLength, bounded?.Scope.Length);

        var usage = ClaudeUsageParser.Parse(
            "Current session: 41% used\n" +
            "Current week (Premium models): 40% used · resets Jul 26 at 10pm (Europe/Istanbul)\n" +
            "Current week (???): 60% used\n",
            Now);
        Assert.Null(usage.Error);
        Assert.Equal(
            new[] { UsageWindowKind.FiveHour, UsageWindowKind.WeeklyScoped("premium-models") },
            usage.Windows.Select(window => window.Kind).ToArray());
        Assert.Equal(40, usage.Windows[1].UsedPercent);
        Assert.Equal("weekly-premium-models", usage.Windows[1].Kind.HistoryKey);
        Assert.Null(usage.Weekly);
    }

    /// <summary>
    /// Repeated or malformed output must not produce two windows with one
    /// identity: the first valid row per kind wins, different scopes all stay.
    /// </summary>
    [Fact]
    public void KeepsTheFirstRowPerWeeklyIdentity()
    {
        var usage = ClaudeUsageParser.Parse(
            "Current week (all models): 18% used\n" +
            "Current week (Opus): 7% used\n" +
            "Current week (Opus only): 50% used\n" +
            "Current week (all models): 99% used\n" +
            "Current week (Sonnet only): 33% used\n",
            Now);

        Assert.Equal(
            new[] { UsageWindowKind.Weekly, UsageWindowKind.WeeklyScoped("opus"), UsageWindowKind.WeeklyScoped("sonnet") },
            usage.Windows.Select(window => window.Kind).ToArray());
        Assert.Equal(new[] { 18, 7, 33 }, usage.Windows.Select(window => window.UsedPercent).ToArray());
    }

    /// <summary>
    /// The scoped identity is visible in the history key, so a later change
    /// that leaked raw text ("Opus only", "(Opus)") into it would be caught.
    /// </summary>
    [Fact]
    public void ScopedWeeklyHistoryKeysAreDistinctAndAdditive()
    {
        Assert.Equal("weekly", UsageWindowKind.Weekly.HistoryKey);
        Assert.Equal("weekly-opus", UsageWindowKind.WeeklyScoped("opus").HistoryKey);
        Assert.Equal("Claude Code|weekly", UsageHistoryModel.SeriesKey(ProviderNames.ClaudeCode, UsageWindowKind.Weekly));
        Assert.Equal(
            "Claude Code|weekly-opus",
            UsageHistoryModel.SeriesKey(ProviderNames.ClaudeCode, UsageWindowKind.WeeklyScoped("opus")));
        Assert.NotEqual(UsageWindowKind.Weekly, UsageWindowKind.WeeklyScoped("opus"));
        Assert.NotEqual(UsageWindowKind.WeeklyScoped("opus"), UsageWindowKind.WeeklyScoped("sonnet"));

        // Two parsed weekly windows record into two series; the all-models
        // series keeps the all-models value instead of the scoped one.
        var usage = ParseFixture("print-usage-extra-window.txt");
        var history = UsageHistoryRecorder.Record(
            new Dictionary<string, IReadOnlyList<UsageHistorySample>>(),
            new Dictionary<string, ProviderUsage> { [ProviderNames.ClaudeCode] = usage },
            Now);
        Assert.Equal(
            new[] { "Claude Code|five-hour", "Claude Code|weekly", "Claude Code|weekly-opus" },
            history.Keys.OrderBy(key => key, StringComparer.Ordinal).ToArray());
        Assert.Equal(new[] { 82 }, history["Claude Code|weekly"].Select(sample => sample.RemainingPercent).ToArray());
        Assert.Equal(new[] { 93 }, history["Claude Code|weekly-opus"].Select(sample => sample.RemainingPercent).ToArray());
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
