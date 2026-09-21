import Foundation

/// Whether the macOS menu's lower controls — settings, provider management,
/// refresh, diagnostics and the version row — are currently revealed.
///
/// This is **session** state and nothing more. It starts collapsed on every
/// launch, lives only in memory while the app runs, and is never written to
/// `UserDefaults`: which half of the menu is open is not a product preference.
/// It is also purely presentational. It takes no part in collection,
/// eligibility, detail visibility, status selection, rotation, history or
/// refresh; those are decided by `ProviderCollectionPolicy`,
/// `ProviderDetailPresentationPolicy` and `ProviderStatusPolicy` from state
/// this value never sees, and none of them can take it as an input.
///
/// `toggle()` is the only mutation. Reading the presentation for a menu
/// rebuild — after a refresh, a language change or any other routine rebuild —
/// leaves the value exactly as the user last left it.
public struct MenuDisclosureState: Equatable {
    /// `true` while the lower controls are shown.
    public private(set) var isExpanded: Bool

    /// The launch state: collapsed, so the menu opens in its compact form.
    public init() {
        isExpanded = false
    }

    /// Flips between collapsed and expanded.
    public mutating func toggle() {
        isExpanded.toggle()
    }

    /// Whether the collapsible group of menu items is drawn.
    public var revealsLowerControls: Bool {
        isExpanded
    }

    /// The SF Symbol on the disclosure control: pointing down while there is
    /// more to reveal, up once it is revealed.
    public var chevronSymbolName: String {
        isExpanded ? "chevron.up" : "chevron.down"
    }
}
