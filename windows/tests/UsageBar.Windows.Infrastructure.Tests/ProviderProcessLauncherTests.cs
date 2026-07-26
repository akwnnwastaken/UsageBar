using System.Runtime.Versioning;
using System.Text;
using UsageBar.Windows.Core.Parsing;
using UsageBar.Windows.Infrastructure.Process;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// Bounding, timeouts, isolation and end-to-end capture through the real
/// launcher. Uses stock Windows executables as stand-ins for a provider.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class ProviderProcessLauncherTests
{
    private static string SystemDirectory =>
        Environment.GetFolderPath(Environment.SpecialFolder.System);

    private static string CmdPath => Path.Combine(SystemDirectory, "cmd.exe");

    [WindowsFact]
    public async Task CapturesStandardOutputAndTheRealExitCode()
    {
        var result = await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
        {
            ExecutablePath = CmdPath,
            Arguments = new[] { "/c", "echo usagebar" },
            Timeout = TimeSpan.FromSeconds(20)
        }).ConfigureAwait(false);

        Assert.True(result.Launched);
        Assert.False(result.TimedOut);
        Assert.Equal(0, result.ExitCode);
        Assert.Contains("usagebar", Encoding.UTF8.GetString(result.StandardOutput), StringComparison.Ordinal);
    }

    [WindowsFact]
    public async Task ReportsANonZeroExitCodeWithoutCallingItATimeout()
    {
        var result = await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
        {
            ExecutablePath = CmdPath,
            Arguments = new[] { "/c", "exit 3" },
            Timeout = TimeSpan.FromSeconds(20)
        }).ConfigureAwait(false);

        Assert.True(result.Launched);
        Assert.False(result.TimedOut);
        Assert.Equal(3, result.ExitCode);
    }

    [WindowsFact]
    public async Task StandardErrorIsCapturedSeparatelyFromStandardOutput()
    {
        var result = await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
        {
            ExecutablePath = CmdPath,
            Arguments = new[] { "/c", "echo to-stderr 1>&2" },
            Timeout = TimeSpan.FromSeconds(20)
        }).ConfigureAwait(false);

        Assert.Empty(Encoding.UTF8.GetString(result.StandardOutput).Trim());
        Assert.Contains("to-stderr", Encoding.UTF8.GetString(result.StandardError), StringComparison.Ordinal);
    }

    [WindowsFact]
    public async Task OutputIsBoundedAndTheOverflowIsReported()
    {
        // A loop that keeps printing until it is stopped.
        var result = await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
        {
            ExecutablePath = CmdPath,
            Arguments = new[] { "/c", "for /L %i in (1,1,200000) do @echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" },
            MaximumOutputBytes = 64 * 1024,
            Timeout = TimeSpan.FromSeconds(60)
        }).ConfigureAwait(false);

        Assert.True(result.OutputExceeded, "The capture should report that it overflowed.");
        Assert.True(
            result.StandardOutput.Length <= 64 * 1024,
            $"Captured {result.StandardOutput.Length} bytes, above the limit.");
    }

    [WindowsFact]
    public async Task StandardInputIsDeliveredToTheChild()
    {
        var result = await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
        {
            ExecutablePath = CmdPath,
            Arguments = new[] { "/c", "findstr", "usage" },
            StandardInput = Encoding.UTF8.GetBytes("nothing here\r\nusage line\r\n"),
            Timeout = TimeSpan.FromSeconds(20)
        }).ConfigureAwait(false);

        Assert.Contains("usage line", Encoding.UTF8.GetString(result.StandardOutput), StringComparison.Ordinal);
    }

    [WindowsFact]
    public async Task IsCompleteStopsTheRunAsSoonAsTheAnswerArrives()
    {
        // Prints the answer, then would keep running for five minutes.
        //
        // The arguments stay separate rather than being packed into one quoted
        // script string: the launcher escapes embedded quotes with the
        // CommandLineToArgvW rules, and cmd.exe does not understand \" — so a
        // hand-quoted script would arrive mangled.
        var before = DateTimeOffset.UtcNow;
        var result = await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
        {
            ExecutablePath = CmdPath,
            Arguments = new[]
            {
                "/c",
                "type", Fixtures.Path("codex/five-hour-and-weekly.jsonl"),
                "&",
                "ping", "-n", "300", "127.0.0.1", ">", "nul"
            },
            Timeout = TimeSpan.FromSeconds(120),
            IsComplete = static output => CodexResponseParser.ParseStream(output.Span) is not null
        }).ConfigureAwait(false);
        var elapsed = DateTimeOffset.UtcNow - before;

        Assert.NotNull(CodexResponseParser.ParseStream(result.StandardOutput));
        Assert.True(elapsed < TimeSpan.FromSeconds(60), $"The run did not stop early (took {elapsed}).");
        // Finishing early because the answer arrived is not a timeout.
        Assert.False(result.TimedOut);
    }

    [WindowsFact]
    public async Task ProvidersRunFromUsageBarsOwnDirectoryNotTheCurrentOne()
    {
        var result = await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
        {
            ExecutablePath = CmdPath,
            Arguments = new[] { "/c", "cd" },
            Timeout = TimeSpan.FromSeconds(20)
        }).ConfigureAwait(false);

        var workingDirectory = Encoding.UTF8.GetString(result.StandardOutput).Trim();

        Assert.Equal(
            ProviderProcessEnvironment.WorkingDirectory.TrimEnd(Path.DirectorySeparatorChar),
            workingDirectory.TrimEnd(Path.DirectorySeparatorChar),
            ignoreCase: true);
        Assert.NotEqual(Directory.GetCurrentDirectory(), workingDirectory, StringComparer.OrdinalIgnoreCase);
    }

    [WindowsFact]
    public async Task TheProviderEnvironmentIsRestricted()
    {
        Environment.SetEnvironmentVariable("USAGEBAR_TEST_SECRET", "must-not-be-inherited");
        try
        {
            var result = await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
            {
                ExecutablePath = CmdPath,
                Arguments = new[] { "/c", "set" },
                Timeout = TimeSpan.FromSeconds(20)
            }).ConfigureAwait(false);

            var environment = Encoding.UTF8.GetString(result.StandardOutput);
            Assert.DoesNotContain("USAGEBAR_TEST_SECRET", environment, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("SystemRoot=", environment, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Environment.SetEnvironmentVariable("USAGEBAR_TEST_SECRET", null);
        }
    }

    [WindowsFact]
    public async Task AMissingExecutableIsReportedAsALaunchFailure()
    {
        var result = await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
        {
            ExecutablePath = Path.Combine(SystemDirectory, "usagebar-does-not-exist.exe"),
            Arguments = Array.Empty<string>(),
            Timeout = TimeSpan.FromSeconds(10)
        }).ConfigureAwait(false);

        Assert.False(result.Launched);
        Assert.NotNull(result.LaunchFailure);
        Assert.Empty(result.StandardOutput);
    }
}
