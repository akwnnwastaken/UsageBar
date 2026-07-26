using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Core.Settings;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// The pure Claude behavior: issue codes, adapter modes, provider selection with
/// two providers connected, and the settings that describe a Claude
/// installation.
/// </summary>
public sealed class ClaudeProviderPolicyTests
{
    /// <summary>
    /// Every issue must map to its own code. A missing switch arm silently fell
    /// through to "unknown" once — and the report test could not see it, because
    /// it derived its expectations from the same switch.
    /// </summary>
    [Fact]
    public void EveryIssueCodeHasAUniqueDiagnosticCode()
    {
        var codes = Enum.GetValues<ProviderIssueCode>()
            .Select(code => (Code: code, Diagnostic: new ProviderIssue(code).DiagnosticCode))
            .ToList();

        var unmapped = codes.Where(entry => entry.Diagnostic == "unknown").Select(entry => entry.Code).ToList();
        Assert.True(unmapped.Count == 0, $"Unmapped issue codes: {string.Join(", ", unmapped)}");

        var duplicates = codes
            .GroupBy(entry => entry.Diagnostic, StringComparer.Ordinal)
            .Where(group => group.Count() > 1)
            .Select(group => group.Key)
            .ToList();
        Assert.True(duplicates.Count == 0, $"Duplicate diagnostic codes: {string.Join(", ", duplicates)}");
    }

    [Fact]
    public void EveryIssueCodeIsTranslatedInBothLanguages()
    {
        var turkish = new Localizer(AppLanguage.Turkish);
        var english = new Localizer(AppLanguage.English);

        foreach (var code in Enum.GetValues<ProviderIssueCode>())
        {
            var issue = new ProviderIssue(code, "detail");
            Assert.False(string.IsNullOrWhiteSpace(turkish.Issue(issue)), $"Turkish missing for {code}");
            Assert.False(string.IsNullOrWhiteSpace(english.Issue(issue)), $"English missing for {code}");
        }
    }

    [Fact]
    public void EveryClaudeIssueCodeIsAcceptedByDiagnostics()
    {
        foreach (var code in Enum.GetValues<ProviderIssueCode>())
        {
            var diagnostic = new ProviderIssue(code).DiagnosticCode;
            Assert.Contains(diagnostic, ProviderIssue.KnownDiagnosticCodes);
            Assert.Equal(diagnostic, DiagnosticsSanitizer.SafeToken(diagnostic));
        }
    }

    [Theory]
    [InlineData(null, ClaudeAdapterMode.Automatic)]
    [InlineData("", ClaudeAdapterMode.Automatic)]
    [InlineData("nonsense", ClaudeAdapterMode.Automatic)]
    [InlineData("automatic", ClaudeAdapterMode.Automatic)]
    [InlineData("nativeWindows", ClaudeAdapterMode.NativeWindows)]
    [InlineData("wsl", ClaudeAdapterMode.Wsl)]
    public void AdapterModeResolvesWithAnAutomaticFallback(string? stored, ClaudeAdapterMode expected)
    {
        Assert.Equal(expected, ClaudeAdapterModes.Resolved(stored));
        Assert.Equal(expected, ClaudeAdapterModes.Resolved(expected.StorageValue()));
    }

    [Fact]
    public void AdapterModeControlsWhichAdaptersMayBeTried()
    {
        Assert.True(ClaudeAdapterMode.Automatic.AllowsNativeWindows());
        Assert.True(ClaudeAdapterMode.Automatic.AllowsWsl());

        Assert.True(ClaudeAdapterMode.NativeWindows.AllowsNativeWindows());
        Assert.False(ClaudeAdapterMode.NativeWindows.AllowsWsl());

        Assert.False(ClaudeAdapterMode.Wsl.AllowsNativeWindows());
        Assert.True(ClaudeAdapterMode.Wsl.AllowsWsl());
    }

    // MARK: - Settings

