import XCTest
@testable import UsageBarCore

/// The macOS menu's collapsible lower section: what its state is, how it
/// changes, and — mostly — what it must leave alone.
///
/// The disclosure is presentation only and lives for one app session. Its
/// value is a plain struct so these tests can pin the launch state and the
/// toggle without AppKit, and can show that every provider decision — whether
/// a provider is collected, whether its details are drawn, which provider the
/// menu bar speaks for — is computed from inputs this value never appears in.
final class MenuDisclosureTests: XCTestCase {
    // MARK: - State

    func testTheMenuLaunchesCollapsed() {
        let state = MenuDisclosureState()

        XCTAssertFalse(state.isExpanded)
        XCTAssertFalse(state.revealsLowerControls)
        XCTAssertEqual(state.chevronSymbolName, "chevron.down")
    }

    func testToggleExpandsACollapsedMenu() {
        var state = MenuDisclosureState()

        state.toggle()

        XCTAssertTrue(state.isExpanded)
        XCTAssertTrue(state.revealsLowerControls)
        XCTAssertEqual(state.chevronSymbolName, "chevron.up")
    }

    func testToggleCollapsesAnExpandedMenu() {
        var state = MenuDisclosureState()
        state.toggle()

        state.toggle()

        XCTAssertFalse(state.isExpanded)
        XCTAssertFalse(state.revealsLowerControls)
        XCTAssertEqual(state.chevronSymbolName, "chevron.down")
        XCTAssertEqual(state, MenuDisclosureState())
    }

    func testReadingThePresentationForARebuildLeavesTheStateAlone() {
        // A rebuild — after a refresh, a language change, a preference toggle —
        // reads the state to decide what to hide. Reading is all it does: only
        // `toggle()` can move the value, so an expanded menu stays expanded
        // through any number of rebuilds and a collapsed one stays collapsed.
        var expanded = MenuDisclosureState()
        expanded.toggle()
        let collapsed = MenuDisclosureState()

        for _ in 0..<5 {
            XCTAssertTrue(expanded.revealsLowerControls)
            XCTAssertEqual(expanded.chevronSymbolName, "chevron.up")
            XCTAssertFalse(collapsed.revealsLowerControls)
            XCTAssertEqual(collapsed.chevronSymbolName, "chevron.down")
        }

        XCTAssertTrue(expanded.isExpanded)
        XCTAssertFalse(collapsed.isExpanded)
    }

    func testAFreshValueIsTheLaunchStateNotTheLastSessions() {
        // Nothing is persisted: the only way to obtain a value is `init()`,
        // and `init()` is collapsed. A relaunch therefore always starts closed.
        var previousSession = MenuDisclosureState()
        previousSession.toggle()
        XCTAssertTrue(previousSession.isExpanded)

        let nextLaunch = MenuDisclosureState()
        XCTAssertFalse(nextLaunch.isExpanded)
    }

    // MARK: - Provider decisions are untouched

    private var bothStates: [MenuDisclosureState] {
        var expanded = MenuDisclosureState()
        expanded.toggle()
        return [MenuDisclosureState(), expanded]
    }

    func testCollectionEligibilityIsTheSameWhicheverHalfIsOpen() {
        // The policy takes no disclosure parameter at all — the strongest
        // form of "eligibility cannot depend on it". Each answer is computed
        // once per disclosure state and must not differ.
        for state in bothStates {
            XCTAssertTrue(
                ProviderCollectionPolicy.isEligible(connected: true, collectionEnabled: true),
                "expanded: \(state.isExpanded)"
            )
            XCTAssertFalse(
                ProviderCollectionPolicy.isEligible(connected: true, collectionEnabled: false),
                "expanded: \(state.isExpanded)"
            )
            XCTAssertEqual(
                ProviderCollectionPolicy.action(connected: true, collectionEnabled: true),
                .collect,
                "expanded: \(state.isExpanded)"
            )
            XCTAssertEqual(
                ProviderCollectionPolicy.action(connected: true, collectionEnabled: false),
                .retainCache,
                "expanded: \(state.isExpanded)"
            )
            XCTAssertTrue(
                ProviderCollectionPolicy.shouldAccept(
                    connected: true,
                    collectionEnabled: true,
                    launchGeneration: 3,
                    currentGeneration: 3
                ),
                "expanded: \(state.isExpanded)"
            )
        }
    }

    func testProviderDetailVisibilityIsTheSameWhicheverHalfIsOpen() {
        // Per-provider "Show details" is its own preference. Collapsing the
        // menu's controls neither hides a visible body nor reveals a hidden one.
        for state in bothStates {
            let shown = ProviderDetailPresentationPolicy.card(
                collectionEnabled: true,
                detailsVisible: true,
                hasIssue: false
            )
            let hidden = ProviderDetailPresentationPolicy.card(
                collectionEnabled: true,
                detailsVisible: false,
                hasIssue: true
            )
            let paused = ProviderDetailPresentationPolicy.card(
                collectionEnabled: false,
                detailsVisible: true,
                hasIssue: true
            )

            XCTAssertTrue(shown.showsDetailBody, "expanded: \(state.isExpanded)")
            XCTAssertFalse(hidden.showsDetailBody, "expanded: \(state.isExpanded)")
            XCTAssertTrue(hidden.showsOperationalIssue, "expanded: \(state.isExpanded)")
            XCTAssertTrue(paused.showsDetailBody, "expanded: \(state.isExpanded)")
            XCTAssertTrue(paused.showsPausedMarker, "expanded: \(state.isExpanded)")
            XCTAssertFalse(paused.showsOperationalIssue, "expanded: \(state.isExpanded)")
        }
    }

    func testStatusProviderSelectionIsTheSameWhicheverHalfIsOpen() {
        let providers = [
            ProviderCollectionState(name: "Codex", connected: true, collectionEnabled: true),
            ProviderCollectionState(name: "Claude Code", connected: true, collectionEnabled: false)
        ]

        for state in bothStates {
            let eligible = ProviderStatusPolicy.eligibleNames(providers)
            XCTAssertEqual(eligible, ["Codex"], "expanded: \(state.isExpanded)")
            XCTAssertEqual(
                ProviderStatusPolicy.connectedNames(providers),
                ["Codex", "Claude Code"],
                "expanded: \(state.isExpanded)"
            )
            // The stored selection is paused, so the value falls through to the
            // one eligible provider — exactly as it does with the menu closed.
            XCTAssertEqual(
                ProviderStatusPolicy.activeProviderName(
                    eligible: eligible,
                    selected: "Claude Code",
                    autoRotate: false,
                    rotatingIndex: 0
                ),
                "Codex",
                "expanded: \(state.isExpanded)"
            )
            XCTAssertFalse(
                ProviderStatusPolicy.rotationIsActive(autoRotate: true, eligibleCount: eligible.count),
                "expanded: \(state.isExpanded)"
            )
            XCTAssertNil(
                ProviderStatusPolicy.idleReason(connectedCount: 2, eligibleCount: eligible.count),
                "expanded: \(state.isExpanded)"
            )
        }
    }
}
