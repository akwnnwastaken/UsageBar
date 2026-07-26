using UsageBar.Windows.Core.Policies;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// Parity with the macOS display filter. The observed sequences are the ones the
/// Swift tests assert, so both platforms hide the same noise.
/// </summary>
public sealed class UsageDisplayNoiseFilterTests
{
    private static int[] Rendered(params int[] rawSamples)
    {
        int? displayed = null;
        int? pendingRise = null;
        var pendingCount = 0;

        return rawSamples.Select(raw =>
        {
            var decision = UsageDisplayNoiseFilter.Decide(raw, displayed, pendingRise, pendingCount);
            displayed = decision.Displayed;
            pendingRise = decision.PendingRise;
            pendingCount = decision.PendingCount;
            return decision.Displayed;
        }).ToArray();
    }

    [Fact]
    public void FirstReadingIsDisplayedAsIs()
    {
        Assert.Equal(
            new UsageDisplayNoiseFilter.Decision(42, null, 0),
            UsageDisplayNoiseFilter.Decide(42, null, null, 0));
    }

    [Fact]
    public void DecreasesAndResetJumpsPassThroughUnchanged()
    {
        Assert.Equal(new[] { 90, 80, 60, 59, 10 }, Rendered(90, 80, 60, 59, 10));
        Assert.Equal(new[] { 4, 100, 98 }, Rendered(4, 100, 98));
    }

    [Fact]
    public void StaleSnapshotReboundIsHeld()
    {
        var screen = Rendered(33, 38, 33);
        Assert.Equal(new[] { 33, 33, 33 }, screen);
        Assert.DoesNotContain(screen.Zip(screen.Skip(1)), pair => pair.Second > pair.First);

        // The same higher value repeated is accepted as a real rise.
        Assert.Equal(new[] { 33, 33, 33, 38 }, Rendered(33, 38, 38, 38));
    }

    [Fact]
    public void RiseHoldThresholdBoundary()
    {
        Assert.Equal(12, UsageDisplayNoiseFilter.RiseHoldThreshold);
        Assert.Equal(new[] { 50, 62 }, Rendered(50, 62));
        Assert.Equal(new[] { 50, 50, 50 }, Rendered(50, 61, 50));
    }

    [Fact]
    public void ObservedRoundingOscillationNeverRisesOnScreen()
    {
        var screen = Rendered(42, 41, 42, 42, 40);
        Assert.Equal(new[] { 42, 41, 41, 41, 40 }, screen);
        Assert.DoesNotContain(screen.Zip(screen.Skip(1)), pair => pair.Second > pair.First);

        Assert.Equal(new[] { 52, 51, 51 }, Rendered(52, 51, 52));
    }

    [Fact]
    public void SustainedRiseIsAcceptedAfterThirdReading()
    {
        Assert.Equal(3, UsageDisplayNoiseFilter.RisePersistenceThreshold);
        Assert.Equal(new[] { 41, 41, 41, 42, 42 }, Rendered(41, 42, 42, 42, 42));
    }

    [Fact]
    public void InterruptedRiseRestartsThePersistenceCount()
    {
        Assert.Equal(new[] { 41, 41, 41, 41, 41 }, Rendered(41, 42, 41, 42, 42));
    }
}
