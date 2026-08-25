import Foundation

/// One provider's connection and collection state, as the status rules see it.
public struct ProviderCollectionState: Equatable {
    public let name: String
    public let connected: Bool
    public let collectionEnabled: Bool

    public init(name: String, connected: Bool, collectionEnabled: Bool) {
        self.name = name
        self.connected = connected
        self.collectionEnabled = collectionEnabled
    }

    public var isEligible: Bool {
        ProviderCollectionPolicy.isEligible(
            connected: connected,
            collectionEnabled: collectionEnabled
        )
    }
}

/// Why the menu bar has no usage value to show.
public enum StatusIdleReason: Equatable {
    /// Nothing is set up yet — the user is asked to connect a provider.
    case noProviderConnected
    /// Providers are connected; the user has paused collection on all of them.
    /// Telling this user to "connect a provider first" would be wrong and would
    /// hide the fact that resuming is one click away.
    case allCollectionPaused
}

/// Which provider the menu bar speaks for, and what it says when none can.
///
/// Three lists are deliberately kept apart. **Connected** providers are what the
/// user manages — they stay listed, disconnectable and resumable while paused.
/// **Eligible** providers are the ones actually being collected, and only those
/// may be presented as the live value or rotated through. The **stored
/// selection** is a preference among connected providers and is never rewritten
/// because collection happened to be paused.
public enum ProviderStatusPolicy {
    public static func connectedNames(_ states: [ProviderCollectionState]) -> [String] {
        states.filter(\.connected).map(\.name)
    }

    public static func eligibleNames(_ states: [ProviderCollectionState]) -> [String] {
        states.filter(\.isEligible).map(\.name)
    }

    /// The provider whose value is shown, or `nil` when none is collecting.
    ///
    /// A paused selection falls through to another eligible provider **without
    /// changing what is stored**, so resuming it brings the user's own choice
    /// straight back.
    public static func activeProviderName(
        eligible: [String],
        selected: String?,
        autoRotate: Bool,
        rotatingIndex: Int
    ) -> String? {
        guard !eligible.isEmpty else { return nil }
        if autoRotate && eligible.count > 1 {
            return eligible[abs(rotatingIndex) % eligible.count]
        }
        if let selected, eligible.contains(selected) { return selected }
        return eligible[0]
    }

    /// Whether auto-rotation has anything to rotate between. The preference
    /// itself survives a pause: rotation simply lies dormant until a second
    /// provider is eligible again.
    public static func rotationIsActive(autoRotate: Bool, eligibleCount: Int) -> Bool {
        autoRotate && eligibleCount > 1
    }

    public static func idleReason(connectedCount: Int, eligibleCount: Int) -> StatusIdleReason? {
        if connectedCount == 0 { return .noProviderConnected }
        if eligibleCount == 0 { return .allCollectionPaused }
        return nil
    }

    /// Whether a provider's retained error should be shown as an active
    /// collection failure.
    ///
    /// A paused provider keeps whatever error it last had — the model is not
    /// rewritten — but UsageBar is not attempting collection, so presenting it
    /// as a failure would blame the provider for a state the user chose. Paused
    /// wins; the error returns on its own if a later reading fails.
    public static func rendersActiveError(collectionEnabled: Bool, hasError: Bool) -> Bool {
        collectionEnabled && hasError
    }
}
