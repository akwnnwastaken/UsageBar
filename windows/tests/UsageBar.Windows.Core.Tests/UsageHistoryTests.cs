using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Providers;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

public sealed class UsageHistoryTests
{
    private static readonly DateTimeOffset Base = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static IReadOnlyList<UsageHistorySample> Series(params int[] values) =>
        values.Select((value, index) =>
            new UsageHistorySample(Base.AddSeconds(index * 120), value)).ToList();

    [Fact]
    public void RetainsWindowAndEnforcesMinimumInterval()
    {
        var samples = UsageHistoryModel.Adding(50, Base, Array.Empty<UsageHistorySample>());

        // Within one minute the last sample is replaced rather than appended.
        samples = UsageHistoryModel.Adding(49, Base.AddSeconds(30), samples);
        Assert.Single(samples);
        Assert.Equal(49, samples[^1].RemainingPercent);

        samples = UsageHistoryModel.Adding(48, Base.AddSeconds(120), samples);
        Assert.Equal(2, samples.Count);

        // Anything older than 24 hours is dropped.
        samples = UsageHistoryModel.Adding(40, Base.AddHours(25), samples);
        Assert.Single(samples);
        Assert.Equal(40, samples[^1].RemainingPercent);
    }

    [Fact]
    public void SanitizeClampsValuesDropsFutureSamplesAndCapsSeries()
    {
        var history = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
        {
            ["Codex|weekly"] = new[]
            {
                new UsageHistorySample(Base.AddSeconds(-120), 140),
                new UsageHistorySample(Base.AddSeconds(-90), -20),
                new UsageHistorySample(Base.AddSeconds(120), 50)
            },
            [new string('k', UsageHistoryModel.MaximumSeriesKeyLength + 1)] = Series(10, 20)
        };

        var sanitized = UsageHistoryModel.Sanitized(history, Base);

        // The two samples inside the same minute collapse to the newest, clamped.
        Assert.Single(sanitized["Codex|weekly"]);
        Assert.Equal(0, sanitized["Codex|weekly"][0].RemainingPercent);
        // A sample more than a minute in the future is dropped, and an
        // over-long series key is refused entirely.
        Assert.Single(sanitized);
    }

    [Fact]
    public void SanitizeCapsTheNumberOfSeries()
    {
        var history = Enumerable.Range(0, UsageHistoryModel.MaximumSeries + 5)
            .ToDictionary(index => $"Provider{index:D2}|weekly", _ => Series(50), StringComparer.Ordinal);

        var sanitized = UsageHistoryModel.Sanitized(
            history.ToDictionary(entry => entry.Key, entry => entry.Value, StringComparer.Ordinal),
            Base);

        Assert.Equal(UsageHistoryModel.MaximumSeries, sanitized.Count);
    }

    [Fact]
    public void DecodeRejectsOversizedTruncatedAndMalformedData()
    {
        Assert.Empty(UsageHistoryModel.Decode(new byte[UsageHistoryModel.MaximumEncodedBytes + 1]));
        Assert.Empty(UsageHistoryModel.Decode("not json"u8.ToArray()));
        Assert.Empty(UsageHistoryModel.Decode("""{"Codex|weekly":[{"recordedAt":"2026-0"""u8.ToArray()));
        Assert.Empty(UsageHistoryModel.Decode(null));
        Assert.Empty(UsageHistoryModel.Decode(Array.Empty<byte>()));
    }

    [Fact]
    public void EncodeAndDecodeRoundTrip()
    {
        var history = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
        {
            ["Codex|five-hour"] = Series(90, 80, 70)
        };

        var decoded = UsageHistoryModel.Decode(UsageHistoryModel.Encode(history));

        Assert.Equal(
            history["Codex|five-hour"].Select(sample => sample.RemainingPercent),
            decoded["Codex|five-hour"].Select(sample => sample.RemainingPercent));
        Assert.Equal(
            history["Codex|five-hour"][0].RecordedAt,
            decoded["Codex|five-hour"][0].RecordedAt);
    }

    [Fact]
    public void ChartFlattensIsolatedNoiseButKeepsRawSamples()
    {
        var noisy = new UsageHistoryChartModel(Series(33, 34, 33));

        Assert.Equal(new[] { 33, 33, 33 }, noisy.DisplaySamples.Select(sample => sample.RemainingPercent));
        Assert.Equal(new[] { 33, 34, 33 }, noisy.Samples.Select(sample => sample.RemainingPercent));
        Assert.Equal(-8, new UsageHistoryChartModel(Series(50, 45, 42)).Delta);
    }

