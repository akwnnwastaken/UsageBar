using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Settings;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// First-run tray visibility guidance. UsageBar explains how to drag its icon
/// out of the overflow menu exactly once per guidance version, and never tries
/// to pin itself.
/// </summary>
public sealed class TrayGuidanceTests
{
    [Fact]
    public void NoStoredVersionShowsGuidance()
    {
        Assert.True(TrayGuidancePolicy.ShouldShowAutomatically(null));
    }

    [Fact]
    public void StoredVersionEqualToCurrentDoesNotShowGuidance()
    {
        Assert.False(TrayGuidancePolicy.ShouldShowAutomatically(TrayGuidancePolicy.CurrentGuidanceVersion));
    }

    [Fact]
    public void OlderStoredVersionShowsGuidanceAgain()
    {
        Assert.True(TrayGuidancePolicy.ShouldShowAutomatically(1, currentVersion: 2));
    }

    [Fact]
    public void NewerStoredVersionIsNeitherDowngradedNorReshown()
    {
        Assert.False(TrayGuidancePolicy.ShouldShowAutomatically(5, currentVersion: 1));
        Assert.Equal(5, TrayGuidancePolicy.VersionAfterShowing(5, currentVersion: 1));
    }

    [Fact]
    public void ManualReshowAlwaysShows()
    {
        Assert.True(TrayGuidancePolicy.ShouldShowManually());
    }

    [Fact]
    public void ShowingRecordsTheCurrentVersion()
    {
        Assert.Equal(1, TrayGuidancePolicy.VersionAfterShowing(null, currentVersion: 1));
        Assert.Equal(2, TrayGuidancePolicy.VersionAfterShowing(1, currentVersion: 2));
    }

    /// <summary>
    /// Recording the guidance version must not disturb anything else in the
    /// settings document — not the provider connections, not the history
    /// toggle, not the language or the refresh interval.
    /// </summary>
    [Fact]
    public void RecordingGuidanceLeavesEveryOtherSettingUntouched()
    {
        var settings = UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            CodexConnected = true,
            ClaudeConnected = true,
            SelectedProvider = "Claude Code",
            AutoRotateProviders = true,
            Language = "turkish",
            RefreshInterval = "oneMinute",
            UsageHistoryEnabled = false,
            UsageColorsEnabled = false,
            UsageAlertPreset = "early"
        });

        var updated = settings.Clone();
        updated.TrayGuidanceVersionShown =
            TrayGuidancePolicy.VersionAfterShowing(settings.TrayGuidanceVersionShown);

        Assert.Equal(TrayGuidancePolicy.CurrentGuidanceVersion, updated.TrayGuidanceVersionShown);
        Assert.True(updated.CodexConnected);
        Assert.True(updated.ClaudeConnected);
        Assert.Equal("Claude Code", updated.SelectedProvider);
        Assert.True(updated.AutoRotateProviders);
        Assert.Equal("turkish", updated.Language);
        Assert.Equal("oneMinute", updated.RefreshInterval);
        Assert.False(updated.UsageHistoryEnabled);
        Assert.False(updated.UsageColorsEnabled);
        Assert.Equal("early", updated.UsageAlertPreset);
    }

    [Fact]
    public void GuidanceTextIsProvidedInBothLanguages()
    {
        var turkish = new Localizer(AppLanguage.Turkish);
        var english = new Localizer(AppLanguage.English);

        Assert.Equal("UsageBar'ı görünür tutun", turkish.TrayGuidanceTitle);
        Assert.Equal(
            "UsageBar simgesini sürekli görmek için görev çubuğundaki ^ simgesini açıp UsageBar'ı saat yanına sürükleyin.",
            turkish.TrayGuidanceBody);
        Assert.Equal("Sistem tepsisi yönlendirmesini yeniden göster", turkish.ShowTrayGuidanceAgain);

        Assert.Equal("Keep UsageBar visible", english.TrayGuidanceTitle);
        Assert.Equal(
            "To keep UsageBar visible, open the ^ menu on the taskbar and drag UsageBar next to the clock.",
            english.TrayGuidanceBody);
        Assert.Equal("Show system tray guidance again", english.ShowTrayGuidanceAgain);
    }
}
