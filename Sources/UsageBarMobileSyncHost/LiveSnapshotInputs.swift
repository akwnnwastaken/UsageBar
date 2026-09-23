import Foundation
import UsageBarCore
import UsageBarSync

/// Turns the desktop's *presented* state into snapshot builder inputs.
///
/// The single most important line in this file is which usage it reads:
/// `displayFilteredUsage` — the value the Mac's own menu bar and menu are
/// showing — and never the raw retained cache or a history sample. A phone that
/// disagreed with the Mac sitting beside it would be worse than a phone with no
/// data, and the display filter deliberately holds a rise back for a cycle, so
/// reading around it would produce exactly that disagreement.
///
/// It is also not a second filter. `UsageDisplayNoiseFilter` has already run at
/// the call site; running it again here would hold the same rise twice.
public enum MobileSyncLiveSnapshot {
    /// Menu order, so the phone lists providers the way the Mac does.
    public static let providerOrder = ["Codex", "Claude Code"]

    /// One provider as the desktop currently presents it.
    public struct ProviderState {
        public let productName: String
        public let connected: Bool
        public let collecting: Bool
        /// `displayUsages[productName]` — after the display filter, before any
        /// mobile-specific interpretation.
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

    public static func inputs(from states: [ProviderState]) -> [UsageSyncProviderInput] {
        states.map { state in
            UsageSyncProviderInput(
                productName: state.productName,
                connected: state.connected,
                collecting: state.collecting,
                // A disconnected provider's reading is dropped here rather than
                // relied on to be absent downstream. The builder also drops it;
                // saying so twice costs nothing and means neither layer is the
                // only thing standing between a disconnected provider and a
                // measurement on the wire.
                displayFilteredUsage: state.connected ? state.displayFilteredUsage : nil
            )
        }
    }

    /// Builds and validates. Throws exactly where the builder throws, so a
    /// caller can keep the previous published snapshot on failure.
    public static func build(
        from states: [ProviderState],
        generatedAt: Date = Date()
    ) throws -> UsageSyncSnapshot {
        try UsageSyncSnapshotBuilder.snapshot(from: inputs(from: states), generatedAt: generatedAt)
    }
}