    [Fact]
    public void ClaudeSettingsSurviveARoundTripThroughSanitization()
    {
        var sanitized = UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            ClaudeConnected = true,
            ClaudeAdapterMode = "wsl",
            ClaudeWslDistribution = "Ubuntu-22.04",
            ClaudeLastAdapterKind = "wsl"
        });

        Assert.True(sanitized.ClaudeConnected);
        Assert.Equal("wsl", sanitized.ClaudeAdapterMode);
        Assert.Equal("Ubuntu-22.04", sanitized.ClaudeWslDistribution);
        Assert.Equal("wsl", sanitized.ClaudeLastAdapterKind);
    }

    /// <summary>
    /// A distribution name is a short identifier. Anything that looks like a
    /// path is dropped rather than stored, so a Linux or Windows path can never
    /// reach the settings file through this field.
    /// </summary>
    [Theory]
    [InlineData("/home/ahmet")]
    [InlineData(@"C:\Users\ahmet")]
    [InlineData("Ubuntu/../etc")]
    [InlineData("")]
    public void AnImplausibleWslDistributionNameIsDropped(string distribution)
    {
        var sanitized = UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            ClaudeWslDistribution = distribution
        });

        Assert.Null(sanitized.ClaudeWslDistribution);
    }

    [Fact]
    public void AnOverlongWslDistributionNameIsDropped()
    {
        var sanitized = UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            ClaudeWslDistribution = new string('x', 65)
        });

        Assert.Null(sanitized.ClaudeWslDistribution);
    }

    [Fact]
    public void AnUnsafeLastAdapterKindIsDropped()
    {
        var sanitized = UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            ClaudeLastAdapterKind = @"C:\Users\ahmet\.local\bin\claude.exe"
        });

        Assert.Null(sanitized.ClaudeLastAdapterKind);
    }

    /// <summary>
    /// A settings file written before Claude support existed must still load,
    /// with the new fields defaulted rather than the file rejected.
    /// </summary>
    [Fact]
    public void SettingsWithoutAnyClaudeFieldsStillLoad()
    {
        var sanitized = UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            CodexConnected = true,
            RefreshInterval = "twoMinutes"
        });

        Assert.True(sanitized.CodexConnected);
        Assert.False(sanitized.ClaudeConnected);
        Assert.Equal("automatic", sanitized.ClaudeAdapterMode);
        Assert.Null(sanitized.ClaudeWslDistribution);
        Assert.Equal("twoMinutes", sanitized.RefreshInterval);
    }

    // MARK: - Two connected providers

    [Fact]
    public void AutoRotationBecomesAvailableOnlyWithBothProvidersConnected()
    {
        var settings = new UsageBarSettings { CodexConnected = true, AutoRotateProviders = true };

        // One provider: rotation has nothing to rotate between.
        Assert.Single(settings.ConnectedProviderNames());
        Assert.False(ProviderConnectionTransition.AutoRotateStaysEnabled(
            settings.ConnectedProviderNames().Count,
            settings.AutoRotateProviders));

        settings.ClaudeConnected = true;
        Assert.Equal(2, settings.ConnectedProviderNames().Count);
        Assert.True(ProviderConnectionTransition.AutoRotateStaysEnabled(
            settings.ConnectedProviderNames().Count,
            settings.AutoRotateProviders));

        // And it rotates between exactly those two, every 30 seconds.
        Assert.Equal(TimeSpan.FromSeconds(30), ProviderRotation.Interval);
        Assert.Equal(ProviderNames.Codex, settings.StatusProviderName(0));
        Assert.Equal(ProviderNames.ClaudeCode, settings.StatusProviderName(1));
        Assert.Equal(ProviderNames.Codex, settings.StatusProviderName(2));
    }

    [Fact]
    public void DisconnectingClaudeKeepsCodexSelectedAndTurnsOffRotation()
    {
        var remaining = new[] { ProviderNames.Codex };

        Assert.Equal(
            ProviderNames.Codex,
            ProviderConnectionTransition.Selection(ProviderNames.ClaudeCode, remaining, ProviderNames.ClaudeCode));
        Assert.False(ProviderConnectionTransition.AutoRotateStaysEnabled(remaining.Length, wasEnabled: true));
    }

    [Fact]
    public void ClaudePrefersFiveHourAndFallsBackToWeekly()
    {
        var both = new ProviderUsage(ProviderNames.ClaudeCode, new[]
        {
            new UsageWindow(UsageWindowKind.FiveHour, 41, null, 300),
            new UsageWindow(UsageWindowKind.Weekly, 74, null, 10_080)
        }, error: null);

        Assert.Equal(
            59,
            UsageSummaryCalculator.Summary(
                ProviderNames.ClaudeCode,
                new Dictionary<string, ProviderUsage> { [ProviderNames.ClaudeCode] = both })?.RemainingPercent);

        var weeklyOnly = new ProviderUsage(ProviderNames.ClaudeCode, new[]
        {
            new UsageWindow(UsageWindowKind.Weekly, 26, null, 10_080)
        }, error: null);

        var summary = UsageSummaryCalculator.Summary(
            ProviderNames.ClaudeCode,
            new Dictionary<string, ProviderUsage> { [ProviderNames.ClaudeCode] = weeklyOnly });
        Assert.Equal(74, summary?.RemainingPercent);
        Assert.Equal(UsageWindowKind.Weekly, summary?.WindowKind);
    }

    // MARK: - Diagnostics safety

    /// <summary>
    /// Nothing about a Claude installation — a Windows path, a Linux home, a
    /// distribution's filesystem, a token — may reach diagnostics.
    /// </summary>
    [Theory]
    [InlineData(@"C:\Users\ahmet\.local\bin\claude.exe")]
    [InlineData(@"C:\Program Files\Git\bin\bash.exe")]
    [InlineData("/home/ahmet/.local/bin/claude")]
    [InlineData(@"\\wsl.localhost\Ubuntu\home\ahmet")]
    [InlineData("/mnt/c/Users/ahmet/project")]
    [InlineData("sk-ant-api03-Xy1234567890abcdefghij")]
    [InlineData("Current session: 41% used")]
    [InlineData("wsl.exe --distribution Ubuntu --exec claude -p /usage")]
    public void ClaudeSensitiveValuesNeverReachDiagnostics(string sensitive)
    {
        var report = DiagnosticsReportBuilder.Build(new DiagnosticsInput(
            AppVersion: sensitive,
            BuildId: sensitive,
            WindowsVersion: sensitive,
            OsArchitecture: sensitive,
            AppArchitecture: sensitive,
            Language: sensitive,
            LastSuccessfulRefresh: null,
            HistoryEnabled: true,
            HistorySeriesCount: 1,
            HistorySampleCount: 1,
            TrayGuidanceVersionShown: 2,
            AutoStartEnabled: false,
            Providers: new[]
            {
                new ProviderDiagnostics(
                    ProviderNames.ClaudeCode,
                    Connected: true,
                    ProviderExecutableState.Trusted,
                    ProviderAdapterKind.Wsl,
                    ProviderDataState.Fresh,
                    new[] { sensitive },
                    sensitive)
            }));

        Assert.DoesNotContain(sensitive, report, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void TheClaudeAdapterKindsAreReportedAsSafeTokens()
    {
        foreach (var kind in Enum.GetValues<ProviderAdapterKind>())
        {
            var report = DiagnosticsReportBuilder.Build(new DiagnosticsInput(
                "1.9.0", "abc1234", "10.0.22631", "x64", "x64", "english", null,
                true, 0, 0, 2, false,
                new[]
                {
                    new ProviderDiagnostics(
                        ProviderNames.ClaudeCode,
                        Connected: true,
                        ProviderExecutableState.Trusted,
                        kind,
                        ProviderDataState.Fresh,
                        Array.Empty<string>(),
                        "none")
                }));

            Assert.DoesNotContain("redacted", report, StringComparison.Ordinal);
        }
    }
}
