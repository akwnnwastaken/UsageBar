import Foundation

/// Whether UsageBar is allowed to collect usage for a provider.
///
/// Two independent facts decide this and are deliberately never conflated. A
/// provider is *connected* when its configuration is retained, and *collection
/// enabled* when UsageBar may initiate reads for it. Pausing a provider leaves
/// it connected — that is the whole point of a pause — so neither fact can
/// stand in for the other, and a single "enabled" flag could not express both.
public enum ProviderCollectionPolicy {
    /// A provider is eligible for collection only while it is both connected
    /// and collection-enabled.
    public static func isEligible(connected: Bool, collectionEnabled: Bool) -> Bool {
        connected && collectionEnabled
    }
}

/// Where the collection-enabled state is stored, and how a stored value reads.
///
/// The read is existence-aware on purpose. `UserDefaults.bool(forKey:)` answers
/// `false` for a key that was never written, which for these two keys would
/// pause every provider belonging to a user upgrading from a build that
/// predates them. An absent preference therefore means *enabled*, and only an
/// explicitly stored `false` pauses collection.
///
/// The historical `provider.codex.enabled` / `provider.claude.enabled` keys are
/// a separate family with an unrelated meaning: they recorded whether a
/// provider was configured at all, are read only by the migration that
/// introduced `provider.*.connected`, and must never be interpreted as a pause.
/// They are neither migrated into these keys nor consulted here.
public enum ProviderCollectionPreference {
    public static let codexKey = "provider.codex.collection.enabled"
    public static let claudeKey = "provider.claude.collection.enabled"

    /// The stored collection state, defaulting to enabled when the key is
    /// absent. `defaults` is a parameter rather than the standard suite so the
    /// semantics can be exercised without touching the user's own preferences.
    public static func isCollectionEnabled(in defaults: UserDefaults, forKey key: String) -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }
}