    [Fact]
    public void ChartRestartsAtTheMostRecentReset()
    {
        var single = new UsageHistoryChartModel(Series(30, 12, 95));
        Assert.Equal(new[] { 95 }, single.DisplaySamples.Select(sample => sample.RemainingPercent));
        Assert.Null(single.Delta);
        Assert.Equal(new[] { 30, 12, 95 }, single.Samples.Select(sample => sample.RemainingPercent));

        var windowed = new UsageHistoryChartModel(Series(80, 50, 30, 100, 90, 70));
        Assert.Equal(new[] { 100, 90, 70 }, windowed.DisplaySamples.Select(sample => sample.RemainingPercent));
        Assert.Equal(-30, windowed.Delta);

        var twoResets = new UsageHistoryChartModel(Series(90, 40, 100, 60, 20, 95, 80));
        Assert.Equal(new[] { 95, 80 }, twoResets.DisplaySamples.Select(sample => sample.RemainingPercent));
        Assert.Equal(-15, twoResets.Delta);
    }

    [Fact]
    public void ChartUsesAnAdaptiveVerticalRange()
    {
        var flat = new UsageHistoryChartModel(Series(33));
        Assert.Equal(28, flat.LowerBound);
        Assert.Equal(38, flat.UpperBound);
        Assert.Equal(0.5, flat.NormalizedY(33), 6);

        var high = new UsageHistoryChartModel(Series(99, 100));
        Assert.True(high.UpperBound <= 100);
        Assert.True(high.LowerBound >= 0);
        Assert.True(high.UpperBound > high.LowerBound);

        var low = new UsageHistoryChartModel(Series(0, 1));
        Assert.Equal(0, low.LowerBound);
        Assert.True(low.UpperBound > low.LowerBound);
    }

    [Fact]
    public void ChartHandlesAnEmptySeries()
    {
        var empty = new UsageHistoryChartModel(Array.Empty<UsageHistorySample>());

        Assert.Empty(empty.DisplaySamples);
        Assert.Null(empty.Delta);
        Assert.Equal(TimeSpan.Zero, empty.RecordedDuration);
    }

    [Fact]
    public void RecorderStoresRawValuesForEverySuccessfulWindow()
    {
        var usages = new Dictionary<string, ProviderUsage>(StringComparer.Ordinal)
        {
            [ProviderNames.Codex] = new(ProviderNames.Codex, new[]
            {
                new UsageWindow(UsageWindowKind.FiveHour, 35, null, 300),
                new UsageWindow(UsageWindowKind.Weekly, 12, null, 10_080)
            }, error: null)
        };

        var history = UsageHistoryRecorder.Record(
            new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal),
            usages,
            new[] { ProviderNames.Codex },
            Base);

        Assert.Equal(65, history["Codex|five-hour"][0].RemainingPercent);
        Assert.Equal(88, history["Codex|weekly"][0].RemainingPercent);
    }

    /// <summary>
    /// A failed refresh keeps the previous value on screen but must not add a
    /// new sample: the chart would otherwise show a flat line that never
    /// happened.
    /// </summary>
    [Fact]
    public void RecorderIgnoresStaleReadings()
    {
        var previous = new ProviderUsage(
            ProviderNames.Codex,
            new[] { new UsageWindow(UsageWindowKind.FiveHour, 35, null, 300) },
            error: null,
            lastSuccessfulAt: Base);
        var stale = ProviderUsage.Stale(previous, ProviderIssue.CodexTimedOut);

        var history = UsageHistoryRecorder.Record(
            new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
            {
                ["Codex|five-hour"] = Series(65)
            },
            new Dictionary<string, ProviderUsage>(StringComparer.Ordinal) { [ProviderNames.Codex] = stale },
            new[] { ProviderNames.Codex },
            Base.AddMinutes(5));

        Assert.Single(history["Codex|five-hour"]);
        Assert.True(stale.IsStale);
    }

    [Fact]
    public void RemovingAProviderOnlyDropsThatProvidersSeries()
    {
        var history = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
        {
            ["Codex|weekly"] = Series(50),
            ["Claude Code|weekly"] = Series(60)
        };

        var trimmed = UsageHistoryRecorder.RemovingProvider(history, ProviderNames.Codex);

        Assert.False(trimmed.ContainsKey("Codex|weekly"));
        Assert.True(trimmed.ContainsKey("Claude Code|weekly"));
    }
}
