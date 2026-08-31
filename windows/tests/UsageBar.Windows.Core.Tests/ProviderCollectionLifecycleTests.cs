using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// The runtime rules of a collection pause, in the same shape macOS asserts
/// them: what a refresh reads, which finished reads it still accepts, and what
/// a cycle is allowed to treat as a measurement.
/// </summary>
public sealed class ProviderCollectionLifecycleTests
{
    private static readonly DateTimeOffset Base = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static readonly string CodexWeekly =
        UsageHistoryModel.SeriesKey(ProviderNames.Codex, UsageWindowKind.Weekly);

    private static readonly string ClaudeWeekly =
        UsageHistoryModel.SeriesKey(ProviderNames.ClaudeCode, UsageWindowKind.Weekly);

    private static Dictionary<string, ProviderUsage> Measurement(string providerName, int remaining) =>
        new(StringComparer.Ordinal)
        {
            [providerName] = new ProviderUsage(
                providerName,
                new[] { new UsageWindow(UsageWindowKind.Weekly, 100 - remaining, null, 10_080) },
                error: null,
                lastSuccessfulAt: Base)
        };

    // MARK: - Refresh plan

    [Theory]
    [InlineData(true, true, ProviderCollectionAction.Collect)]
    [InlineData(true, false, ProviderCollectionAction.RetainCache)]
    [InlineData(false, true, ProviderCollectionAction.DropCache)]
    [InlineData(false, false, ProviderCollectionAction.DropCache)]
    public void OnlyAnEligibleProviderIsReadAndOnlyADisconnectedOneLosesItsCache(
        bool connected,
        bool collectionEnabled,
        ProviderCollectionAction expected)
    {
        Assert.Equal(expected, ProviderCollectionPolicy.Action(connected, collectionEnabled));
    }

    [Fact]
    public void ACycleWithNothingToReadCollectsNothing()
    {
        Assert.False(ProviderCollectionPolicy.CollectsUsage(Array.Empty<ProviderCollectionAction>()));
        Assert.False(ProviderCollectionPolicy.CollectsUsage(new[]
        {
            ProviderCollectionAction.RetainCache,
            ProviderCollectionAction.DropCache
        }));
        Assert.True(ProviderCollectionPolicy.CollectsUsage(new[]
        {
            ProviderCollectionAction.RetainCache,
            ProviderCollectionAction.Collect
        }));
    }

    // MARK: - Acceptance

    [Theory]
    [InlineData(true, true, 3, 3, true)]
    [InlineData(false, true, 3, 3, false)]
    [InlineData(true, false, 3, 3, false)]
    [InlineData(true, true, 2, 3, false)]
    [InlineData(false, false, 3, 3, false)]
    public void AResultIsAcceptedOnlyWhileItsProviderIsUnchangedAndEligible(
        bool connected,
        bool collectionEnabled,
        int launchGeneration,
        int currentGeneration,
        bool expected)
    {
        Assert.Equal(
            expected,
            ProviderCollectionPolicy.ShouldAccept(
                connected,
                collectionEnabled,
                launchGeneration,
                currentGeneration));
    }

    /// <summary>
    /// Disconnect → reconnect while a read is in flight. Both bumps land before
    /// the old result returns, so the provider is fully eligible again by then:
    /// eligibility alone would accept a reading of an account the user has
    /// since reconnected, out of order with the newer one.
    /// </summary>
    [Fact]
    public void ReconnectingDoesNotMakeAnInFlightResultCurrentAgain()
    {
        var generation = 4;
        var launchGeneration = generation;

        generation++; // disconnect
        generation++; // reconnect

        Assert.False(ProviderCollectionPolicy.ShouldAccept(true, true, launchGeneration, generation));
        Assert.True(ProviderCollectionPolicy.ShouldAccept(true, true, generation, generation));
    }

    /// <summary>The same race through pause → resume.</summary>
    [Fact]
    public void ResumingDoesNotMakeAnInFlightResultCurrentAgain()
    {
        var generation = 9;
        var launchGeneration = generation;

        generation++; // pause
        generation++; // resume

        Assert.False(ProviderCollectionPolicy.ShouldAccept(true, true, launchGeneration, generation));
    }

    // MARK: - Coalescing

    [Fact]
    public void ResumingWhileIdleCollectsStraightAway()
    {
        var pending = default(PendingCollectionRefresh);

        Assert.True(pending.RequestCollection(isRefreshing: false));
        // Nothing was deferred, so no follow-up is owed.
        Assert.False(pending.Consume());
    }

    [Fact]
    public void ResumingDuringARefreshOwesExactlyOneFollowUp()
    {
        var pending = default(PendingCollectionRefresh);

        Assert.False(pending.RequestCollection(isRefreshing: true));
        Assert.False(pending.RequestCollection(isRefreshing: true));
        Assert.False(pending.RequestCollection(isRefreshing: true));

        Assert.True(pending.Consume());
        // Consuming empties the slot, so the follow-up cannot re-arm itself.
        Assert.False(pending.Consume());
    }

    [Fact]
    public void AConsumedFollowUpCanBeArmedAgainByANewResume()
    {
        var pending = default(PendingCollectionRefresh);

        Assert.False(pending.RequestCollection(isRefreshing: true));
        Assert.True(pending.Consume());

        Assert.False(pending.RequestCollection(isRefreshing: true));
        Assert.True(pending.Consume());
    }

    // MARK: - Display filter

