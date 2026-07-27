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
    public void HoverReturnsNullForAnEmptySeries()
    {
        var empty = new UsageHistoryChartModel(Array.Empty<UsageHistorySample>());

        Assert.Null(empty.NearestDisplaySample(0));
        Assert.Null(empty.NearestDisplaySample(0.5));
        Assert.Null(empty.NearestDisplaySample(1));
    }

    [Fact]
    public void HoverAlwaysReturnsTheOnlySample()
    {
        var single = new UsageHistoryChartModel(Series(42));

        foreach (var normalizedX in new[] { 0, 0.5, 1, -3, 4 })
        {
            Assert.Equal(42, single.NearestDisplaySample(normalizedX)?.RemainingPercent);
        }
    }

    [Fact]
    public void HoverSelectsTheEndsAndClampsBeyondThem()
    {
        var model = new UsageHistoryChartModel(Series(50, 46, 44));

        Assert.Equal(50, model.NearestDisplaySample(0)?.RemainingPercent);
        Assert.Equal(44, model.NearestDisplaySample(1)?.RemainingPercent);
        // Outside the plot the position clamps rather than wrapping or throwing.
        Assert.Equal(50, model.NearestDisplaySample(-0.4)?.RemainingPercent);
        Assert.Equal(50, model.NearestDisplaySample(-1_000)?.RemainingPercent);
        Assert.Equal(44, model.NearestDisplaySample(1.4)?.RemainingPercent);
        Assert.Equal(44, model.NearestDisplaySample(1_000)?.RemainingPercent);
    }

    /// <summary>
    /// Documented non-finite behaviour: NaN and negative infinity select the
    /// beginning, positive infinity the end.
    /// </summary>
    [Fact]
    public void HoverHandlesNonFiniteInputDeterministically()
    {
        var model = new UsageHistoryChartModel(Series(50, 46, 44));

        Assert.Equal(50, model.NearestDisplaySample(double.NaN)?.RemainingPercent);
        Assert.Equal(50, model.NearestDisplaySample(double.NegativeInfinity)?.RemainingPercent);
        Assert.Equal(44, model.NearestDisplaySample(double.PositiveInfinity)?.RemainingPercent);
    }

    /// <summary>
    /// Samples are not evenly spaced in time, so the nearest one must be found
    /// by timestamp. Index-based interpolation would answer 40 at a quarter of
    /// the way across.
    /// </summary>
    [Fact]
    public void HoverSelectsByTimestampNotArrayIndex()
    {
        var model = new UsageHistoryChartModel(new[]
        {
            new UsageHistorySample(Base, 50),
            new UsageHistorySample(Base.AddSeconds(3_540), 40),
            new UsageHistorySample(Base.AddSeconds(3_560), 39),
            new UsageHistorySample(Base.AddSeconds(3_600), 38)
        });

        Assert.Equal(50, model.NearestDisplaySample(0.25)?.RemainingPercent);
        Assert.Equal(50, model.NearestDisplaySample(0.4)?.RemainingPercent);
        Assert.Equal(40, model.NearestDisplaySample(0.9)?.RemainingPercent);
    }

    /// <summary>
    /// A position exactly between two records picks the earlier one, and no
    /// position ever invents the 47 that sits between 48 and 46.
    /// </summary>
    [Fact]
    public void HoverBreaksTiesTowardsTheEarlierSampleAndNeverInterpolates()
    {
        var model = new UsageHistoryChartModel(new[]
        {
            new UsageHistorySample(Base, 48),
            new UsageHistorySample(Base.AddSeconds(300), 46)
        });

        var middle = model.NearestDisplaySample(0.5);
        Assert.Equal(48, middle?.RemainingPercent);
        Assert.Equal(Base, middle?.RecordedAt);
        // Just past the midpoint the later record wins.
        Assert.Equal(46, model.NearestDisplaySample(0.51)?.RemainingPercent);

        for (var step = -20; step <= 120; step++)
        {
            var selected = model.NearestDisplaySample(step / 100.0);
            Assert.NotNull(selected);
            Assert.Contains(selected!.RemainingPercent, new[] { 48, 46 });
        }
    }

    [Fact]
    public void HoverCannotSelectSamplesBeforeTheLatestReset()
    {
        var model = new UsageHistoryChartModel(Series(80, 50, 30, 100, 90, 70));

        Assert.Equal(new[] { 100, 90, 70 }, model.DisplaySamples.Select(sample => sample.RemainingPercent));
        Assert.Equal(100, model.NearestDisplaySample(0)?.RemainingPercent);

        // Sweeping the whole plot only ever reports drawn samples.
        for (var step = -20; step <= 120; step++)
        {
            var selected = model.NearestDisplaySample(step / 100.0);
            Assert.NotNull(selected);
            Assert.Contains(selected!, model.DisplaySamples);
        }
    }

    /// <summary>
    /// The hover value must agree with the visible line, so the flattened
    /// display value is reported for an isolated one-point spike.
    /// </summary>
    [Fact]
    public void HoverReportsTheFlattenedDisplayValueNotRawNoise()
    {
        var model = new UsageHistoryChartModel(Series(33, 34, 33));

        Assert.Equal(new[] { 33, 34, 33 }, model.Samples.Select(sample => sample.RemainingPercent));
        var middle = model.NearestDisplaySample(0.5);
        Assert.Equal(Base.AddSeconds(120), middle?.RecordedAt);
        Assert.Equal(33, middle?.RemainingPercent);
    }

    /// <summary>
    /// Duplicate timestamps give a zero-length window: the first drawn sample
    /// answers every position, and nothing divides by zero.
    /// </summary>
    [Fact]
    public void HoverWithDuplicateTimestampsIsDeterministic()
    {
        var duplicates = new UsageHistoryChartModel(new[]
        {
            new UsageHistorySample(Base, 50),
            new UsageHistorySample(Base, 44)
        });

        Assert.Equal(TimeSpan.Zero, duplicates.RecordedDuration);
        var expected = duplicates.DisplaySamples[0];
        foreach (var normalizedX in new[] { 0, 0.25, 0.5, 1, -2, 3 })
        {
            Assert.Equal(expected, duplicates.NearestDisplaySample(normalizedX));
        }
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
