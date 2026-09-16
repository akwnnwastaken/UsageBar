using System.Text.Json;
using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Core.Settings;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// Per-provider detail visibility: what it stores, and what it is not allowed
/// to touch.
///
/// The feature is one preference and one rendering decision, so most of these
/// tests are about <i>absence</i> — the things that must go on behaving exactly
/// as they did when the preference did not exist. A hidden provider is still
/// collected, still eligible, still selectable, still rotated through, still
/// speaks for the tray and still keeps every sample it recorded.
/// </summary>
public sealed class ProviderDetailVisibilityTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static readonly Localizer Turkish = new(AppLanguage.Turkish);
    private static readonly Localizer English = new(AppLanguage.English);

    private static UsageBarSettings Settings(
        bool codexConnected = true,
        bool codexCollecting = true,
        bool? codexDetails = null,
        bool claudeConnected = true,
        bool claudeCollecting = true,
        bool? claudeDetails = null,
        string? selected = null,
        bool autoRotate = false) =>
        UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings
        {
            CodexConnected = codexConnected,
            ClaudeConnected = claudeConnected,
            CodexCollectionEnabled = codexCollecting,
            ClaudeCollectionEnabled = claudeCollecting,
            CodexDetailsVisible = codexDetails,
            ClaudeDetailsVisible = claudeDetails,
            SelectedProvider = selected,
            AutoRotateProviders = autoRotate
        });

    // MARK: - Stored preference

    [Fact]
    public void AnAbsentPreferenceMeansTheDetailsAreVisible()
    {
        // The upgrade case: every build through 2.0.1 wrote neither field, and a
        // non-nullable bool would default to false and collapse every card.
        var raw = new UsageBarSettings();
        Assert.Null(raw.CodexDetailsVisible);
        Assert.Null(raw.ClaudeDetailsVisible);

        var sanitized = UsageBarSettingsSanitizer.Sanitize(raw);

        Assert.True(sanitized.CodexDetailsVisible);
        Assert.True(sanitized.ClaudeDetailsVisible);
        Assert.True(sanitized.AreDetailsVisible(ProviderNames.Codex));
        Assert.True(sanitized.AreDetailsVisible(ProviderNames.ClaudeCode));
    }

    [Fact]
    public void AnExplicitFalseSurvivesSanitizing()
    {
        var settings = Settings(codexDetails: false, claudeDetails: false);

        Assert.False(settings.CodexDetailsVisible);
        Assert.False(settings.ClaudeDetailsVisible);
        Assert.False(settings.AreDetailsVisible(ProviderNames.Codex));
        Assert.False(settings.AreDetailsVisible(ProviderNames.ClaudeCode));
    }

    [Fact]
    public void AnExplicitTrueSurvivesSanitizing()
    {
        var settings = Settings(codexDetails: true, claudeDetails: true);

        Assert.True(settings.CodexDetailsVisible);
        Assert.True(settings.ClaudeDetailsVisible);
    }

    [Fact]
    public void EachProviderKeepsItsOwnPreference()
    {
        var settings = Settings(codexDetails: false, claudeDetails: true);

        Assert.False(settings.AreDetailsVisible(ProviderNames.Codex));
        Assert.True(settings.AreDetailsVisible(ProviderNames.ClaudeCode));
    }

    [Fact]
    public void CloningPreservesBothValues()
    {
        var settings = Settings(codexDetails: false, claudeDetails: true);

        var clone = settings.Clone();

        Assert.False(clone.CodexDetailsVisible);
        Assert.True(clone.ClaudeDetailsVisible);
        Assert.False(clone.AreDetailsVisible(ProviderNames.Codex));
    }

    [Fact]
    public void TheStoredNamesAreTheOnesTheDocumentUses()
    {
        var json = JsonSerializer.Serialize(Settings(codexDetails: false, claudeDetails: true));

        Assert.Contains("\"codexDetailsVisible\":false", json, StringComparison.Ordinal);
        Assert.Contains("\"claudeDetailsVisible\":true", json, StringComparison.Ordinal);
    }

    /// <summary>
    /// Restart persistence: the document round-trips, so what the user chose is
    /// what the next launch reads. The collection fields are asserted alongside
    /// to prove one did not overwrite the other on the way through.
    /// </summary>
    [Fact]
    public void TheStoredChoiceSurvivesARoundTrip()
    {
        var written = JsonSerializer.Serialize(Settings(
            codexCollecting: false,
            codexDetails: false,
            claudeCollecting: true,
            claudeDetails: true));

        var reloaded = UsageBarSettingsSanitizer.Sanitize(
            JsonSerializer.Deserialize<UsageBarSettings>(written));

        Assert.False(reloaded.AreDetailsVisible(ProviderNames.Codex));
        Assert.True(reloaded.AreDetailsVisible(ProviderNames.ClaudeCode));
        Assert.False(reloaded.IsCollectionEnabled(ProviderNames.Codex));
        Assert.True(reloaded.IsCollectionEnabled(ProviderNames.ClaudeCode));
    }

    /// <summary>
    /// A document written by 2.0.1 — collection fields present, detail fields
    /// absent — must load with its pauses intact and its cards visible.
    /// </summary>
    [Fact]
    public void AnUpgradedDocumentKeepsItsPausesAndShowsItsCards()
    {
        const string stored = """
        {"schemaVersion":1,"codexConnected":true,"claudeConnected":true,
         "codexCollectionEnabled":false,"claudeCollectionEnabled":true}
        """;

        var loaded = UsageBarSettingsSanitizer.Sanitize(
            JsonSerializer.Deserialize<UsageBarSettings>(stored));

        Assert.False(loaded.IsCollectionEnabled(ProviderNames.Codex));
        Assert.True(loaded.AreDetailsVisible(ProviderNames.Codex));
        Assert.True(loaded.AreDetailsVisible(ProviderNames.ClaudeCode));
    }

    // MARK: - The two preferences are independent

    [Fact]
    public void PausingAProviderDoesNotHideItsDetails()
    {
        var settings = Settings(codexCollecting: false, claudeCollecting: false);

        Assert.True(settings.AreDetailsVisible(ProviderNames.Codex));
        Assert.True(settings.AreDetailsVisible(ProviderNames.ClaudeCode));
    }

    [Fact]
    public void HidingTheDetailsDoesNotPauseCollection()
    {
        var settings = Settings(codexDetails: false, claudeDetails: false);

        Assert.True(settings.IsCollectionEnabled(ProviderNames.Codex));
        Assert.True(settings.IsCollectionEnabled(ProviderNames.ClaudeCode));
    }

    [Fact]
    public void TheFourCombinationsAreAllRepresentable()
    {
        Assert.True(Settings(codexCollecting: true, codexDetails: true)
            .AreDetailsVisible(ProviderNames.Codex));
        Assert.False(Settings(codexCollecting: true, codexDetails: false)
            .AreDetailsVisible(ProviderNames.Codex));
        Assert.True(Settings(codexCollecting: false, codexDetails: true)
            .AreDetailsVisible(ProviderNames.Codex));
        Assert.False(Settings(codexCollecting: false, codexDetails: false)
            .AreDetailsVisible(ProviderNames.Codex));
    }

    // MARK: - Card plan

    private static ProviderCardPlan Plan(
        bool collecting = true,
        bool visible = true,
        bool issue = false) =>
        ProviderDetailPresentationPolicy.Card(collecting, visible, issue);

    [Fact]
    public void AVisibleCollectingProviderKeepsItsFullBody()
    {
        var plan = Plan();

        Assert.True(plan.ShowsDetailBody);
        Assert.False(plan.ShowsPausedMarker);
        Assert.False(plan.ShowsOperationalIssue);
    }

    [Fact]
    public void HidingTheDetailsOmitsTheWholeBodyAndNothingElse()
    {
        // Every usage row, reset line, history summary and chart lives in the
        // body, so one decision removes all of them together — and the heading
        // is not part of it.
        var plan = Plan(visible: false);

        Assert.False(plan.ShowsDetailBody);
        Assert.False(plan.ShowsPausedMarker);
    }

    [Fact]
    public void AHiddenPausedProviderKeepsItsPausedMarker()
    {
        var plan = Plan(collecting: false, visible: false);

        Assert.True(plan.ShowsPausedMarker);
        Assert.False(plan.ShowsDetailBody);
    }

    [Fact]
    public void APausedProviderWithVisibleDetailsStillShowsThem()
    {
        // Unchanged 2.0.1 behaviour: a pause retains and keeps showing what was
        // last read.
        var plan = Plan(collecting: false, visible: true);

        Assert.True(plan.ShowsPausedMarker);
        Assert.True(plan.ShowsDetailBody);
    }

    [Fact]
    public void AHiddenProviderStillReportsAnActiveCollectionFailure()
    {
        var plan = Plan(visible: false, issue: true);

        Assert.True(plan.ShowsOperationalIssue);
        Assert.False(plan.ShowsDetailBody);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void APausedProviderIsStillNotBlamedForItsRetainedError(bool visible)
    {
        Assert.False(Plan(collecting: false, visible: visible, issue: true).ShowsOperationalIssue);
    }

    [Fact]
    public void NeitherPreferenceMovesTheOthersPartOfThePlan()
    {
        Assert.False(Plan(collecting: true, visible: true).ShowsPausedMarker);
        Assert.False(Plan(collecting: true, visible: false).ShowsPausedMarker);
        Assert.True(Plan(collecting: false, visible: true).ShowsPausedMarker);
        Assert.True(Plan(collecting: false, visible: false).ShowsPausedMarker);

        Assert.True(Plan(collecting: true, visible: true).ShowsDetailBody);
        Assert.True(Plan(collecting: false, visible: true).ShowsDetailBody);
        Assert.False(Plan(collecting: true, visible: false).ShowsDetailBody);
        Assert.False(Plan(collecting: false, visible: false).ShowsDetailBody);
    }

    [Fact]
    public void TheDetailStringIsFixedInBothLanguages()
    {
        Assert.Equal("Ayrıntıları göster", Turkish.ShowDetails);
        Assert.Equal("Show details", English.ShowDetails);

        // It is not the collection control wearing a different label.
        Assert.NotEqual(Turkish.CollectUsage, Turkish.ShowDetails);
        Assert.NotEqual(English.CollectUsage, English.ShowDetails);
    }

    // MARK: - Collection, status and rotation are untouched

    [Fact]
    public void AHiddenProviderIsStillConnectedAndStillEligible()
    {
        var settings = Settings(codexDetails: false, claudeDetails: false);

        Assert.Equal(
            new[] { ProviderNames.Codex, ProviderNames.ClaudeCode },
            settings.ConnectedProviderNames());
        Assert.Equal(
            new[] { ProviderNames.Codex, ProviderNames.ClaudeCode },
            settings.EligibleProviderNames());
    }

    [Fact]
    public void AHiddenProviderStillDrivesTheTray()
    {
        var settings = Settings(codexDetails: false, selected: ProviderNames.Codex);

        Assert.Equal(ProviderNames.Codex, settings.StatusProviderName(0));
    }

    [Fact]
    public void HidingTheDetailsLeavesTheStoredSelectionAlone()
    {
        var settings = Settings(codexDetails: false, selected: ProviderNames.Codex);

        Assert.Equal(ProviderNames.Codex, settings.SelectedProvider);
    }

    [Fact]
    public void RotationStillVisitsAHiddenProvider()
    {
        var settings = Settings(
            codexDetails: false,
            claudeDetails: false,
            autoRotate: true);

        Assert.True(settings.RotationIsActive());
        Assert.Equal(ProviderNames.Codex, settings.StatusProviderName(0));
        Assert.Equal(ProviderNames.ClaudeCode, settings.StatusProviderName(1));
    }

    [Fact]
    public void TheTrayStillShowsAHiddenProvidersValue()
    {
        var settings = Settings(codexDetails: false, claudeConnected: false, selected: ProviderNames.Codex);
        var usages = new Dictionary<string, ProviderUsage>(StringComparer.Ordinal)
        {
            [ProviderNames.Codex] = new(
                ProviderNames.Codex,
                new[] { new UsageWindow(UsageWindowKind.FiveHour, 58, null, 300) },
                error: null,
                lastSuccessfulAt: Now)
        };

        var presentation = TrayPresentationCalculator.Calculate(
            settings.StatusProviderName(0),
            settings.ConnectedProviderNames().Count > 0,
            usages,
            new UsageAlertPolicy(true, UsageAlertPreset.Balanced),
            English,
            isRefreshing: false,
            showResetCountdown: false,
            Now);

        // The compact card shows no percentage; the tray still shows 42%.
        Assert.Equal(TrayIconState.Normal, presentation.State);
        Assert.Equal(42, presentation.RemainingPercent);
    }

    [Fact]
    public void EverythingPausedIsStillItsOwnStateWhateverTheCardsShow()
    {
        var settings = Settings(
            codexCollecting: false,
            claudeCollecting: false,
            codexDetails: false,
            claudeDetails: true);

        Assert.Empty(settings.EligibleProviderNames());
        Assert.Equal(2, settings.ConnectedProviderNames().Count);
        Assert.Null(settings.StatusProviderName(0));
    }

    // MARK: - History and cache survive

    private static IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> Recorded(int steps)
    {
        IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> history =
            new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal);

        for (var step = 0; step < steps; step++)
        {
            var at = Now.AddMinutes(step * 10);
            var measurement = new Dictionary<string, ProviderUsage>(StringComparer.Ordinal)
            {
                [ProviderNames.Codex] = new(
                    ProviderNames.Codex,
                    new[] { new UsageWindow(UsageWindowKind.Weekly, 40 + step, null, 10_080) },
                    error: null,
                    lastSuccessfulAt: at)
            };

            history = UsageHistoryRecorder.Record(history, measurement, at);
        }

        return history;
    }

    [Fact]
    public void HidingTheDetailsNeitherDeletesNorGapsTheSeries()
    {
        // Recording is driven by the measurements a cycle accepted. Nothing in
        // that path can see the presentation preference, so the series a hidden
        // provider records is the series a visible one would.
        var key = UsageHistoryModel.SeriesKey(ProviderNames.Codex, UsageWindowKind.Weekly);
        var history = Recorded(3);

        Assert.Equal(new[] { 60, 59, 58 }, history[key].Select(sample => sample.RemainingPercent));

        // Showing the card again finds the whole retained arc, not one that
        // restarted when the body came back.
        var model = new UsageHistoryChartModel(history[key]);
        Assert.Equal(3, model.DisplaySamples.Count);
        Assert.Equal(60, model.DisplaySamples[0].RemainingPercent);
        Assert.Equal(58, model.DisplaySamples[^1].RemainingPercent);
    }

    [Fact]
    public void RetentionIsUnchangedByTheDetailPreference()
    {
        var key = UsageHistoryModel.SeriesKey(ProviderNames.Codex, UsageWindowKind.Weekly);
        var before = Recorded(3);

        var after = UsageHistoryModel.Sanitized(before, Now.AddMinutes(20));

        Assert.Equal(before[key].Count, after[key].Count);
        Assert.Equal(
            before[key].Select(sample => sample.RemainingPercent),
            after[key].Select(sample => sample.RemainingPercent));
    }
}
