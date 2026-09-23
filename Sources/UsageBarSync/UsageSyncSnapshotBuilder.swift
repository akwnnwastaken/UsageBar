import Foundation
import UsageBarCore

/// What the builder is told about one provider.
///
/// This is the narrow input the privacy boundary accepts. It carries no raw
/// command output, no process handle, no executable path, no environment and
/// no credential, because none of those is a parameter here.
///
/// `displayFilteredUsage` is the product's own `ProviderUsage` **after**
/// `UsageDisplayNoiseFilter` has been applied by the call site — the same value
/// the desktop UI is showing. The builder deliberately does not reach for the
/// raw cache and does not run a second filter of its own; see
/// `UsageSyncSnapshotBuilder` for why. Its `lastSuccessfulAt` is the
/// measurement time, and its `error` is never read: the snapshot model has no
/// field that could carry one.
public struct UsageSyncProviderInput {
    /// The product's provider name, e.g. `"Codex"` or `"Claude Code"`. Needed
    /// because the product's headline policy is keyed on it; it is normalized
    /// to a slug before it reaches the wire and never transmitted verbatim.
    public let productName: String

    /// Whether the provider's configuration is retained.
    public let connected: Bool

    /// Whether the desktop may currently initiate readings.
    public let collecting: Bool

    /// The display-filtered usage the desktop is presenting, when it holds one.
    public let displayFilteredUsage: ProviderUsage?

    public init(
        productName: String,
        connected: Bool,
        collecting: Bool,
        displayFilteredUsage: ProviderUsage?
    ) {
        self.productName = productName
        self.connected = connected
        self.collecting = collecting
        self.displayFilteredUsage = displayFilteredUsage
    }
}

public enum UsageSyncBuilderError: Error, Equatable, CustomStringConvertible {
    case malformedProviderName
    case headlineWindowNotFound(providerId: String)
    case percentageOutOfRange(providerId: String, windowId: String, value: Int)

    public var description: String {
        switch self {
        case .malformedProviderName:
            return "provider name does not normalize to a usable providerId"
        case .headlineWindowNotFound(let providerId):
            return "selected headline window is not among the windows of provider '\(providerId)'"
        case .percentageOutOfRange(let providerId, let windowId, let value):
            return "remaining percentage \(value) out of range 0...100 at window '\(windowId)' in provider '\(providerId)'"
        }
    }
}

/// Builds a schema-v1 snapshot from desktop state.
///
/// **This type is the privacy boundary.** It maps field by field and never
/// serializes a product object wholesale, so adding a field to `ProviderUsage`
/// upstream can never silently widen what crosses to a phone.
///
/// Three things it deliberately does *not* do:
///
/// 1. **It does not filter.** `UsageDisplayNoiseFilter` has already run at the
///    call site; running it again here would hold a rise twice and make the
///    phone disagree with the Mac beside it. There is exactly one display
///    filter and it lives in the desktop app.
/// 2. **It does not select a headline.** `UsageSummaryCalculator` — the
///    product's own policy, shared with the menu bar — decides. So Claude keeps
///    five-hour-then-ordinary-weekly, and Codex keeps most-constrained-window,
///    including when the most constrained window is a `duration` one.
/// 3. **It does not touch a network.** No transport exists yet, and the payload
///    is designed so that the selected Tailscale overlay does not change it.
public enum UsageSyncSnapshotBuilder {
    /// Builds and validates a snapshot. Deterministic for a given input and
    /// `generatedAt`.
    public static func snapshot(
        from inputs: [UsageSyncProviderInput],
        generatedAt: Date
    ) throws -> UsageSyncSnapshot {
        let snapshot = UsageSyncSnapshot(
            generatedAt: generatedAt,
            providers: try inputs.map { try provider(from: $0) }
        )
        try UsageSyncValidator.validate(snapshot)
        return snapshot
    }

    private static func provider(from input: UsageSyncProviderInput) throws -> UsageSyncProvider {
        guard let providerId = UsageSyncIdentity.providerId(forProductName: input.productName) else {
            throw UsageSyncBuilderError.malformedProviderName
        }

        // A disconnected provider's readings are dropped by the desktop, so it
        // carries no measurement regardless of what it was last told.
        guard input.connected else {
            return UsageSyncProvider(
                providerId: providerId,
                connected: false,
                collecting: false,
                measurement: nil
            )
        }

        return UsageSyncProvider(
            providerId: providerId,
            connected: true,
            collecting: input.collecting,
            measurement: try measurement(from: input, providerId: providerId)
        )
    }

    /// A measurement exists only when the desktop actually accepted one:
    /// `lastSuccessfulAt` is set exclusively by `markedSuccessful(at:)` and is
    /// preserved across a failure by `ProviderUsage.stale(from:)`, so it is the
    /// authoritative signal — and the authoritative measurement time.
    private static func measurement(
        from input: UsageSyncProviderInput,
        providerId: String
    ) throws -> UsageSyncMeasurement? {
        guard
            let usage = input.displayFilteredUsage,
            let measuredAt = usage.lastSuccessfulAt,
            !usage.windows.isEmpty
        else { return nil }

        let windows = try usage.windows.map { try window(from: $0, providerId: providerId) }

        // The product's own headline policy, not a mobile reimplementation.
        guard let summary = UsageSummaryCalculator.summary(
            for: usage.name,
            in: [usage.name: usage]
        ) else { return nil }

        let headlineWindowId = UsageSyncIdentity.windowId(for: summary.windowKind)
        guard windows.contains(where: { $0.windowId == headlineWindowId }) else {
            throw UsageSyncBuilderError.headlineWindowNotFound(providerId: providerId)
        }

        return UsageSyncMeasurement(
            measuredAt: measuredAt,
            headlineRemainingPercent: summary.remainingPercent,
            headlineWindowId: headlineWindowId,
            windows: windows
        )
    }

    private static func window(
        from window: UsageWindow,
        providerId: String
    ) throws -> UsageSyncWindow {
        let windowId = UsageSyncIdentity.windowId(for: window.kind)

        // The product's canonical conversion. Corrupted input is rejected
        // rather than clamped: clamping here would quietly turn a broken
        // reading into a plausible-looking one on the phone.
        let remaining = 100 - window.usedPercent
        guard (0...100).contains(remaining) else {
            throw UsageSyncBuilderError.percentageOutOfRange(
                providerId: providerId, windowId: windowId, value: remaining
            )
        }

        var scope: String?
        var position: Int?
        var durationMinutes = window.durationMinutes

        switch window.kind {
        case .weeklyScoped(let windowScope):
            scope = windowScope
        case .unknown(let windowPosition):
            position = windowPosition
            // An unknown window is precisely one whose length is not known;
            // carrying a duration beside it would contradict its own kind.
            durationMinutes = nil
        case .fiveHour, .weekly, .duration:
            break
        }

        return UsageSyncWindow(
            windowId: windowId,
            kind: UsageSyncIdentity.windowKind(for: window.kind),
            scope: scope,
            durationMinutes: durationMinutes,
            position: position,
            remainingPercent: remaining,
            resetsAt: window.resetsAt
        )
    }
}
