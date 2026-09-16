namespace UsageBar.Windows.Core.Policies;

/// <summary>
/// What one connected provider's card contains.
///
/// The three parts are independent because the states behind them are: a
/// provider can be paused with its details shown, collecting with them hidden,
/// or any other combination. Nothing here can hide a provider outright — a
/// connected provider always keeps its heading, so it is always recognisable
/// and always manageable.
/// </summary>
public sealed record ProviderCardPlan(
    bool ShowsPausedMarker,
    bool ShowsDetailBody,
    bool ShowsOperationalIssue);

/// <summary>
/// How a connected provider is presented, given what the user chose.
///
/// Pure, so both the panel and the tests read the same rule. It takes no part
/// in eligibility, selection or rotation: those are decided by
/// <see cref="ProviderCollectionPolicy"/> and the settings extensions, from
/// state this policy never sees. The macOS rule is identical.
/// </summary>
public static class ProviderDetailPresentationPolicy
{
    /// <param name="collectionEnabled">Whether UsageBar may read the provider.</param>
    /// <param name="detailsVisible">Whether the user wants the detailed body.</param>
    /// <param name="hasIssue">Whether the reading carries an error.</param>
    public static ProviderCardPlan Card(bool collectionEnabled, bool detailsVisible, bool hasIssue) =>
        new(
            // The "· Duraklatıldı" / "· Paused" suffix on the heading. It
            // survives a hidden body: a compact card must still say why it is
            // not moving.
            ShowsPausedMarker: !collectionEnabled,

            // The quota and history body: usage-window values, remaining
            // percentages, reset lines, history summaries and charts. This is
            // the only part detail visibility controls.
            ShowsDetailBody: detailsVisible,

            // The one concise line an active collection failure earns. It
            // survives a hidden body on purpose: it is operational state rather
            // than quota data, and without it a failing provider would be
            // indistinguishable from a healthy one the user had collapsed.
            ShowsOperationalIssue: ProviderCollectionPolicy.RendersActiveError(
                collectionEnabled,
                hasIssue));
}
