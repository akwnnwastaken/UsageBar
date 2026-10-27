using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Core.Settings;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

public sealed class WeeklyHistoryTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    [Fact]
    public void RecordingKeepsRollingWeekAcrossSeveralWeeks()
    {
        IReadOnlyList<UsageHistorySample> samples = Array.Empty<UsageHistorySample>();
        for (var hour = 0; hour <= 21 * 24; hour++)
            samples = UsageHistoryModel.Adding(hour % 101, Now.AddHours(hour), samples, weekly: true);
        Assert.Equal(7 * 24 + 1, samples.Count);
        Assert.Equal(Now.AddDays(14), samples[0].RecordedAt);
        Assert.Equal(Now.AddDays(21), samples[^1].RecordedAt);
    }

    [Fact]
    public void RetentionBoundaryAndMiniHistoryRemainIndependent()
    {
        var input = new Dictionary<string, IReadOnlyList<UsageHistorySample>>
        {
            ["Codex|weekly"] = new[]
            {
                new UsageHistorySample(Now.AddDays(-7).AddSeconds(-1), 80),
                new UsageHistorySample(Now.AddDays(-7), 70),
                new UsageHistorySample(Now.AddDays(-2), 60), new UsageHistorySample(Now, 50)
            }
        };
        Assert.Equal(new[] { 70, 60, 50 }, UsageHistoryModel.Sanitized(input, Now, weekly: true)["Codex|weekly"].Select(s => s.RemainingPercent));
        Assert.Equal(50, Assert.Single(UsageHistoryModel.Sanitized(input, Now)["Codex|weekly"]).RemainingPercent);
        Assert.Empty(UsageHistoryModel.Sanitized(input, Now.AddDays(8), weekly: true));
    }

    [Fact]
    public void WeeklyRecordingUsesOnlyAcceptedRawOrdinaryWeeklyMeasurements()
    {
        var kinds = new[] { UsageWindowKind.FiveHour, UsageWindowKind.Weekly, UsageWindowKind.WeeklyScoped("opus"), UsageWindowKind.Duration(120), UsageWindowKind.Unknown(0) };
        var accepted = new Dictionary<string, ProviderUsage>
        {
            [ProviderNames.Codex] = new(ProviderNames.Codex, kinds.Select(k => new UsageWindow(k, 67, null, null)).ToList(), null),
            [ProviderNames.ClaudeCode] = ProviderUsage.Unavailable(ProviderNames.ClaudeCode, ProviderIssue.ClaudeUsageUnreadable)
        };
        var history = UsageHistoryRecorder.Record(new Dictionary<string, IReadOnlyList<UsageHistorySample>>(), accepted, Now, weekly: true);
        Assert.Equal("Codex|weekly", Assert.Single(history).Key);
        Assert.Equal(kinds.Length, UsageHistoryRecorder.Record(new Dictionary<string, IReadOnlyList<UsageHistorySample>>(), accepted, Now).Count);
        var noWeekly = new Dictionary<string, ProviderUsage>
        {
            [ProviderNames.Codex] = new(ProviderNames.Codex, accepted[ProviderNames.Codex].Windows.Where(w => w.Kind != UsageWindowKind.Weekly).ToList(), null)
        };
        Assert.Empty(UsageHistoryRecorder.Record(new Dictionary<string, IReadOnlyList<UsageHistorySample>>(), noWeekly, Now, weekly: true));
        Assert.All(history.Values, s => Assert.Equal(33, Assert.Single(s).RemainingPercent));
        var paused = UsageHistoryRecorder.Record(history, new Dictionary<string, ProviderUsage>(), Now.AddMinutes(2), weekly: true);
        Assert.All(history, pair => Assert.Equal(pair.Value, paused[pair.Key]));
        var replaced = UsageHistoryRecorder.Record(history, accepted, Now.AddSeconds(30), weekly: true);
        Assert.All(replaced.Values, s => Assert.Equal(Now.AddSeconds(30), Assert.Single(s).RecordedAt));
    }

    [Fact]
    public void WeeklyChartIncludesResetsAndMiniChartKeepsLatestPeriod()
    {
        var samples = new[] { 33, 34, 33, 20, 100, 60, 10, 95, 80 }.Select((v, i) => new UsageHistorySample(Now.AddHours(i), v)).ToList();
        var model = new UsageHistoryChartModel(samples, startsAtLatestReset: false);
        Assert.Equal(samples, model.Samples);
        Assert.Equal(new[] { 33, 33, 33, 20, 100, 60, 10, 95, 80 }, model.DisplaySamples.Select(s => s.RemainingPercent));
        Assert.Equal(0, model.LowerBound);
        Assert.Equal(100, model.UpperBound);
        Assert.Equal(TimeSpan.FromHours(8), model.RecordedDuration);
        Assert.Equal(100, model.NearestDisplaySample(0.5)?.RemainingPercent);
        Assert.Equal(new[] { 95, 80 }, new UsageHistoryChartModel(samples).DisplaySamples.Select(s => s.RemainingPercent));
        Assert.Empty(new UsageHistoryChartModel(Array.Empty<UsageHistorySample>(), false).DisplaySamples);
    }

    [Fact]
    public void FullCapacityWeeklyHistorySurvivesReload()
    {
        var samples = Enumerable.Range(0, UsageHistoryModel.WeeklyMaximumSamplesPerSeries).Select(i => new UsageHistorySample(Now.AddMinutes(-i), i % 101)).Reverse().ToList();
        var input = Enumerable.Range(0, UsageHistoryModel.MaximumSeries).ToDictionary(i => $"Codex|unknown-{i}", _ => (IReadOnlyList<UsageHistorySample>)samples);
        var bytes = UsageHistoryModel.Encode(input)!;
        Assert.InRange(bytes.Length, UsageHistoryModel.MaximumEncodedBytes + 1, UsageHistoryModel.WeeklyMaximumEncodedBytes);
        var loaded = UsageHistoryModel.Decode(bytes, weekly: true);
        Assert.All(input, pair => Assert.Equal(pair.Value, loaded[pair.Key]));
        Assert.Empty(UsageHistoryModel.Decode(bytes));
        Assert.Empty(UsageHistoryModel.Decode("invalid"u8.ToArray(), weekly: true));
    }

    [Fact]
    public void SelectedReadingSurvivesAppendsAndClampsAfterRetention()
    {
        var samples = new[] { 80, 70, 60 }.Select((value, i) => new UsageHistorySample(Now.AddHours(i), value)).ToList();
        var model = new UsageHistoryChartModel(samples, false);
        Assert.Equal(0, model.SelectionIndex(Now));
        Assert.Equal(1, model.SelectionIndex(Now.AddHours(1)));
        Assert.Equal(2, model.SelectionIndex(null));
        samples.Add(new UsageHistorySample(Now.AddHours(3), 50));
        model = new UsageHistoryChartModel(samples, false);
        Assert.Equal(1, model.SelectionIndex(Now.AddHours(1)));
        Assert.Equal(3, model.SelectionIndex(null));
        Assert.Equal(0, model.SelectionIndex(Now.AddHours(0.5)));
        Assert.Equal(3, model.SelectionIndex(Now.AddDays(1)));
        Assert.Equal(0, new UsageHistoryChartModel(samples.Skip(2).ToList(), false).SelectionIndex(Now));
        Assert.Equal(0, new UsageHistoryChartModel(Array.Empty<UsageHistorySample>(), false).SelectionIndex(Now));
    }

    [Fact]
    public void RecordingIsOptInAndLabelsAreLocalized()
    {
        Assert.False(UsageBarSettingsSanitizer.Sanitize(null).WeeklyHistoryEnabled);
        Assert.True(UsageBarSettingsSanitizer.Sanitize(new UsageBarSettings { WeeklyHistoryEnabled = true }).WeeklyHistoryEnabled);
        var tr = new Localizer(AppLanguage.Turkish);
        var en = new Localizer(AppLanguage.English);
        Assert.Equal("Sağlayıcı", tr.HistorySeries);
        Assert.Equal("Provider", en.HistorySeries);
        Assert.NotEqual(tr.RecordWeeklyHistory, en.RecordWeeklyHistory);
        Assert.NotEqual(tr.WeeklyHistoryHelp, en.WeeklyHistoryHelp);
    }
}
