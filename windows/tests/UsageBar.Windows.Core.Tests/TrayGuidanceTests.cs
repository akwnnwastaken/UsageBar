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

    /// <summary>
    /// The wording changed after physical testing, so the current version is 2
    /// and everyone — including someone who already saw version 1 — must see the
    /// corrected text exactly once.
    /// </summary>
    [Fact]
    public void TheCurrentGuidanceVersionIsTwo()
    {
        Assert.Equal(2, TrayGuidancePolicy.CurrentGuidanceVersion);
    }

    [Theory]
    [InlineData(null, true)]   // never shown
    [InlineData(0, true)]      // recorded before any guidance existed
    [InlineData(1, true)]      // saw the old "next to the clock" wording
    [InlineData(2, false)]     // already saw the corrected wording
    [InlineData(3, false)]     // a settings file from a future build
    public void AutomaticGuidanceFollowsTheStoredVersion(int? stored, bool expected)
    {
        Assert.Equal(expected, TrayGuidancePolicy.ShouldShowAutomatically(stored, currentVersion: 2));
    }

    [Fact]
    public void NewerStoredVersionIsNeitherDowngradedNorReshown()
    {
        Assert.False(TrayGuidancePolicy.ShouldShowAutomatically(3, currentVersion: 2));
        Assert.Equal(3, TrayGuidancePolicy.VersionAfterShowing(3, currentVersion: 2));

        Assert.False(TrayGuidancePolicy.ShouldShowAutomatically(5, currentVersion: 1));
        Assert.Equal(5, TrayGuidancePolicy.VersionAfterShowing(5, currentVersion: 1));
    }

    [Fact]
    public void ManualReshowAlwaysShows()
    {
        Assert.True(TrayGuidancePolicy.ShouldShowManually());
    }

    [Theory]
    [InlineData(null, 2)]
    [InlineData(0, 2)]
    [InlineData(1, 2)]
    [InlineData(2, 2)]
    public void ShowingRecordsTheCurrentVersion(int? stored, int expected)
    {
        Assert.Equal(expected, TrayGuidancePolicy.VersionAfterShowing(stored, currentVersion: 2));
    }

    /// <summary>
    /// Showing version 2 once must settle: the very next check must not ask for
    /// it again.
    /// </summary>
    [Fact]
    public void GuidanceShownOnceIsNotShownAutomaticallyAgain()
    {
        int? stored = 1;

        Assert.True(TrayGuidancePolicy.ShouldShowAutomatically(stored));
        stored = TrayGuidancePolicy.VersionAfterShowing(stored);

        Assert.Equal(TrayGuidancePolicy.CurrentGuidanceVersion, stored);
        Assert.False(TrayGuidancePolicy.ShouldShowAutomatically(stored));
        // The manual action still works afterwards.
        Assert.True(TrayGuidancePolicy.ShouldShowManually());
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
            "UsageBar simgesi ^ menüsünde gizliyse simgeyi görev çubuğundaki görünür sistem tepsisi alanına taşıyın.",
            turkish.TrayGuidanceBody);
        Assert.Equal("Sistem tepsisi yönlendirmesini yeniden göster", turkish.ShowTrayGuidanceAgain);
        Assert.Equal(
            "Windows Ayarlar > Kişiselleştirme > Görev Çubuğu > Diğer sistem tepsisi simgeleri",
            turkish.TrayGuidanceSettingsPath);

        Assert.Equal("Keep UsageBar visible", english.TrayGuidanceTitle);
        Assert.Equal(
            "If UsageBar is hidden under ^, move its icon to the visible system tray area on the taskbar.",
            english.TrayGuidanceBody);
        Assert.Equal("Show system tray guidance again", english.ShowTrayGuidanceAgain);
        Assert.Equal(
            "Windows Settings > Personalization > Taskbar > Other system tray icons",
            english.TrayGuidanceSettingsPath);
    }

    /// <summary>
    /// The corrected wording must not promise a position Windows controls.
    /// Physical testing showed the icon landing beside the `^` button rather
    /// than beside the clock, which is normal and must not read as a failure.
    /// </summary>
    [Fact]
    public void GuidanceDoesNotPromiseAPositionWindowsControls()
    {
        var turkish = new Localizer(AppLanguage.Turkish);
        var english = new Localizer(AppLanguage.English);

        Assert.DoesNotContain("saat yanına", turkish.TrayGuidanceBody, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("next to the clock", english.TrayGuidanceBody, StringComparison.OrdinalIgnoreCase);

        // Both point at the visible tray area instead.
        Assert.Contains("görünür sistem tepsisi", turkish.TrayGuidanceBody, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("visible system tray area", english.TrayGuidanceBody, StringComparison.OrdinalIgnoreCase);

        // The detailed text may mention the clock, but only to say the position
        // is not guaranteed.
        Assert.Contains("yeterlidir", turkish.TrayGuidanceDetail, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("is sufficient", english.TrayGuidanceDetail, StringComparison.OrdinalIgnoreCase);
    }
}
