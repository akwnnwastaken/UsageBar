using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Core.Settings;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// What the tray shows once collection can be paused.
///
/// Three lists are deliberately kept apart and these tests exist to keep them
/// apart: the providers the user <i>manages</i>, the providers actually being
/// <i>collected</i>, and the provider the user <i>chose</i>. Conflating any two
/// of them is what would make a paused provider disappear from settings, or make
/// resuming it lose the user's own selection.
/// </summary>
public sealed class ProviderCollectionPresentationTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static readonly Localizer Turkish = new(AppLanguage.Turkish);
    private static readonly Localizer English = new(AppLanguage.English);

    private static UsageBarSettings Settings(
        bool codexConnected = true,
        bool codexCollecting = true,
        bool claudeConnected = true,
        bool claudeCollecting = true,
        string? selected = null,
        bool autoRotate = false) =>
        UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            CodexConnected = codexConnected,
            ClaudeConnected = claudeConnected,
            CodexCollectionEnabled = codexCollecting,
            ClaudeCollectionEnabled = claudeCollecting,
            SelectedProvider = selected,
            AutoRotateProviders = autoRotate
        });

    private static Dictionary<string, ProviderUsage> Usages(int remaining) =>
        new(StringComparer.Ordinal)
        {
            [ProviderNames.Codex] = new(
                ProviderNames.Codex,
                new[] { new UsageWindow(UsageWindowKind.FiveHour, 100 - remaining, null, 300) },
                error: null,
                lastSuccessfulAt: Now)
        };

    private static TrayPresentation Presentation(
        UsageBarSettings settings,
        Localizer text,
        IReadOnlyDictionary<string, ProviderUsage>? usages = null,
        bool isRefreshing = false) =>
        TrayPresentationCalculator.Calculate(
            settings.StatusProviderName(0),
            settings.ConnectedProviderNames().Count > 0,
            usages ?? new Dictionary<string, ProviderUsage>(StringComparer.Ordinal),
            new UsageAlertPolicy(true, UsageAlertPreset.Balanced),
            text,
            isRefreshing,
            showResetCountdown: false,
            Now);

    // MARK: - Connected vs eligible

    [Fact]
    public void APausedProviderStaysConnectedButStopsBeingEligible()
    {
        var settings = Settings(codexCollecting: false);

        Assert.Equal(new[] { ProviderNames.Codex, ProviderNames.ClaudeCode }, settings.ConnectedProviderNames());
        Assert.Equal(new[] { ProviderNames.ClaudeCode }, settings.EligibleProviderNames());
    }

    [Fact]
    public void ADisconnectedProviderLeavesBothLists()
    {
        var settings = Settings(codexConnected: false);

        Assert.Equal(new[] { ProviderNames.ClaudeCode }, settings.ConnectedProviderNames());
        Assert.Equal(new[] { ProviderNames.ClaudeCode }, settings.EligibleProviderNames());
    }

    // MARK: - Active provider

    [Fact]
    public void PausingTheSelectedProviderFallsThroughWithoutRewritingTheSelection()
    {
        var settings = Settings(codexCollecting: false, selected: ProviderNames.Codex);

        Assert.Equal(ProviderNames.ClaudeCode, settings.StatusProviderName(0));
        // The stored preference is untouched, which is what lets the next test
        // bring Codex back.
        Assert.Equal(ProviderNames.Codex, settings.SelectedProvider);
    }

    [Fact]
    public void ResumingTheSelectedProviderBringsItBack()
    {
        var settings = Settings(selected: ProviderNames.Codex);

        Assert.Equal(ProviderNames.Codex, settings.StatusProviderName(0));
    }

    [Fact]
    public void NothingIsActiveWhileEveryProviderIsPaused()
    {
        var settings = Settings(codexCollecting: false, claudeCollecting: false, selected: ProviderNames.Codex);

        Assert.Null(settings.StatusProviderName(0));
    }

    // MARK: - Rotation

    [Fact]
    public void RotationOnlyVisitsProvidersThatAreBeingCollected()
    {
        var settings = Settings(codexCollecting: false, autoRotate: true);

        Assert.Equal(ProviderNames.ClaudeCode, settings.StatusProviderName(0));
        Assert.Equal(ProviderNames.ClaudeCode, settings.StatusProviderName(1));
    }

    /// <summary>
    /// Pausing one of two providers makes rotation dormant. The preference is
    /// not part of that decision, so nothing rewrites it — and the moment the
    /// second provider resumes, rotation is active again.
    /// </summary>
    [Fact]
    public void RotationSleepsWhileFewerThanTwoProvidersAreEligibleAndWakesOnResume()
    {
        var paused = Settings(codexCollecting: false, autoRotate: true);
        Assert.False(paused.RotationIsActive());
        Assert.True(paused.AutoRotateProviders);

        var resumed = Settings(autoRotate: true);
        Assert.True(resumed.RotationIsActive());
        Assert.Equal(ProviderNames.Codex, resumed.StatusProviderName(0));
        Assert.Equal(ProviderNames.ClaudeCode, resumed.StatusProviderName(1));
    }

    // MARK: - Tray state

    [Fact]
    public void EverythingPausedIsItsOwnTrayStateAndNotAnInvitationToConnect()
    {
        var settings = Settings(codexCollecting: false, claudeCollecting: false);

        var english = Presentation(settings, English);
        Assert.Equal(TrayIconState.Paused, english.State);
        Assert.Equal(TrayPresentation.NoDataLabel, english.Label);
        Assert.Null(english.RemainingPercent);
        Assert.Contains("Usage collection paused", english.Tooltip, StringComparison.Ordinal);
        Assert.DoesNotContain("Connect a provider first", english.Tooltip, StringComparison.Ordinal);

        var turkish = Presentation(settings, Turkish);
        Assert.Equal(TrayIconState.Paused, turkish.State);
        Assert.Contains("Kullanım toplama duraklatıldı", turkish.Tooltip, StringComparison.Ordinal);
    }

    /// <summary>
    /// A read can still be finishing when the last provider is paused, but its
    /// result can no longer be accepted — so the icon says paused, not busy.
    /// </summary>
    [Fact]
    public void PausedWinsOverAnInFlightRefresh()
    {
        var settings = Settings(codexCollecting: false, claudeCollecting: false);

        var presentation = Presentation(settings, English, isRefreshing: true);

        Assert.Equal(TrayIconState.Paused, presentation.State);
    }

    [Fact]
    public void NothingConnectedStillAsksTheUserToConnect()
    {
        var settings = Settings(codexConnected: false, claudeConnected: false);

        var presentation = Presentation(settings, English);

        Assert.Equal(TrayIconState.NoData, presentation.State);
        Assert.Contains("Connect a provider first", presentation.Tooltip, StringComparison.Ordinal);
    }

    [Fact]
    public void ACollectingProviderStillShowsItsValue()
    {
        var settings = Settings(claudeConnected: false, selected: ProviderNames.Codex);

        var presentation = Presentation(settings, English, Usages(remaining: 42));

        Assert.Equal(TrayIconState.Normal, presentation.State);
        Assert.Equal(42, presentation.RemainingPercent);
    }

    /// <summary>
    /// Paused reuses the existing neutral dashed treatment: it is not an error,
    /// and the meaning is carried by the tooltip rather than by colour.
    /// </summary>
    [Fact]
    public void ThePausedIconUsesTheExistingNeutralTreatment()
    {
        var settings = Settings(codexCollecting: false, claudeCollecting: false);

        var glyph = TrayIconGlyph.For(Presentation(settings, English));

        Assert.Equal(TrayUnderline.Dashed, glyph.Underline);
        Assert.Equal(TrayPresentation.NoDataLabel, glyph.Text);
    }

    // MARK: - Wording

    [Fact]
    public void TheCollectionStringsAreFixedInBothLanguages()
    {
        Assert.Equal("Kullanımı topla", Turkish.CollectUsage);
        Assert.Equal("Collect usage", English.CollectUsage);
        Assert.Equal("Duraklatıldı", Turkish.Paused);
        Assert.Equal("Paused", English.Paused);
        Assert.Equal("Kullanım toplama duraklatıldı", Turkish.CollectionPaused);
        Assert.Equal("Usage collection paused", English.CollectionPaused);
    }

    // MARK: - Paused over error

    [Theory]
    [InlineData(false, true, false)]
    [InlineData(true, true, true)]
    [InlineData(true, false, false)]
    public void APausedProviderIsNotShownAsAFailingOne(
        bool collectionEnabled,
        bool hasError,
        bool expected)
    {
        Assert.Equal(expected, ProviderCollectionPolicy.RendersActiveError(collectionEnabled, hasError));
    }

    // MARK: - Recovery

    /// <summary>
    /// The path out of an all-paused state, end to end: every provider paused,
    /// the tray saying so, then one resume brings a live provider back without
    /// touching the connection or the stored selection.
    /// </summary>
    [Fact]
    public void ResumingOneProviderRecoversFromEverythingPaused()
    {
        var paused = Settings(codexCollecting: false, claudeCollecting: false, selected: ProviderNames.Codex);
        Assert.Equal(2, paused.ConnectedProviderNames().Count);
        Assert.Empty(paused.EligibleProviderNames());
        Assert.Equal(TrayIconState.Paused, Presentation(paused, English).State);

        var resumed = Settings(codexCollecting: false, selected: ProviderNames.Codex);

        Assert.Equal(new[] { ProviderNames.ClaudeCode }, resumed.EligibleProviderNames());
        Assert.Equal(ProviderNames.ClaudeCode, resumed.StatusProviderName(0));
        // Both providers are still connected, so resuming needed no reconnection
        // and the stored selection survived.
        Assert.Equal(2, resumed.ConnectedProviderNames().Count);
        Assert.Equal(ProviderNames.Codex, resumed.SelectedProvider);
    }
}
