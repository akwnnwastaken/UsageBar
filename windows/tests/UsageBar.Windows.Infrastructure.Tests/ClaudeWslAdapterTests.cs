using System.Runtime.Versioning;
using System.Text;
using UsageBar.Windows.Infrastructure.Providers;
using UsageBar.Windows.Infrastructure.Wsl;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// The WSL command shape and distribution parsing. These assert what UsageBar
/// asks wsl.exe to do without needing WSL installed — CI runners have none.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class ClaudeWslAdapterTests
{
    /// <summary>
    /// The command must reach Claude without a login shell: `--exec` runs the
    /// target directly, so no interactive startup file is ever sourced.
    /// </summary>
    [Fact]
    public void TheCommandUsesNonShellExecution()
    {
        var arguments = WslCommandRunner.BuildExecArguments(
            "Ubuntu",
            useHomeDirectory: true,
            new[] { ".local/bin/claude", "-p", "/usage" });

        Assert.Equal(
            new[] { "--distribution", "Ubuntu", "--cd", "~", "--exec", ".local/bin/claude", "-p", "/usage" },
            arguments);

        // Nothing that would introduce a shell.
        Assert.DoesNotContain("bash", arguments);
        Assert.DoesNotContain("-lc", arguments);
        Assert.DoesNotContain("sh", arguments);
        Assert.DoesNotContain("cmd.exe", arguments);
        Assert.DoesNotContain("powershell", arguments);
    }

    [Fact]
    public void TheDistributionIsOmittedWhenNoneIsChosen()
    {
        var arguments = WslCommandRunner.BuildExecArguments(
            distribution: null,
            useHomeDirectory: false,
            new[] { "claude", "--version" });

        Assert.Equal(new[] { "--exec", "claude", "--version" }, arguments);
    }

    /// <summary>
    /// Running from the Linux home means the query never starts in a Windows
    /// project directory, and lets Claude be addressed relative to the home so
    /// UsageBar never learns the home path at all.
    /// </summary>
    [Fact]
    public void TheHomeDirectoryFormAvoidsEverHandlingALinuxPath()
    {
        var arguments = WslCommandRunner.BuildExecArguments(
            "Ubuntu",
            useHomeDirectory: true,
            new[] { ".local/bin/claude" });

        Assert.Contains("--cd", arguments);
        Assert.Contains("~", arguments);
        Assert.DoesNotContain(arguments, argument => argument.StartsWith("/home/", StringComparison.Ordinal));
        Assert.DoesNotContain(arguments, argument => argument.StartsWith("/root", StringComparison.Ordinal));
    }

    [Fact]
    public void BothProbeFormsAreNonShellAndDocumented()
    {
        var forms = ClaudeWslAdapter.Invocations;

        Assert.Equal(2, forms.Count);
        // The Linux native installer's location, addressed from the home.
        Assert.Equal(".local/bin/claude", forms[0].Command);
        Assert.True(forms[0].UseHomeDirectory);
        // A package-manager install already on the default PATH.
        Assert.Equal("claude", forms[1].Command);
        Assert.False(forms[1].UseHomeDirectory);
    }

    /// <summary>
    /// wsl.exe writes UTF-16LE on most Windows builds and UTF-8 on some newer
    /// ones, so the encoding is detected rather than assumed.
    /// </summary>
    [Fact]
    public void DistributionListingIsDecodedFromEitherEncoding()
    {
        var utf16 = Encoding.Unicode.GetBytes("Ubuntu\r\nDebian\r\n");
        Assert.Equal(new[] { "Ubuntu", "Debian" }, WslCommandRunner.ParseDistributions(utf16));

        var utf8 = Encoding.UTF8.GetBytes("Ubuntu-22.04\nAlpine\n");
        Assert.Equal(new[] { "Ubuntu-22.04", "Alpine" }, WslCommandRunner.ParseDistributions(utf8));
    }

    [Fact]
    public void DistributionListingHandlesEmptyAndNoisyOutput()
    {
        Assert.Empty(WslCommandRunner.ParseDistributions(Array.Empty<byte>()));
        Assert.Empty(WslCommandRunner.ParseDistributions(Encoding.Unicode.GetBytes("\r\n\r\n")));

        // A byte-order mark must not become part of a name.
        var withBom = Encoding.Unicode.GetBytes("﻿Ubuntu\r\n");
        Assert.Equal(new[] { "Ubuntu" }, WslCommandRunner.ParseDistributions(withBom));

        // An implausibly long line is not a distribution name.
        var overlong = Encoding.UTF8.GetBytes(new string('x', 200) + "\n");
        Assert.Empty(WslCommandRunner.ParseDistributions(overlong));
    }

    [WindowsFact]
    public void AnAbsentWslReportsUnavailableRatherThanThrowing()
    {
        var runner = new WslCommandRunner(Path.Combine(Path.GetTempPath(), "usagebar-no-wsl.exe"));

        Assert.False(runner.IsInstalled);
    }

    [WindowsFact]
    public async Task AnAbsentWslIsReportedAsUnavailableByTheAdapter()
    {
        var adapter = new ClaudeWslAdapter(
            new WslCommandRunner(Path.Combine(Path.GetTempPath(), "usagebar-no-wsl.exe")));

        Assert.False(await adapter.IsAvailableAsync(CancellationToken.None));
        Assert.Equal(WslAvailability.WslUnavailable, adapter.Availability);
        Assert.Null(adapter.ResolvedDistribution);

        var result = await adapter.RunUsageQueryAsync(CancellationToken.None);
        Assert.False(result.Launched);
        Assert.Empty(result.StandardOutput);
    }

    /// <summary>
    /// Whatever the adapter reports about WSL, it must never carry a Linux path.
    /// </summary>
    [WindowsFact]
    public async Task WslDiagnosticsNeverExposeLinuxPaths()
    {
        var adapter = new ClaudeWslAdapter(
            new WslCommandRunner(Path.Combine(Path.GetTempPath(), "usagebar-no-wsl.exe")),
            configuredDistribution: "Ubuntu");

        await adapter.IsAvailableAsync(CancellationToken.None);

        var reported = $"{adapter.Availability}|{adapter.ResolvedDistribution}|{adapter.Kind}";
        foreach (var fragment in new[] { "/home/", "/root", "/mnt/", ".local/share" })
        {
            Assert.DoesNotContain(fragment, reported, StringComparison.OrdinalIgnoreCase);
        }
    }
}
