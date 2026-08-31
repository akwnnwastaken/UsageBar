import XCTest
@testable import UsageBarCore

/// What the menu bar shows once collection can be paused.
///
/// Three lists are deliberately kept apart and these tests exist to keep them
/// apart: the providers the user *manages*, the providers actually being
/// *collected*, and the provider the user *chose*. Conflating any two of them
/// is what would make a paused provider disappear, or make resuming it lose the
/// user's own selection.
final class ProviderStatusPolicyTests: XCTestCase {
    private let codex = "Codex"
    private let claude = "Claude Code"

    private func states(
        codexConnected: Bool = true,
        codexCollecting: Bool = true,
        claudeConnected: Bool = true,
        claudeCollecting: Bool = true
    ) -> [ProviderCollectionState] {
        [
            ProviderCollectionState(
                name: codex,
                connected: codexConnected,
                collectionEnabled: codexCollecting
            ),
            ProviderCollectionState(
                name: claude,
                connected: claudeConnected,
                collectionEnabled: claudeCollecting
            )
        ]
    }

    // MARK: - Connected vs eligible

    func testAPausedProviderStaysConnectedButStopsBeingEligible() {
        let paused = states(codexCollecting: false)

        XCTAssertEqual(ProviderStatusPolicy.connectedNames(paused), [codex, claude])
        XCTAssertEqual(ProviderStatusPolicy.eligibleNames(paused), [claude])
    }

    func testADisconnectedProviderLeavesBothLists() {
        let disconnected = states(codexConnected: false)

        XCTAssertEqual(ProviderStatusPolicy.connectedNames(disconnected), [claude])
        XCTAssertEqual(ProviderStatusPolicy.eligibleNames(disconnected), [claude])
    }

    // MARK: - Active provider

    func testTheStoredSelectionIsUsedWhileItIsEligible() {
        XCTAssertEqual(
            ProviderStatusPolicy.activeProviderName(
                eligible: [codex, claude],
                selected: codex,
                autoRotate: false,
                rotatingIndex: 0
            ),
            codex
        )
    }

    /// The selection is a preference among connected providers, so pausing the
    /// selected one falls through to another eligible provider — and stores
    /// nothing, which is what lets the next test restore it.
    func testPausingTheSelectedProviderFallsThroughToAnEligibleOne() {
        XCTAssertEqual(
            ProviderStatusPolicy.activeProviderName(
                eligible: [claude],
                selected: codex,
                autoRotate: false,
                rotatingIndex: 0
            ),
            claude
        )
    }

    func testResumingTheSelectedProviderBringsItBack() {
        // Same stored selection as the previous case; only eligibility changed.
        XCTAssertEqual(
            ProviderStatusPolicy.activeProviderName(
                eligible: [codex, claude],
                selected: codex,
                autoRotate: false,
                rotatingIndex: 0
            ),
            codex
        )
    }

    func testNothingIsActiveWhileEveryProviderIsPaused() {
        XCTAssertNil(
            ProviderStatusPolicy.activeProviderName(
                eligible: [],
                selected: codex,
                autoRotate: false,
                rotatingIndex: 0
            )
        )
    }

    // MARK: - Rotation

    func testRotationOnlyVisitsProvidersThatAreBeingCollected() {
        XCTAssertEqual(
            ProviderStatusPolicy.activeProviderName(
                eligible: [claude],
                selected: nil,
                autoRotate: true,
                rotatingIndex: 7
            ),
            claude
        )
    }

    func testRotationCyclesThroughEveryEligibleProvider() {
        let eligible = [codex, claude]
        XCTAssertEqual(
            ProviderStatusPolicy.activeProviderName(
                eligible: eligible,
                selected: nil,
                autoRotate: true,
                rotatingIndex: 0
            ),
            codex
        )
        XCTAssertEqual(
            ProviderStatusPolicy.activeProviderName(
                eligible: eligible,
                selected: nil,
                autoRotate: true,
                rotatingIndex: 1
            ),
            claude
        )
    }

