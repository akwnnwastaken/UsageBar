using System.Runtime.Versioning;
using System.Text;
using System.Text.Json;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Infrastructure.Process;
using UsageBar.Windows.Infrastructure.Providers;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// The Codex adapter's outcome mapping, driven from real fixtures and
/// synthesized process results so every category is covered without a signed-in
/// Codex installation.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class CodexUsageReaderTests
{
    private static ProviderProcessResult Result(
        byte[]? output = null,
        byte[]? error = null,
        bool outputExceeded = false,
        bool errorExceeded = false,
        bool timedOut = false,
        int exitCode = 0,
        string? launchFailure = null) =>
        new()
        {
            StandardOutput = output ?? Array.Empty<byte>(),
            StandardError = error ?? Array.Empty<byte>(),
            OutputExceeded = outputExceeded,
            ErrorExceeded = errorExceeded,
            TimedOut = timedOut,
            ExitCode = exitCode,
            LaunchFailure = launchFailure
        };

    [Fact]
    public void SuccessfulResponseBecomesUsage()
    {
        var usage = CodexUsageReader.Interpret(
            Result(Fixtures.ReadBytes("codex/five-hour-and-weekly.jsonl")));

        Assert.Null(usage.Error);
        Assert.Equal(35, usage.Session?.UsedPercent);
        Assert.Equal(12, usage.Weekly?.UsedPercent);
    }

    [Fact]
    public void InterleavedProtocolMessagesStillYieldUsage()
    {
        var usage = CodexUsageReader.Interpret(
            Result(Fixtures.ReadBytes("codex/interleaved-protocol-messages.jsonl")));

        Assert.Null(usage.Error);
        Assert.Equal(35, usage.Session?.UsedPercent);
    }

    [Fact]
    public void WeeklyOnlyAccountsAreSupported()
    {
        var usage = CodexUsageReader.Interpret(Result(Fixtures.ReadBytes("codex/weekly-only.jsonl")));

        Assert.Null(usage.Error);
        Assert.Null(usage.Session);
        Assert.Equal(13, usage.Weekly?.UsedPercent);
    }

    [Fact]
    public void OversizedOutputIsReportedAsSuch()
    {
        var usage = CodexUsageReader.Interpret(
            Result(Fixtures.ReadBytes("codex/five-hour-and-weekly.jsonl"), outputExceeded: true));

        Assert.Equal("output_too_large", usage.Error?.DiagnosticCode);
        Assert.Equal(ProviderNames.Codex, usage.Error?.Detail);
    }

    [Fact]
    public void OversizedErrorOutputIsAlsoReported()
    {
        Assert.Equal(
            "output_too_large",
            CodexUsageReader.Interpret(Result(errorExceeded: true)).Error?.DiagnosticCode);
    }

    [Fact]
    public void AnIncompatibleCliIsDetectedFromItsStandardError()
    {
        var usage = CodexUsageReader.Interpret(
            Result(error: Fixtures.ReadBytes("codex/incompatible-flag-stderr.txt"), exitCode: 2));

        Assert.Equal("codex_incompatible", usage.Error?.DiagnosticCode);
    }

    /// <summary>
    /// A timed-out fetch that UsageBar itself terminated leaves a non-zero exit
    /// code. It must classify as a timeout, never as a command failure.
    /// </summary>
    [Fact]
    public void TimeoutWinsOverTheExitCodeUsageBarCaused()
    {
        Assert.Equal(
            "codex_timed_out",
            CodexUsageReader.Interpret(Result(timedOut: true, exitCode: 1)).Error?.DiagnosticCode);
    }

    [Fact]
    public void ANonZeroExitWithoutATimeoutIsACommandFailure()
    {
        Assert.Equal(
            "codex_command_failed",
            CodexUsageReader.Interpret(Result(exitCode: 3)).Error?.DiagnosticCode);
    }

    [Fact]
    public void ACleanExitWithNoOutputIsAnEmptyResponse()
    {
        Assert.Equal(
            "codex_empty_response",
            CodexUsageReader.Interpret(Result()).Error?.DiagnosticCode);
    }

    [Fact]
    public void AResponseWithoutRateLimitsKeepsItsOwnError()
    {
        Assert.Equal(
            "codex_limit_missing",
            CodexUsageReader.Interpret(Result(Fixtures.ReadBytes("codex/missing-rate-limits.jsonl")))
                .Error?.DiagnosticCode);

        Assert.Equal(
            "codex_usage_unavailable",
            CodexUsageReader.Interpret(Result(Fixtures.ReadBytes("codex/error-response.jsonl")))
                .Error?.DiagnosticCode);
    }

    [Fact]
    public void MalformedOutputIsNotMistakenForUsage()
    {
        Assert.Equal(
            "codex_empty_response",
            CodexUsageReader.Interpret(Result(Fixtures.ReadBytes("codex/malformed.jsonl")))
                .Error?.DiagnosticCode);
    }

    [Fact]
    public void ALaunchFailureIsReportedWithoutTouchingTheOutput()
    {
        var usage = CodexUsageReader.Interpret(Result(launchFailure: "Win32 error 2"));

        Assert.Equal("codex_launch_failed", usage.Error?.DiagnosticCode);
        Assert.Empty(usage.Windows);
    }

    [Fact]
    public void TheHandshakeRequestsRateLimitsAsIdTwo()
    {
        var messages = CodexUsageReader.HandshakeMessages("1.9.0");
        var lines = messages.Split('\n', StringSplitOptions.RemoveEmptyEntries);

        Assert.Equal(3, lines.Length);
        Assert.EndsWith("\n", messages, StringComparison.Ordinal);

        foreach (var line in lines)
        {
            using var document = JsonDocument.Parse(line);
            Assert.Equal(JsonValueKind.Object, document.RootElement.ValueKind);
        }

        using var initialize = JsonDocument.Parse(lines[0]);
        Assert.Equal("initialize", initialize.RootElement.GetProperty("method").GetString());
        Assert.Equal(1, initialize.RootElement.GetProperty("id").GetInt32());
        Assert.Equal(
            "1.9.0",
            initialize.RootElement.GetProperty("params").GetProperty("clientInfo")
                .GetProperty("version").GetString());

        using var initialized = JsonDocument.Parse(lines[1]);
        Assert.Equal("initialized", initialized.RootElement.GetProperty("method").GetString());

        using var rateLimits = JsonDocument.Parse(lines[2]);
        Assert.Equal("account/rateLimits/read", rateLimits.RootElement.GetProperty("method").GetString());
        Assert.Equal(2, rateLimits.RootElement.GetProperty("id").GetInt32());
    }

    [Fact]
    public void TheHandshakeEscapesTheClientVersion()
    {
        var messages = CodexUsageReader.HandshakeMessages("1.0\"; drop\n");

        foreach (var line in messages.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            using var document = JsonDocument.Parse(line);
            Assert.Equal(JsonValueKind.Object, document.RootElement.ValueKind);
        }
    }

    [Fact]
    public void TheAppServerIsStartedWithTheSafeDisableFlags()
    {
        Assert.Equal(
            new[]
            {
                "app-server", "--stdio",
                "--disable", "apps",
                "--disable", "plugins",
                "--disable", "remote_plugin",
                "--disable", "plugin_sharing"
            },
            CodexUsageReader.AppServerArguments);
    }

    [Theory]
    [InlineData("error: unexpected argument '--disable' found", true)]
    [InlineData("unknown option --disable", true)]
    [InlineData("unrecognized option: --disable", true)]
    [InlineData("error: unexpected argument '--verbose' found", false)]
    [InlineData("some unrelated warning", false)]
    [InlineData("", false)]
    public void IncompatibilityNeedsBothTheFlagAndAnUnknownOptionSignal(string standardError, bool expected)
    {
        Assert.Equal(expected, CodexUsageReader.IsIncompatible(Encoding.UTF8.GetBytes(standardError)));
    }

    /// <summary>
    /// End-to-end through the real launcher: a stock Windows executable stands in
    /// for the Codex app server and emits the fixture, which must survive
    /// containment, redirection and bounded capture intact.
    /// </summary>
    [WindowsFact]
    public async Task TheLauncherDeliversAnAppServerResponseIntact()
    {
        var cmd = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
        var result = await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
        {
            ExecutablePath = cmd,
            Arguments = new[] { "/c", "type", Fixtures.Path("codex/five-hour-and-weekly.jsonl") },
            Timeout = TimeSpan.FromSeconds(30)
        }).ConfigureAwait(false);

        var usage = CodexUsageReader.Interpret(result);

        // Surfaces the child's own diagnostics when this fails, so a broken
        // command line is visible in the CI log instead of just an error code.
        Assert.True(
            usage.Error is null,
            $"issue={usage.Error?.DiagnosticCode} exit={result.ExitCode} " +
            $"stdout={Encoding.UTF8.GetString(result.StandardOutput)} " +
            $"stderr={Encoding.UTF8.GetString(result.StandardError)}");
        Assert.Equal(35, usage.Session?.UsedPercent);
        Assert.Equal(12, usage.Weekly?.UsedPercent);
    }
}
