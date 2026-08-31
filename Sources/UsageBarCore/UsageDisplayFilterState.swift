import Foundation

/// The memory `UsageDisplayNoiseFilter` keeps between refreshes: what is shown
/// for each series, which rise is being held back, and how many consecutive
/// measurements have confirmed it.
///
/// It advances **only** from measurements newly accepted in the current refresh
/// cycle. Advancing it from the whole usage cache — which is what UsageBar used
/// to do — lets one provider's refresh re-confirm a rise that nobody measured
/// again, so a rise the filter requires three consecutive measurements for is
/// accepted after two. The input is part of the contract, not a detail.
public struct UsageDisplayFilterState: Equatable {
    private var displayed: [String: Int]
    private var pendingRise: [String: Int]
    private var pendingCount: [String: Int]

    public init(
        displayed: [String: Int] = [:],
        pendingRise: [String: Int] = [:],
        pendingCount: [String: Int] = [:]
    ) {
        self.displayed = displayed
        self.pendingRise = pendingRise
        self.pendingCount = pendingCount
    }

    /// What to show for a series, or `nil` while it has never been measured.
    public func displayedValue(forKey key: String) -> Int? { displayed[key] }

    /// The rise being held for a series, exposed so the holding itself can be
    /// asserted rather than inferred from what happens several cycles later.
    public func pendingRise(forKey key: String) -> Int? { pendingRise[key] }

    /// How many consecutive measurements have confirmed the held rise.
    public func pendingCount(forKey key: String) -> Int { pendingCount[key] ?? 0 }

    /// Records one newly accepted measurement for one series.
    public mutating func advance(key: String, raw: Int) {
        let decision = UsageDisplayNoiseFilter.decide(
            raw: raw,
            previouslyDisplayed: displayed[key],
            pendingRise: pendingRise[key],
            pendingCount: pendingCount[key] ?? 0
        )
        displayed[key] = decision.displayed
        pendingRise[key] = decision.pendingRise
        pendingCount[key] = decision.pendingCount
    }

    /// Drops a provider's half-proven rise while keeping what is on screen.
    ///
    /// This is the pause case: the measurements that would have confirmed the
    /// rise are not coming, and a pause of any length must not later be treated
    /// as though they had arrived consecutively.
    public mutating func clearPendingRise(forProvider providerName: String) {
        let prefix = Self.keyPrefix(forProvider: providerName)
        pendingRise = pendingRise.filter { !$0.key.hasPrefix(prefix) }
        pendingCount = pendingCount.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Forgets a provider entirely, displayed values included. Reserved for
    /// disconnect — a pause must never reach for this.
    public mutating func forget(provider providerName: String) {
        let prefix = Self.keyPrefix(forProvider: providerName)
        displayed = displayed.filter { !$0.key.hasPrefix(prefix) }
        clearPendingRise(forProvider: providerName)
    }

    /// Series keys are `provider|window`, so one provider's entries share this
    /// prefix.
    public static func keyPrefix(forProvider providerName: String) -> String {
        "\(providerName)|"
    }
}
