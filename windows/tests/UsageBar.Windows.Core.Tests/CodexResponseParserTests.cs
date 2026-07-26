using System.Text;
using UsageBar.Windows.Core.Parsing;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

public sealed class CodexResponseParserTests
{
    private static ProviderUsage? ParseFixture(string name) =>
        CodexResponseParser.ParseStream(Fixtures.ReadBytes($"codex/{name}"));

    [Fact]
    public void ParsesFiveHourAndWeeklyWindows()
    {
        var usage = ParseFixture("five-hour-and-weekly.jsonl");

        Assert.NotNull(usage);
        Assert.Null(usage!.Error);
        Assert.Equal(35, usage.Session?.UsedPercent);
        Assert.Equal(UsageWindowKind.FiveHour, usage.Session?.Kind);
        Assert.Equal(12, usage.Weekly?.UsedPercent); // 12.4 rounds down
        Assert.Equal(UsageWindowKind.Weekly, usage.Weekly?.Kind);
        Assert.Equal(
            DateTimeOffset.FromUnixTimeSeconds(1784740000),
            usage.Session?.ResetsAt);
    }

    [Fact]
    public void ParsesWeeklyOnlyAccountWithoutInventingAFiveHourWindow()
    {
        var usage = ParseFixture("weekly-only.jsonl");

        Assert.NotNull(usage);
        Assert.Null(usage!.Session);
        Assert.Equal(13, usage.Weekly?.UsedPercent);
        Assert.Single(usage.Windows);
    }

    [Fact]
    public void KeepsAdditionalDurationWindowsAndPicksTheMostConstrained()
    {
        var usage = ParseFixture("additional-duration-window.jsonl");

        Assert.NotNull(usage);
        Assert.Equal(2, usage!.Windows.Count);
        Assert.Contains(usage.Windows, window => window.Kind == UsageWindowKind.Duration(4320));

        var summary = UsageSummaryCalculator.Summary(
            ProviderNames.Codex,
            new Dictionary<string, ProviderUsage> { [ProviderNames.Codex] = usage });
        Assert.Equal(45, summary?.RemainingPercent);
    }

    [Fact]
    public void SkipsWindowsMissingUsedPercent()
    {
        var usage = ParseFixture("missing-fields.jsonl");

        Assert.NotNull(usage);
        Assert.Single(usage!.Windows);
        Assert.Equal(41, usage.Windows[0].UsedPercent);
        // No duration means the window keeps its position instead of guessing.
        Assert.Equal(UsageWindowKind.Unknown(1), usage.Windows[0].Kind);
    }

    [Fact]
    public void ReportsMissingRateLimitsAndErrorResponses()
    {
        Assert.Equal("codex_limit_missing", ParseFixture("missing-rate-limits.jsonl")?.Error?.DiagnosticCode);
        Assert.Equal("codex_usage_unavailable", ParseFixture("error-response.jsonl")?.Error?.DiagnosticCode);
    }

    [Fact]
    public void IgnoresInterleavedProtocolMessagesAndOtherRequestIds()
    {
        var usage = ParseFixture("interleaved-protocol-messages.jsonl");

        Assert.NotNull(usage);
        Assert.Equal(35, usage!.Session?.UsedPercent);
        Assert.Equal(12, usage.Weekly?.UsedPercent);
    }

    [Fact]
    public void MalformedOutputYieldsNoUsageInsteadOfThrowing()
    {
        Assert.Null(ParseFixture("malformed.jsonl"));
        Assert.Null(CodexResponseParser.ParseStream(ReadOnlySpan<byte>.Empty));
        Assert.Null(CodexResponseParser.ParseLine(Encoding.UTF8.GetBytes("{\"id\":1,\"result\":{}}")));
    }

    [Fact]
    public void EmptyResponseDoesNotProduceUsage()
    {
        // A well-formed response for another id must never be read as usage.
        Assert.Null(CodexResponseParser.ParseStream(
            Encoding.UTF8.GetBytes("{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"rateLimits\":{}}}\n")));
    }

    [Theory]
    [InlineData(true, false, false, true, 9, CodexFetchOutcome.Usage)]
    [InlineData(false, true, true, true, 9, CodexFetchOutcome.OutputTooLarge)]
    [InlineData(false, false, false, true, 15, CodexFetchOutcome.TimedOut)]
    [InlineData(false, false, true, false, 1, CodexFetchOutcome.Incompatible)]
    [InlineData(false, false, false, false, 3, CodexFetchOutcome.CommandFailed)]
    [InlineData(false, false, false, false, 0, CodexFetchOutcome.EmptyResponse)]
    public void ClassifiesOutcomesInTheMacOsOrder(
        bool hasUsage,
        bool outputExceeded,
        bool incompatible,
        bool didTimeout,
        int exitCode,
        CodexFetchOutcome expected)
    {
        Assert.Equal(
            expected,
            CodexFetchOutcomeClassifier.Classify(hasUsage, outputExceeded, incompatible, didTimeout, exitCode));
    }
}
