import Foundation

/// Where the per-provider detail-visibility preference is stored, and how a
/// stored value reads.
///
/// This is a **presentation** preference and nothing else. It decides whether a
/// connected provider's detailed body is drawn; it never decides whether the
/// provider is read. Collection has its own state in
/// `ProviderCollectionPreference`, and the two are deliberately kept apart: a
/// provider whose details are hidden goes on collecting, recording history and
/// speaking for the menu bar exactly as before.
///
/// The read is existence-aware for the same reason collection's is.
/// `UserDefaults.bool(forKey:)` answers `false` for a key that was never
/// written, which for these two keys would silently collapse every provider
/// belonging to a user upgrading from a build that predates them. An absent
/// preference therefore means *visible*, and only an explicitly stored `false`
/// hides a body.
///
/// Neither the connection keys (`provider.*.connected`), the collection keys
/// (`provider.*.collection.enabled`) nor the historical `provider.*.enabled`
/// family is consulted or migrated here. They answer different questions, and
/// borrowing an answer from any of them would tie a presentation choice to a
/// lifecycle event the user did not make.
public enum ProviderDetailVisibilityPreference {
    public static let codexKey = "provider.codex.details.visible"
    public static let claudeKey = "provider.claude.details.visible"

    /// The stored visibility, defaulting to visible when the key is absent.
    /// `defaults` is a parameter rather than the standard suite so the semantics
    /// can be exercised without touching the user's own preferences.
    public static func areDetailsVisible(in defaults: UserDefaults, forKey key: String) -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }
}

/// What one connected provider's card contains.
///
/// The three parts are independent because the states behind them are: a
/// provider can be paused with its details shown, collecting with them hidden,
/// or any other combination. Nothing here can hide a provider outright — a
/// connected provider always keeps its heading, so it is always recognisable
/// and always manageable.
public struct ProviderCardPlan: Equatable {
    /// The "· Duraklatıldı" / "· Paused" suffix on the heading.
    public let showsPausedMarker: Bool

    /// The quota and history body: usage-window values, remaining percentages,
    /// reset lines, history summaries and charts. This is the only part detail
    /// visibility controls.
    public let showsDetailBody: Bool

    /// The one concise line an active collection failure earns. It survives a
    /// hidden body on purpose: it is operational state rather than quota data,
    /// and without it a failing provider would be indistinguishable from a
    /// healthy one the user had merely collapsed.
    public let showsOperationalIssue: Bool

    public init(showsPausedMarker: Bool, showsDetailBody: Bool, showsOperationalIssue: Bool) {
        self.showsPausedMarker = showsPausedMarker
        self.showsDetailBody = showsDetailBody
        self.showsOperationalIssue = showsOperationalIssue
    }
}

/// How a connected provider is presented, given what the user chose.
///
/// Pure, so both the menu and the tests read the same rule. It takes no part in
/// eligibility, selection or rotation: those are decided by
/// `ProviderCollectionPolicy` and `ProviderStatusPolicy` from state this policy
/// never sees.
public enum ProviderDetailPresentationPolicy {
    public static func card(
        collectionEnabled: Bool,
        detailsVisible: Bool,
        hasIssue: Bool
    ) -> ProviderCardPlan {
        ProviderCardPlan(
            showsPausedMarker: !collectionEnabled,
            showsDetailBody: detailsVisible,
            showsOperationalIssue: ProviderStatusPolicy.rendersActiveError(
                collectionEnabled: collectionEnabled,
                hasError: hasIssue
            )
        )
    }
}
