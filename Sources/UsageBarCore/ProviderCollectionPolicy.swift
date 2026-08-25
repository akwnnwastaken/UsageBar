import Foundation

/// What a refresh cycle does about one provider.
public enum ProviderCollectionAction: Equatable {
    /// Eligible: launch a read and accept what comes back, per Model B.
    case collect
    /// Connected but paused: leave the cache exactly as it is. Reusing the
    /// disconnected branch here would erase the readings a pause is meant to
    /// keep, which is the opposite of "temporary".
    case retainCache
    /// Not connected: drop the provider's readings, as disconnect always has.
    case dropCache
}

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

    /// The three-way decision a refresh makes for one provider. Every launch
    /// site goes through this so "paused" can never fall into the disconnected
    /// branch by accident.
    public static func action(connected: Bool, collectionEnabled: Bool) -> ProviderCollectionAction {
        guard connected else { return .dropCache }
        return collectionEnabled ? .collect : .retainCache
    }

    /// Whether a cycle built from these actions reads any provider at all. When
    /// it does not there is nothing to refresh: no spinner, no completion, no
    /// timestamp — only history retention, which runs on its own.
    public static func collectsUsage(_ actions: [ProviderCollectionAction]) -> Bool {
        actions.contains(.collect)
    }

    /// Whether a finished read may still change what UsageBar shows.
    ///
    /// Neither platform can cancel one provider's read, so a read started
    /// before the user paused or disconnected can physically finish afterwards.
    /// Current eligibility alone cannot catch every such result: a
    /// disconnect→reconnect or pause→resume during a slow read leaves the
    /// provider eligible again, and the stale answer would be accepted after a
    /// newer one. The generation captured at launch is what distinguishes them.
    public static func shouldAccept(
        connected: Bool,
        collectionEnabled: Bool,
        launchGeneration: Int,
        currentGeneration: Int
    ) -> Bool {
        isEligible(connected: connected, collectionEnabled: collectionEnabled)
            && launchGeneration == currentGeneration
    }
}

/// The single-slot follow-up a resumed provider is owed.
///
/// Resuming collection asks for an immediate reading, but a refresh already in
/// flight cannot adopt a provider it did not launch. The request is therefore
/// remembered as one bit and honoured once that refresh completes. It is
/// deliberately not a queue: any number of resumes during one refresh still owe
/// exactly one follow-up, and consuming the bit before the follow-up starts is
/// what stops it from re-arming itself forever.
public struct PendingCollectionRefresh: Equatable {
    private var isArmed = false

    public init() {}

    /// Records a resume. Returns `true` when the caller should start a refresh
    /// straight away, `false` when the running one will be followed up.
    public mutating func requestCollection(isRefreshing: Bool) -> Bool {
        guard isRefreshing else { return true }
        isArmed = true
        return false
    }

    /// Takes the pending request, if any. Always leaves the slot empty.
    public mutating func consume() -> Bool {
        defer { isArmed = false }
        return isArmed
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
