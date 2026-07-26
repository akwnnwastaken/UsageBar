using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Core.Providers;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

public sealed class DiagnosticsTests
{
    /// <summary>Strings that must never reach a diagnostics summary.</summary>
    public static TheoryData<string> SensitiveValues() => new()
    {
        @"C:\Users\ahmed\AppData\Local\Programs\codex\codex.exe",
        @"\\fileserver\share\codex.exe",
        "/home/ahmed/.local/bin/claude",
        "%LOCALAPPDATA%\\UsageBar",
        "sk-ant-api03-Xy1234567890abcdefghijklmnop",
        "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
        "password=hunter2",
        "https://api.anthropic.com/v1/messages",
        "codex app-server --stdio --disable apps",
        "C:\\Projects\\secret-client\\src",
        "ANTHROPIC_API_KEY=abcdef"
    };

    private static DiagnosticsInput Input(
        string? issueCode = null,
        string? appVersion = null,
        string? windowsVersion = null,
        IReadOnlyList<string>? windowKinds = null,
        string? buildId = null) =>
        new(
            AppVersion: appVersion ?? "1.9.0",
            BuildId: buildId ?? "0a48c1e",
            WindowsVersion: windowsVersion ?? "10.0.22631",
            OsArchitecture: "X64",
            AppArchitecture: "X64",
            Language: "turkish",
            LastSuccessfulRefresh: DateTimeOffset.FromUnixTimeSeconds(1_800_000_000),
            HistoryEnabled: true,
            HistorySeriesCount: 3,
            HistorySampleCount: 120,
            TrayGuidanceVersionShown: 1,
            AutoStartEnabled: false,
            Providers: new[]
            {
                new ProviderDiagnostics(
                    ProviderNames.Codex,
                    Connected: true,
                    ProviderExecutableState.Trusted,
                    ProviderAdapterKind.NativeExecutable,
                    ProviderDataState.Fresh,
                    windowKinds ?? new[] { "five-hour", "weekly" },
                    issueCode ?? "none"),
                new ProviderDiagnostics(
                    ProviderNames.ClaudeCode,
                    Connected: true,
                    ProviderExecutableState.UnsupportedInstallation,
                    ProviderAdapterKind.Wsl,
                    ProviderDataState.Stale,
                    Array.Empty<string>(),
                    "claude_usage_timed_out")
            });

    [Fact]
    public void ReportContainsOnlySafeFacts()
    {
        var report = DiagnosticsReportBuilder.Build(Input());

        Assert.Contains("UsageBar 1.9.0", report, StringComparison.Ordinal);
        Assert.Contains("build=0a48c1e", report, StringComparison.Ordinal);
        Assert.Contains("windows=10.0.22631", report, StringComparison.Ordinal);
        Assert.Contains("os_arch=X64", report, StringComparison.Ordinal);
        Assert.Contains("language=turkish", report, StringComparison.Ordinal);
        Assert.Contains("last_refresh=2027-01-15T08:00:00Z", report, StringComparison.Ordinal);
        Assert.Contains("history_enabled=true", report, StringComparison.Ordinal);
        Assert.Contains("tray_guidance_version=1", report, StringComparison.Ordinal);
        Assert.Contains("autostart=false", report, StringComparison.Ordinal);
        Assert.Contains(
            "codex=connected:true,executable:trusted,adapter:native_exe,state:fresh,windows:five-hour+weekly,issue:none",
            report,
            StringComparison.Ordinal);
        Assert.Contains(
            "claude=connected:true,executable:unsupported_installation,adapter:wsl,state:stale,windows:none,issue:claude_usage_timed_out",
            report,
            StringComparison.Ordinal);
    }

    [Theory]
    [MemberData(nameof(SensitiveValues))]
    public void SensitiveValuesNeverAppearInTheReport(string sensitive)
    {
        var report = DiagnosticsReportBuilder.Build(Input(
            issueCode: sensitive,
            appVersion: sensitive,
            windowsVersion: sensitive,
            windowKinds: new[] { sensitive },
            buildId: sensitive));

        Assert.DoesNotContain(sensitive, report, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(DiagnosticsSanitizer.Redacted, report, StringComparison.Ordinal);
    }

    [Fact]
    public void UnknownIssueCodesAreRedactedRatherThanEchoed()
    {
        var report = DiagnosticsReportBuilder.Build(Input(issueCode: "totally_made_up"));

        Assert.DoesNotContain("totally_made_up", report, StringComparison.Ordinal);
        Assert.Contains("issue:redacted", report, StringComparison.Ordinal);
    }

    [Fact]
    public void EveryKnownIssueCodeSurvivesTheReport()
    {
        foreach (var code in ProviderIssue.KnownDiagnosticCodes)
        {
            var report = DiagnosticsReportBuilder.Build(Input(issueCode: code));
            Assert.Contains($"issue:{code}", report, StringComparison.Ordinal);
        }
    }

    [Theory]
    [InlineData(null, DiagnosticsSanitizer.None)]
    [InlineData("", DiagnosticsSanitizer.None)]
    [InlineData("   ", DiagnosticsSanitizer.None)]
    [InlineData("native_exe", "native_exe")]
    [InlineData("1.9.0", "1.9.0")]
    [InlineData("five-hour", "five-hour")]
    [InlineData(@"C:\Windows", DiagnosticsSanitizer.Redacted)]
    [InlineData("has space", DiagnosticsSanitizer.Redacted)]
    [InlineData("key=value", DiagnosticsSanitizer.Redacted)]
    [InlineData("a,b", DiagnosticsSanitizer.Redacted)]
    public void SanitizerClassifiesTokens(string? value, string expected)
    {
        Assert.Equal(expected, DiagnosticsSanitizer.SafeToken(value));
    }

    [Fact]
    public void OverlongTokensAreRedacted()
    {
        var overlong = new string('a', DiagnosticsSanitizer.MaximumTokenLength + 1);
        Assert.Equal(DiagnosticsSanitizer.Redacted, DiagnosticsSanitizer.SafeToken(overlong));
    }
}
