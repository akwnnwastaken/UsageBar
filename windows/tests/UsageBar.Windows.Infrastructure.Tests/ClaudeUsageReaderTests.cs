using System.Runtime.Versioning;
using System.Text;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Infrastructure.Providers;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// How one Claude adapter run becomes a provider reading. Driven from fixtures
/// and synthesized results, so every outcome is covered without an installed
/// Claude — CI runners have none.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class ClaudeUsageReaderTests
{
    private static readonly DateTimeOffset Now = new(2026, 7, 20, 12, 0, 0, TimeSpan.FromHours(3));

    private static ClaudeAdapterResult Result(
        string? output = null,
        string? error = null,
        bool outputExceeded = false,
        bool timedOut = false,
        bool cancelled = false,
        int exitCode = 0,
        string? launchFailure = null,
        ProviderAdapterKind adapterKind = ProviderAdapterKind.NativeExecutable) =>
        new()
        {
            StandardOutput = Encoding.UTF8.GetBytes(output ?? string.Empty),
            StandardError = Encoding.UTF8.GetBytes(error ?? string.Empty),
            OutputExceeded = outputExceeded,
            TimedOut = timedOut,
            Cancelled = cancelled,
            ExitCode = exitCode,
            LaunchFailure = launchFailure,
            AdapterKind = adapterKind
        };

    private static ProviderUsage Interpret(string fixture) =>
        ClaudeUsageReader.Interpret(Result(Fixtures.ReadText($"claude/{fixture}")), Now);

    [Fact]
    public void ValidOutputYieldsBothWindows()
    {
        var usage = Interpret("print-usage-both-windows.txt");

        Assert.Null(usage.Error);
        Assert.Equal(100, usage.Session?.UsedPercent);
        Assert.Equal(53, usage.Weekly?.UsedPercent);
        Assert.NotNull(usage.Session?.ResetsAt);
        Assert.NotNull(usage.Weekly?.ResetsAt);
    }

    [Fact]
    public void WeeklyOnlyOutputIsAccepted()
    {
        var usage = Interpret("print-usage-weekly-only.txt");

        Assert.Null(usage.Error);
        Assert.Null(usage.Session);
        Assert.Equal(26, usage.Weekly?.UsedPercent);
    }

    /// <summary>
    /// Every window Claude returns must survive to the panel, including one the
    /// five-hour/weekly pair does not cover.
    /// </summary>
    [Fact]
    public void ExtraDurationWindowsAreKept()
    {
        var usage = Interpret("print-usage-extra-window.txt");

        Assert.Null(usage.Error);
        Assert.Equal(41, usage.Session?.UsedPercent);
        Assert.Equal(18, usage.Weekly?.UsedPercent);

        // The five-hour window drives the tray summary even with more present.
        var summary = UsageSummaryCalculator.Summary(
            ProviderNames.ClaudeCode,
            new Dictionary<string, ProviderUsage> { [ProviderNames.ClaudeCode] = usage });
        Assert.Equal(59, summary?.RemainingPercent);
        Assert.Equal(UsageWindowKind.FiveHour, summary?.WindowKind);
    }

    [Theory]
    [InlineData("print-usage-not-logged-in.txt")]
    [InlineData("print-usage-login-required.txt")]
    public void SignedOutIsReportedAsSuch(string fixture)
    {
        Assert.Equal("claude_not_logged_in", Interpret(fixture).Error?.DiagnosticCode);
    }

    [Fact]
    public void MalformedOutputIsUnreadableRatherThanWrong()
    {
        Assert.Equal("claude_usage_unreadable", Interpret("print-usage-unreadable.txt").Error?.DiagnosticCode);
    }

    /// <summary>
    /// A partially written final line must not be turned into a wrong number:
    /// the complete window still reads, the incomplete one is simply absent.
    /// </summary>
    [Fact]
    public void AnIncompleteFinalLineNeverProducesAWrongWindow()
    {
        var usage = Interpret("print-usage-truncated.txt");

        Assert.Null(usage.Error);
        Assert.Equal(12, usage.Session?.UsedPercent);
        Assert.Null(usage.Weekly);
    }

    [Fact]
    public void OversizedOutputIsReportedBeforeAnythingElse()
    {
        var usage = ClaudeUsageReader.Interpret(
            Result(Fixtures.ReadText("claude/print-usage-both-windows.txt"), outputExceeded: true),
            Now);

        Assert.Equal("output_too_large", usage.Error?.DiagnosticCode);
        Assert.Equal(ProviderNames.ClaudeCode, usage.Error?.Detail);
    }

    /// <summary>
    /// UsageBar terminates a timed-out run itself, which leaves a non-zero exit
    /// code. That code must never be read as a command failure.
    /// </summary>
    [Fact]
    public void TimeoutWinsOverTheExitCodeUsageBarCaused()
    {
        Assert.Equal(
            "claude_usage_timed_out",
            ClaudeUsageReader.Interpret(Result(timedOut: true, exitCode: 1), Now).Error?.DiagnosticCode);
    }

    [Fact]
    public void CancellationIsNotReportedAsAFailure()
    {
        var usage = ClaudeUsageReader.Interpret(Result(cancelled: true, exitCode: 1), Now);

        Assert.Equal("cancelled", usage.Error?.DiagnosticCode);
        Assert.True(usage.Error?.IsInformational);
    }

    [Fact]
    public void ANonZeroExitWithoutATimeoutIsACommandFailure()
    {
        Assert.Equal(
            "claude_command_failed",
            ClaudeUsageReader.Interpret(Result(exitCode: 3), Now).Error?.DiagnosticCode);
    }

    [Fact]
    public void ALaunchFailureIsReportedWithoutTouchingTheOutput()
    {
        var usage = ClaudeUsageReader.Interpret(Result(launchFailure: "Win32 error 2"), Now);

        Assert.Equal("claude_launch_failed", usage.Error?.DiagnosticCode);
        Assert.Empty(usage.Windows);
    }

    /// <summary>
    /// Git for Windows is optional for this query, so its absence is never
    /// assumed to be the problem. The code is produced only when Claude itself
    /// says it could not find Git Bash.
    /// </summary>
    [Fact]
    public void GitBashIsReportedOnlyWhenClaudeComplainsAboutIt()
    {
        var complaint = ClaudeUsageReader.Interpret(
            Result(error: Fixtures.ReadText("claude/native-git-bash-missing.txt"), exitCode: 1),
            Now);
        Assert.Equal("claude_git_bash_missing", complaint.Error?.DiagnosticCode);

        // An unrelated failure is not reinterpreted as a Git Bash problem.
        var unrelated = ClaudeUsageReader.Interpret(Result(error: "something else went wrong", exitCode: 1), Now);
        Assert.Equal("claude_command_failed", unrelated.Error?.DiagnosticCode);

        // A healthy read is never reinterpreted either, even if the word appears.
        var healthy = ClaudeUsageReader.Interpret(
            Result(
                Fixtures.ReadText("claude/print-usage-both-windows.txt"),
                error: "warning: git bash not found"),
            Now);
        Assert.Null(healthy.Error);
    }

    [Theory]
    [InlineData("", "", false)]
    [InlineData("using git bash for tools", "", false)]
    [InlineData("Could not find Git Bash", "", true)]
    [InlineData("bash.exe: no such file", "", true)]
    [InlineData("unrelated failure", "", false)]
    public void GitBashDetectionNeedsBothAMentionAndAComplaint(
        string standardError,
        string standardOutput,
        bool expected)
    {
        Assert.Equal(
            expected,
            ClaudeUsageReader.MentionsGitBash(Encoding.UTF8.GetBytes(standardError), standardOutput));
    }

    [Theory]
    // usage and oversized output outrank everything, as they do for Codex.
    [InlineData(true, false, false, false, true, false, 9, ClaudeFetchOutcome.Usage)]
    [InlineData(false, true, true, true, true, true, 9, ClaudeFetchOutcome.OutputTooLarge)]
    // A stopped run explains itself before a deadline or an exit code does.
    [InlineData(false, false, true, false, true, true, 1, ClaudeFetchOutcome.Cancelled)]
    [InlineData(false, false, true, false, true, false, 1, ClaudeFetchOutcome.TimedOut)]
    [InlineData(false, false, true, false, false, false, 1, ClaudeFetchOutcome.NotLoggedIn)]
    [InlineData(false, false, false, true, false, false, 1, ClaudeFetchOutcome.GitBashMissing)]
    [InlineData(false, false, false, false, false, false, 3, ClaudeFetchOutcome.CommandFailed)]
    [InlineData(false, false, false, false, false, false, 0, ClaudeFetchOutcome.Unreadable)]
    public void OutcomeOrderingMatchesTheCodexPrecedent(
        bool hasUsage,
        bool outputExceeded,
        bool notLoggedIn,
        bool gitBashMissing,
        bool didTimeout,
        bool wasCancelled,
        int exitCode,
        ClaudeFetchOutcome expected)
    {
        Assert.Equal(
            expected,
            ClaudeFetchOutcomeClassifier.Classify(
                hasUsage, outputExceeded, notLoggedIn, gitBashMissing, didTimeout, wasCancelled, exitCode));
    }

    /// <summary>
    /// A failed refresh keeps the previous good value on screen, and that stale
    /// value must never be recorded as a new history sample.
    /// </summary>
    [Fact]
    public void StaleTransitionKeepsTheValueButNotTheHistory()
    {
        var good = ClaudeUsageReader.Interpret(
            Result(Fixtures.ReadText("claude/print-usage-both-windows.txt")),
            Now);
        var accepted = ProviderUsageTransition.Accept(null, good, Now);

        var failure = ClaudeUsageReader.Interpret(Result(timedOut: true, exitCode: 1), Now);
        var stale = ProviderUsageTransition.Accept(accepted, failure, Now.AddMinutes(5));

        Assert.True(stale.IsStale);
        Assert.Equal(Now, stale.LastSuccessfulAt);
        Assert.Equal(good.Session?.RemainingPercent, stale.Session?.RemainingPercent);

        var history = Core.History.UsageHistoryRecorder.Record(
            new Dictionary<string, IReadOnlyList<Core.History.UsageHistorySample>>(StringComparer.Ordinal),
            new Dictionary<string, ProviderUsage>(StringComparer.Ordinal)
            {
                [ProviderNames.ClaudeCode] = stale
            },
            new[] { ProviderNames.ClaudeCode },
            Now.AddMinutes(5));

        Assert.Empty(history);
    }

    [Fact]
    public void TheQueryIsTheSameOneMacOsRuns()
    {
        Assert.Equal(
            new[]
            {
                "-p", "/usage",
                "--no-session-persistence",
                "--setting-sources", "",
                "--no-chrome",
                "--strict-mcp-config",
                "--tools", ""
            },
            ClaudeQuery.Arguments);
    }
}