    /// Pausing one of two providers makes rotation dormant. The preference is
    /// not part of this decision at all, so nothing can rewrite it — and the
    /// moment the second provider resumes, rotation is active again.
    func testRotationSleepsWhileFewerThanTwoProvidersAreEligible() {
        XCTAssertFalse(ProviderStatusPolicy.rotationIsActive(autoRotate: true, eligibleCount: 1))
        XCTAssertFalse(ProviderStatusPolicy.rotationIsActive(autoRotate: true, eligibleCount: 0))
        XCTAssertTrue(ProviderStatusPolicy.rotationIsActive(autoRotate: true, eligibleCount: 2))
        XCTAssertFalse(ProviderStatusPolicy.rotationIsActive(autoRotate: false, eligibleCount: 2))
    }

    // MARK: - Idle reason

    func testNothingConnectedAsksTheUserToConnect() {
        XCTAssertEqual(
            ProviderStatusPolicy.idleReason(connectedCount: 0, eligibleCount: 0),
            .noProviderConnected
        )
    }

    /// The distinction the whole feature turns on: a user who paused every
    /// provider has nothing to connect, and telling them otherwise would hide
    /// the fact that resuming is one click away.
    func testEverythingPausedIsNotAskedToConnect() {
        XCTAssertEqual(
            ProviderStatusPolicy.idleReason(connectedCount: 2, eligibleCount: 0),
            .allCollectionPaused
        )
    }

    func testACollectingProviderHasNoIdleReason() {
        XCTAssertNil(ProviderStatusPolicy.idleReason(connectedCount: 2, eligibleCount: 1))
    }

    // MARK: - Paused over error

    func testAPausedProviderIsNotShownAsAFailingOne() {
        XCTAssertFalse(
            ProviderStatusPolicy.rendersActiveError(collectionEnabled: false, hasError: true)
        )
    }

    func testACollectingProviderStillShowsItsError() {
        XCTAssertTrue(
            ProviderStatusPolicy.rendersActiveError(collectionEnabled: true, hasError: true)
        )
        XCTAssertFalse(
            ProviderStatusPolicy.rendersActiveError(collectionEnabled: true, hasError: false)
        )
    }

    // MARK: - Recovery

    /// The path out of an all-paused state, end to end: every provider paused,
    /// the status idle for the right reason, then one resume brings a live
    /// provider back without touching the connection or the stored selection.
    func testResumingOneProviderRecoversFromEverythingPaused() {
        let paused = states(codexCollecting: false, claudeCollecting: false)
        XCTAssertEqual(ProviderStatusPolicy.connectedNames(paused).count, 2)
        XCTAssertTrue(ProviderStatusPolicy.eligibleNames(paused).isEmpty)
        XCTAssertEqual(
            ProviderStatusPolicy.idleReason(connectedCount: 2, eligibleCount: 0),
            .allCollectionPaused
        )
        XCTAssertNil(
            ProviderStatusPolicy.activeProviderName(
                eligible: [],
                selected: codex,
                autoRotate: false,
                rotatingIndex: 0
            )
        )

        let resumed = states(codexCollecting: false, claudeCollecting: true)
        let eligible = ProviderStatusPolicy.eligibleNames(resumed)

        XCTAssertEqual(eligible, [claude])
        XCTAssertNil(ProviderStatusPolicy.idleReason(connectedCount: 2, eligibleCount: eligible.count))
        XCTAssertEqual(
            ProviderStatusPolicy.activeProviderName(
                eligible: eligible,
                selected: codex,
                autoRotate: false,
                rotatingIndex: 0
            ),
            claude
        )
        // Codex never left the connected list, so resuming it needs no
        // reconnection.
        XCTAssertEqual(ProviderStatusPolicy.connectedNames(resumed), [codex, claude])
    }
}
