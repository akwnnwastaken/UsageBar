using System.Runtime.Versioning;
using Microsoft.Win32;
using UsageBar.Windows.Infrastructure.Diagnostics;
using UsageBar.Windows.Infrastructure.Startup;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// Auto-start through the current user's Run key: never elevated, never
/// touching another application's entry.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class AutoStartTests
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    private const string UnrelatedValueName = "UsageBarTestUnrelatedApp";

    [Theory]
    [InlineData(@"""C:\Program Files\UsageBar\UsageBar.exe""", @"C:\Program Files\UsageBar\UsageBar.exe")]
    [InlineData(@"C:\Tools\UsageBar.exe", @"C:\Tools\UsageBar.exe")]
    [InlineData(@"C:\Tools\UsageBar.exe --minimized", @"C:\Tools\UsageBar.exe")]
    [InlineData(@"""C:\My Tools\UsageBar.exe"" --minimized", @"C:\My Tools\UsageBar.exe")]
    public void TheProgramPathIsExtractedFromAStoredCommandLine(string stored, string expected)
    {
        Assert.Equal(expected, RegistryAutoStartService.ExtractProgramPath(stored));
    }

    [Fact]
    public void TheCommandLineQuotesTheExecutablePath()
    {
        var service = new RegistryAutoStartService(@"C:\Program Files\UsageBar\UsageBar.exe");

        Assert.Equal(@"""C:\Program Files\UsageBar\UsageBar.exe""", service.CommandLine);
    }

    [Fact]
    public void AStaleEntryPointingElsewhereIsDetected()
    {
        var service = new RegistryAutoStartService(@"C:\Tools\UsageBar.exe");

        Assert.True(service.PointsAtThisExecutable(@"""C:\Tools\UsageBar.exe"""));
        Assert.True(service.PointsAtThisExecutable(@"C:\Tools\usagebar.exe"));
        Assert.False(service.PointsAtThisExecutable(@"C:\Old\UsageBar.exe"));
    }

    /// <summary>
    /// Exercises the real registry under the current user. Enabling, reading and
    /// disabling must round-trip, and an unrelated startup entry created
    /// alongside must survive untouched.
    /// </summary>
    [WindowsFact]
    public void EnableAndDisableOnlyAffectUsageBarsOwnEntry()
    {
        var executable = Path.Combine(Path.GetTempPath(), "UsageBarAutoStartTest.exe");
        var service = new RegistryAutoStartService(executable);

        using (var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true))
        {
            Assert.NotNull(key);
            key!.SetValue(UnrelatedValueName, @"C:\Other\App.exe", RegistryValueKind.String);
        }

        try
        {
            var initial = service.GetState();
            Assert.Equal(AutoStartStatus.Disabled, initial.Status);

            var enabled = service.Enable();
            Assert.Equal(AutoStartStatus.Enabled, enabled.Status);
            Assert.True(enabled.IsOn);
            Assert.False(enabled.LastOperationFailed);

            var disabled = service.Disable();
            Assert.Equal(AutoStartStatus.Disabled, disabled.Status);
            Assert.False(disabled.IsOn);

            // Disabling twice is harmless.
            Assert.Equal(AutoStartStatus.Disabled, service.Disable().Status);

            using var check = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
            Assert.Equal(@"C:\Other\App.exe", check?.GetValue(UnrelatedValueName));
        }
        finally
        {
            service.Disable();
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
            key?.DeleteValue(UnrelatedValueName, throwOnMissingValue: false);
        }
    }

    [WindowsFact]
    public void AnEntryForADifferentPathIsReportedRatherThanSilentlyOverwritten()
    {
        var service = new RegistryAutoStartService(Path.Combine(Path.GetTempPath(), "UsageBarCurrent.exe"));

        using (var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true))
        {
            key!.SetValue("UsageBar", @"""C:\Somewhere\Else\UsageBar.exe""", RegistryValueKind.String);
        }

        try
        {
            var state = service.GetState();
            Assert.Equal(AutoStartStatus.EnabledForDifferentPath, state.Status);
            Assert.True(state.IsOn);
        }
        finally
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
            key?.DeleteValue("UsageBar", throwOnMissingValue: false);
        }
    }

    [WindowsFact]
    public void EnvironmentFactsAreSafeToPutInDiagnostics()
    {
        Assert.Matches(@"^\d+(\.\d+)*$", WindowsEnvironmentInfo.Version);
        Assert.Matches(@"^[a-z0-9]+$", WindowsEnvironmentInfo.OsArchitecture);
        Assert.Matches(@"^[a-z0-9]+$", WindowsEnvironmentInfo.ProcessArchitecture);
        Assert.Matches(@"^\d+\.\d+\.\d+$", WindowsEnvironmentInfo.ApplicationVersion);

        // No user or machine identity leaks through these.
        foreach (var value in new[]
                 {
                     WindowsEnvironmentInfo.Version,
                     WindowsEnvironmentInfo.OsArchitecture,
                     WindowsEnvironmentInfo.ProcessArchitecture,
                     WindowsEnvironmentInfo.ApplicationVersion
                 })
        {
            Assert.DoesNotContain(Environment.UserName, value, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain(Environment.MachineName, value, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain(@"\", value, StringComparison.Ordinal);
        }
    }
}