    /// <summary>
    /// The frozen counterexample. Codex is displaying 33, reads 38 once, and
    /// the filter holds that rise until three consecutive readings confirm it.
    /// If another provider's refreshes could re-feed the cached 38, a rise
    /// needing three measurements would be accepted after two.
    /// </summary>
    [Fact]
    public void AHeldRiseDoesNotAdvanceWhileTheProviderIsPaused()
    {
        var state = new UsageDisplayState();
        state.Advance(Measurement(ProviderNames.Codex, 33));
        state.Advance(Measurement(ProviderNames.Codex, 38));

        Assert.Equal(33, state.Apply(Measurement(ProviderNames.Codex, 38))[ProviderNames.Codex].Windows[0].RemainingPercent);

        // Codex is paused. Three Claude-only cycles follow: the accepted set
        // never contains Codex, so nothing about Codex may move.
        for (var cycle = 0; cycle < 3; cycle++)
        {
            state.Advance(Measurement(ProviderNames.ClaudeCode, 70 - cycle));
        }

        Assert.Equal(33, state.Apply(Measurement(ProviderNames.Codex, 38))[ProviderNames.Codex].Windows[0].RemainingPercent);
    }

    [Fact]
    public void PausingClearsTheHeldRiseButKeepsWhatIsOnScreen()
    {
        var state = new UsageDisplayState();
        state.Advance(Measurement(ProviderNames.Codex, 33));
        state.Advance(Measurement(ProviderNames.Codex, 38));

        state.ClearPendingRise(ProviderNames.Codex);

        // Still showing 33 — the pause kept it.
        Assert.Equal(33, state.Apply(Measurement(ProviderNames.Codex, 38))[ProviderNames.Codex].Windows[0].RemainingPercent);

        // And persistence restarts from scratch: two more readings are not
        // enough, the third is.
        state.Advance(Measurement(ProviderNames.Codex, 38));
        state.Advance(Measurement(ProviderNames.Codex, 38));
        Assert.Equal(33, state.Apply(Measurement(ProviderNames.Codex, 38))[ProviderNames.Codex].Windows[0].RemainingPercent);

        state.Advance(Measurement(ProviderNames.Codex, 38));
        Assert.Equal(38, state.Apply(Measurement(ProviderNames.Codex, 38))[ProviderNames.Codex].Windows[0].RemainingPercent);
    }

    [Fact]
    public void PausingOneProviderLeavesTheOtherAlone()
    {
        var state = new UsageDisplayState();
        state.Advance(Measurement(ProviderNames.ClaudeCode, 70));
        state.Advance(Measurement(ProviderNames.ClaudeCode, 75));

        state.ClearPendingRise(ProviderNames.Codex);

        // Claude's held rise survived, so its third reading still confirms it.
        state.Advance(Measurement(ProviderNames.ClaudeCode, 75));
        state.Advance(Measurement(ProviderNames.ClaudeCode, 75));
        Assert.Equal(
            75,
            state.Apply(Measurement(ProviderNames.ClaudeCode, 75))[ProviderNames.ClaudeCode].Windows[0].RemainingPercent);
    }

    // MARK: - History

    [Fact]
    public void AnAcceptedMeasurementBecomesASample()
    {
        var history = UsageHistoryRecorder.Record(
            new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal),
            Measurement(ProviderNames.Codex, 60),
            Base);

        Assert.Single(history[CodexWeekly]);
        Assert.Equal(60, history[CodexWeekly][0].RemainingPercent);
    }

    [Fact]
    public void ACycleThatAcceptedNothingRecordsNothing()
    {
        var existing = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
        {
            [CodexWeekly] = new[] { new UsageHistorySample(Base, 60) }
        };

        var history = UsageHistoryRecorder.Record(
            existing,
            new Dictionary<string, ProviderUsage>(StringComparer.Ordinal),
            Base.AddMinutes(10));

        Assert.Single(history[CodexWeekly]);
        Assert.Equal(60, history[CodexWeekly][0].RemainingPercent);
    }

    /// <summary>
    /// A Claude-only cycle: Codex is paused and its last reading is still on
    /// screen, but the chart must not gain a point nobody measured.
    /// </summary>
    [Fact]
    public void AnotherProvidersCycleAddsNoSampleForTheRetainedOne()
    {
        var existing = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
        {
            [CodexWeekly] = new[] { new UsageHistorySample(Base, 60) }
        };

        var history = UsageHistoryRecorder.Record(
            existing,
            Measurement(ProviderNames.ClaudeCode, 70),
            Base.AddMinutes(10));

        Assert.Single(history[CodexWeekly]);
        Assert.Single(history[ClaudeWeekly]);
    }

    [Fact]
    public void RecordingStillPrunesEverythingOlderThanTheRetentionWindow()
    {
        var expired = Base - UsageHistoryModel.RetentionInterval - TimeSpan.FromMinutes(1);
        var existing = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
        {
            [CodexWeekly] = new[] { new UsageHistorySample(expired, 95) }
        };

        var history = UsageHistoryRecorder.Record(existing, Measurement(ProviderNames.Codex, 60), Base);

        Assert.Single(history[CodexWeekly]);
        Assert.Equal(60, history[CodexWeekly][0].RemainingPercent);
    }

    /// <summary>
    /// The all-paused tick: retention is the only thing that runs, and it runs
    /// whether or not anything was collected — a long pause does not stop the
    /// 24-hour clock.
    /// </summary>
    [Fact]
    public void RetentionPrunesWithoutAnyMeasurement()
    {
        var expired = Base - UsageHistoryModel.RetentionInterval - TimeSpan.FromMinutes(1);
        var history = UsageHistoryModel.Sanitized(
            new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal)
            {
                [CodexWeekly] = new[]
                {
                    new UsageHistorySample(expired, 95),
                    new UsageHistorySample(Base.AddMinutes(-2), 80)
                }
            },
            Base);

        Assert.Single(history[CodexWeekly]);
        Assert.Equal(80, history[CodexWeekly][0].RemainingPercent);
    }
}
