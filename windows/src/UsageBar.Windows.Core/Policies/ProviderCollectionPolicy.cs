namespace UsageBar.Windows.Core.Policies;

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
}
