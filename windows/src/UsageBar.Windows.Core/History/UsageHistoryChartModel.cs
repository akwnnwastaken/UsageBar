namespace UsageBar.Windows.Core.History;

/// <summary>
/// Presentation model for the mini history chart.
///
/// A window's remaining percentage only falls until the window resets (a large
/// upward jump back toward ~100%). To make each period a distinct, readable arc,
/// the chart begins at the most recent reset instead of spanning the whole
/// retained history. Isolated one-point noise (33 → 34 → 33) is flattened for
/// drawing only; <see cref="Samples"/> stays raw.
/// </summary>
public sealed class UsageHistoryChartModel
{
    public const int ResetJumpThreshold = 20;

    public const double MinimumVerticalSpan = 10.0;

    public UsageHistoryChartModel(IReadOnlyList<UsageHistorySample> samples)
    {
        ArgumentNullException.ThrowIfNull(samples);

        var sorted = samples.OrderBy(sample => sample.RecordedAt).ToList();
        Samples = sorted;

        var windowStart = 0;
        for (var index = 1; index < sorted.Count; index++)
        {
            if (sorted[index].RemainingPercent - sorted[index - 1].RemainingPercent >= ResetJumpThreshold)
            {
                windowStart = index;
            }
        }

        var windowSamples = sorted.GetRange(windowStart, sorted.Count - windowStart);
        var display = new List<UsageHistorySample>(windowSamples.Count);
        for (var index = 0; index < windowSamples.Count; index++)
        {
            var sample = windowSamples[index];
            if (index == 0 || index == windowSamples.Count - 1)
            {
                display.Add(sample);
                continue;
            }

            var previous = windowSamples[index - 1].RemainingPercent;
            var current = sample.RemainingPercent;
            var next = windowSamples[index + 1].RemainingPercent;
            display.Add(previous == next && Math.Abs(current - previous) == 1
                ? new UsageHistorySample(sample.RecordedAt, previous)
                : sample);
        }

        DisplaySamples = display;

        var values = display.Select(sample => (double)Math.Clamp(sample.RemainingPercent, 0, 100)).ToList();
        var minimum = values.Count > 0 ? values.Min() : 0;
        var maximum = values.Count > 0 ? values.Max() : 100;
        var rawSpan = maximum - minimum;
        var padding = Math.Max(2, rawSpan * 0.15);
        var desiredSpan = Math.Max(MinimumVerticalSpan, rawSpan + (padding * 2));
        var lower = Math.Floor((minimum + maximum - desiredSpan) / 2);
        var upper = Math.Ceiling((minimum + maximum + desiredSpan) / 2);

        if (lower < 0)
        {
            upper = Math.Min(100, upper - lower);
            lower = 0;
        }

        if (upper > 100)
        {
            lower = Math.Max(0, lower - (upper - 100));
            upper = 100;
        }

        if (upper <= lower)
        {
            lower = 0;
            upper = 100;
        }

        LowerBound = lower;
        UpperBound = upper;
    }

    /// <summary>Every retained sample, unmodified.</summary>
    public IReadOnlyList<UsageHistorySample> Samples { get; }

    /// <summary>The samples actually drawn: current reset arc, noise flattened.</summary>
    public IReadOnlyList<UsageHistorySample> DisplaySamples { get; }

    public double LowerBound { get; }

    public double UpperBound { get; }

    /// <summary>Duration of the shown window (since the last reset), not the full history.</summary>
    public TimeSpan RecordedDuration
    {
        get
        {
            if (DisplaySamples.Count == 0)
            {
                return TimeSpan.Zero;
            }

            var span = DisplaySamples[^1].RecordedAt - DisplaySamples[0].RecordedAt;
            return span < TimeSpan.Zero ? TimeSpan.Zero : span;
        }
    }

    /// <summary>Net change across the shown window, or null when there is a single point.</summary>
    public int? Delta =>
        DisplaySamples.Count > 1
            ? DisplaySamples[^1].RemainingPercent - DisplaySamples[0].RemainingPercent
            : null;

    /// <summary>0 at the bottom of the plotted range, 1 at the top.</summary>
    public double NormalizedY(int remainingPercent)
    {
        var clamped = (double)Math.Clamp(remainingPercent, 0, 100);
        return (clamped - LowerBound) / (UpperBound - LowerBound);
    }

    /// <summary>
    /// The recorded sample nearest a horizontal position on the chart, for
    /// pointer hover.
    /// </summary>
    /// <param name="normalizedX">
    /// The pointer's progress across the plot rectangle: 0 is the left edge and
    /// 1 the right edge. Finite values are clamped into 0...1. NaN and negative
    /// infinity select the beginning; positive infinity selects the end.
    /// </param>
    /// <returns>
    /// A sample from <see cref="DisplaySamples"/>, or <c>null</c> when nothing
    /// is drawn.
    /// </returns>
    /// <remarks>
    /// The search runs over <see cref="DisplaySamples"/> — the exact line drawn,
    /// i.e. the current reset arc with isolated one-point noise flattened — so
    /// the value shown above the graph always agrees with the visible line.
    /// Selection is by <see cref="UsageHistorySample.RecordedAt"/>, not array
    /// index, because samples are not evenly spaced in time. Nothing is
    /// interpolated: the answer is always a real recorded sample. Two samples
    /// equally far from the target resolve to the earlier one.
    /// </remarks>
    public UsageHistorySample? NearestDisplaySample(double normalizedX)
    {
        if (DisplaySamples.Count == 0)
        {
            return null;
        }

        var first = DisplaySamples[0];
        if (DisplaySamples.Count == 1)
        {
            return first;
        }

        var durationSeconds = RecordedDuration.TotalSeconds;
        if (durationSeconds <= 0)
        {
            return first;
        }

        // Math.Clamp maps ±infinity onto the ends but returns NaN unchanged, so
        // NaN is decided first and deliberately selects the beginning.
        var progress = double.IsNaN(normalizedX) ? 0 : Math.Clamp(normalizedX, 0, 1);
        var target = first.RecordedAt.AddSeconds(durationSeconds * progress);

        var nearest = first;
        var nearestDistance = Math.Abs((target - first.RecordedAt).TotalSeconds);

        // DisplaySamples is sorted ascending and only a strictly smaller
        // distance replaces the current best, so an exact tie keeps the earlier
        // sample.
        for (var index = 1; index < DisplaySamples.Count; index++)
        {
            var candidate = DisplaySamples[index];
            var distance = Math.Abs((target - candidate.RecordedAt).TotalSeconds);
            if (distance < nearestDistance)
            {
                nearest = candidate;
                nearestDistance = distance;
            }
        }

        return nearest;
    }
}
