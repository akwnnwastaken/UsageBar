namespace UsageBar.Windows.Core.Policies;

/// <summary>What a refresh cycle does about one provider.</summary>
public enum ProviderCollectionAction
{
    /// <summary>Eligible: read it, and accept what comes back per Model B.</summary>
    Collect,

    /// <summary>
    /// Connected but paused: leave the cache exactly as it is. Reusing the
    /// disconnected branch here would erase the readings a pause is meant to
    /// keep, which is the opposite of "temporary".
    /// </summary>
    RetainCache,

    /// <summary>Not connected: drop the readings, as disconnect always has.</summary>
    DropCache
}

/// <summary>
/// Whether UsageBar is allowed to collect usage for a provider.
///
/// Two independent facts decide this and are deliberately never conflated. A
/// provider is <em>connected</em> when its configuration is retained, and
/// <em>collection enabled</em> when UsageBar may initiate reads for it. Pausing
/// a provider leaves it connected — that is the whole point of a pause — so
/// neither fact can stand in for the other, and a single "enabled" flag could
/// not express both. The macOS rule is identical.
/// </summary>
public static class ProviderCollectionPolicy
{
    /// <summary>
    /// A provider is eligible for collection only while it is both connected
    /// and collection-enabled.
    /// </summary>
    public static bool IsEligible(bool connected, bool collectionEnabled) =>
        connected && collectionEnabled;

    /// <summary>
    /// The three-way decision a refresh makes for one provider. Every launch
    /// site goes through this so "paused" can never fall into the disconnected
    /// branch by accident.
    /// </summary>
    public static ProviderCollectionAction Action(bool connected, bool collectionEnabled)
    {
        if (!connected)
        {
            return ProviderCollectionAction.DropCache;
        }

        return collectionEnabled
            ? ProviderCollectionAction.Collect
            : ProviderCollectionAction.RetainCache;
    }

    /// <summary>
    /// Whether a cycle built from these actions reads any provider at all. When
    /// it does not there is nothing to refresh: no spinner, no completion, no
    /// timestamp — only history retention, which runs on its own.
    /// </summary>
    public static bool CollectsUsage(IEnumerable<ProviderCollectionAction> actions)
    {
        ArgumentNullException.ThrowIfNull(actions);

        return actions.Contains(ProviderCollectionAction.Collect);
    }

    /// <summary>
    /// Whether a finished read may still change what UsageBar shows.
    ///
    /// Neither platform can cancel one provider's read, so a read started
    /// before the user paused or disconnected can physically finish afterwards.
    /// Current eligibility alone cannot catch every such result: a
    /// disconnect→reconnect or pause→resume during a slow read leaves the
    /// provider eligible again, and the stale answer would be accepted after a
    /// newer one. The generation captured at launch is what distinguishes them.
    /// </summary>
    public static bool ShouldAccept(
        bool connected,
        bool collectionEnabled,
        int launchGeneration,
        int currentGeneration) =>
        IsEligible(connected, collectionEnabled) && launchGeneration == currentGeneration;
}

/// <summary>
/// The single-slot follow-up a resumed provider is owed.
///
/// Resuming collection asks for an immediate reading, but a refresh already in
/// flight cannot adopt a provider it did not launch. The request is therefore
/// remembered as one bit and honoured once that refresh completes. It is
/// deliberately not a queue: any number of resumes during one refresh still owe
/// exactly one follow-up, and consuming the bit before the follow-up starts is
/// what stops it from re-arming itself forever.
/// </summary>
public struct PendingCollectionRefresh : IEquatable<PendingCollectionRefresh>
{
    private bool _isArmed;

    /// <summary>
    /// Records a resume. Returns true when the caller should start a refresh
    /// straight away, false when the running one will be followed up.
    /// </summary>
    public bool RequestCollection(bool isRefreshing)
    {
        if (!isRefreshing)
        {
            return true;
        }

        _isArmed = true;
        return false;
    }

    /// <summary>Takes the pending request, if any. Always leaves the slot empty.</summary>
    public bool Consume()
    {
        var armed = _isArmed;
        _isArmed = false;
        return armed;
    }

    public bool Equals(PendingCollectionRefresh other) => _isArmed == other._isArmed;

    public override bool Equals(object? obj) => obj is PendingCollectionRefresh other && Equals(other);

    public override int GetHashCode() => _isArmed.GetHashCode();

    public static bool operator ==(PendingCollectionRefresh left, PendingCollectionRefresh right) =>
        left.Equals(right);

    public static bool operator !=(PendingCollectionRefresh left, PendingCollectionRefresh right) =>
        !left.Equals(right);
}
