import XCTest
import UsageBarSyncTransport
@testable import UsageBarMobileSyncHost

/// Containing the code is not permission to run it.
///
/// UsageBar links this module unconditionally, so every guard that keeps Mobile
/// Sync from running — the bundle identity, the preference, the permitted flag —
/// is load-bearing. These are the tests that keep an ordinary launch of UsageBar
/// from quietly becoming a network service.
final class MobileSyncIsolationTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UsageBarMobileSyncHostTests
            .deletingLastPathComponent()   // tests
            .deletingLastPathComponent()   // repository root
    }

    private func makeCoordinator(
        permitted: Bool,
        enabled: Bool
    ) -> (MobileSyncCoordinator, InMemoryMobileSyncAuthStore, Int) {
        var started = 0
        let authStore = InMemoryMobileSyncAuthStore()
        let coordinator = MobileSyncCoordinator(
            authStore: authStore,
            preferences: InMemoryMobileSyncPreferences(isMobileSyncEnabled: enabled),
            isPermittedInThisProcess: permitted,
            makeServer: { handler in
                started += 1
                return UsageSyncLoopbackHTTPServer(handler: handler)
            }
        )
        return (coordinator, authStore, started)
    }

    // MARK: - The runtime gate

    /// One identity, not a list. The Mobile Lab host was a separate
    /// application; it is not part of this product and must not be able to run
    /// this code, or a lab build and a shipping build could serve the same
    /// phone from the same machine.
    func testOnlyUsageBarsOwnBundleIdentifierEnablesMobileSync() {
        XCTAssertTrue(MobileSyncIdentity.isEnabledForBundle("local.codex.usagebar"))
        XCTAssertFalse(MobileSyncIdentity.isEnabledForBundle("com.usagebar.mobilelab.host"))
        XCTAssertFalse(MobileSyncIdentity.isEnabledForBundle("com.usagebar.mobilelab"))
        XCTAssertFalse(MobileSyncIdentity.isEnabledForBundle("local.codex.usagebar.evil"))
        XCTAssertFalse(MobileSyncIdentity.isEnabledForBundle("local.codex"))
        XCTAssertFalse(MobileSyncIdentity.isEnabledForBundle(""))
    }

    /// An unbundled build — a test runner, `swift run` — is not UsageBar
    /// either, so nil must not read as permission.
    func testNilBundleIdentifierIsNotPermitted() {
        XCTAssertFalse(MobileSyncIdentity.isEnabledForBundle(nil))
    }

    /// This very test process is not UsageBar, and proves the default.
    func testCurrentTestProcessIsNotPermitted() {
        XCTAssertFalse(MobileSyncIdentity.isEnabledForCurrentProcess)
    }

    // MARK: - A process that is not UsageBar

    func testUnpermittedProcessNeverStartsTheListener() {
        let (coordinator, _, _) = makeCoordinator(permitted: false, enabled: true)
        XCTAssertFalse(coordinator.isPermitted)
        XCTAssertFalse(coordinator.isEnabled)
        coordinator.startIfEnabled()
        XCTAssertNil(coordinator.boundPort)
        XCTAssertEqual(coordinator.status, .disabled)
        XCTAssertFalse(coordinator.enable(), "enable must refuse outside UsageBar")
        XCTAssertNil(coordinator.boundPort)
    }

    func testUnpermittedProcessCannotStartPairing() {
        let (coordinator, _, _) = makeCoordinator(permitted: false, enabled: true)
        XCTAssertNil(coordinator.startPairing(host: HostFixtures.host))
        XCTAssertNil(coordinator.pairingSession())
    }

    func testUnpermittedProcessPublishesNothing() throws {
        let (coordinator, _, _) = makeCoordinator(permitted: false, enabled: true)
        XCTAssertFalse(coordinator.publish(providers: HostFixtures.bothCollecting))
        XCTAssertNil(coordinator.snapshots.latest)
    }

    // MARK: - UsageBar itself, with Mobile Sync off

    /// The shipped default. Capability in the binary is not activation: a first
    /// launch after upgrading must open no listener, reach no Tailscale and
    /// create no credential.
    func testPermittedProcessStartsDisabledUntilEnabled() {
        let (coordinator, authStore, started) = makeCoordinator(permitted: true, enabled: false)
        XCTAssertTrue(coordinator.isPermitted)
        XCTAssertFalse(coordinator.isEnabled)
        coordinator.startIfEnabled()
        XCTAssertNil(coordinator.boundPort)
        XCTAssertEqual(coordinator.status, .disabled)
        XCTAssertEqual(started, 0, "no server may even be constructed while disabled")
        XCTAssertNil(authStore.load(), "no credential is created by starting up")
        XCTAssertFalse(coordinator.isPaired)
    }

    /// The preference is absent on a fresh install, and absent must mean off.
    func testFreshPreferenceStoreDefaultsToDisabled() {
        let suite = "local.codex.usagebar.tests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = MobileSyncUserDefaultsPreferences(defaults: defaults)
        XCTAssertFalse(preferences.isMobileSyncEnabled, "absent must read as off")
        XCTAssertNil(defaults.object(forKey: MobileSyncUserDefaultsPreferences.preferenceKey))
    }

    func testPermittedProcessPublishesOnlyWhileEnabled() throws {
        let preferences = InMemoryMobileSyncPreferences(isMobileSyncEnabled: false)
        let coordinator = MobileSyncCoordinator(
            authStore: InMemoryMobileSyncAuthStore(),
            preferences: preferences,
            isPermittedInThisProcess: true,
            makeServer: { UsageSyncLoopbackHTTPServer(handler: $0) }
        )
        XCTAssertFalse(coordinator.publish(providers: HostFixtures.bothCollecting))
        preferences.isMobileSyncEnabled = true
        XCTAssertTrue(coordinator.publish(providers: HostFixtures.bothCollecting))
        XCTAssertNotNil(coordinator.snapshots.latest)
    }

    // MARK: - Namespaces

    /// New namespaces, not renamed ones. A device paired with the standalone
    /// Mobile Lab host is not paired with UsageBar: nothing migrates, and the
    /// user pairs once more.
    func testProductionNamespacesAreDistinctFromTheLabHost() {
        XCTAssertEqual(MobileSyncIdentity.loopbackPort, 18642)
        XCTAssertEqual(MobileSyncIdentity.productionBundleIdentifier, "local.codex.usagebar")
        XCTAssertEqual(MobileSyncIdentity.keychainService, "local.codex.usagebar.mobile-sync")
        XCTAssertEqual(MobileSyncUserDefaultsPreferences.preferenceKey, "MobileSyncEnabled")

        XCTAssertNotEqual(MobileSyncIdentity.keychainService, "com.usagebar.mobilelab.host.mobile-sync")
        XCTAssertNotEqual(MobileSyncUserDefaultsPreferences.preferenceKey, "MobileSyncEnabledLab")
        // Distinct from the iOS app's own Keychain service, too.
        XCTAssertNotEqual(MobileSyncIdentity.keychainService, "com.usagebar.mobilelab.connection")
    }

    /// The listener binds loopback and nothing else; that is a property of the
    /// server type, restated here because Serve's injected identity header is
    /// only trustworthy while Serve is the sole path in.
    func testServerBindsLoopbackOnly() {
        XCTAssertEqual(UsageSyncLoopbackHTTPServer.loopbackAddress, "127.0.0.1")
    }

    // MARK: - Packaging

    /// Pinned on purpose, like the Windows product-version assertion: a version
    /// bump has to be a deliberate edit here, never a silent drift.
    func testProductionPlistKeepsItsIdentityAndVersion() throws {
        let url = repositoryRoot.appendingPathComponent("Info.plist")
        let plist = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: url), format: nil
        ) as? [String: Any]
        let info = try XCTUnwrap(plist)
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, MobileSyncIdentity.productionBundleIdentifier)
        XCTAssertEqual(info["CFBundleName"] as? String, "UsageBar")
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "2.3.0")
        XCTAssertEqual(info["CFBundleVersion"] as? String, "30")
    }

    /// No second Mac application. Mobile Sync is a feature of UsageBar, so the
    /// separate host's bundle, build script and packaging must not have come
    /// across with the code.
    func testTheSeparateMobileHostProductWasNotImported() {
        let manager = FileManager.default
        for path in [
            "mobile-lab/macos/Info.plist",
            "scripts/build_mobile_lab_host.sh",
            "scripts/package_mobile_host_release.sh",
            "scripts/package_mobile_source_release.sh",
            "Sources/UsageBarSyncTransportProbe"
        ] {
            XCTAssertFalse(
                manager.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path),
                path
            )
        }
    }

    /// The module must not carry the lab host's identifiers in *code*. Its
    /// prose legitimately names them to explain what it deliberately does not
    /// reuse, so comments are stripped before the claim is made.
    func testNoLabNamespaceSurvivesInCode() throws {
        let manager = FileManager.default
        let base = repositoryRoot.appendingPathComponent("Sources/UsageBarMobileSyncHost")
        let walker = try XCTUnwrap(manager.enumerator(at: base, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = Self.strippingSwiftComments(from: try String(contentsOf: url, encoding: .utf8))
            scanned += 1
            XCTAssertFalse(text.contains("mobilelab"), url.lastPathComponent)
            XCTAssertFalse(text.contains("MobileSyncEnabledLab"), url.lastPathComponent)
            // Mobile Sync reads UsageBar's own defaults, never another domain.
            XCTAssertFalse(text.contains("persistentDomain"), url.lastPathComponent)
            XCTAssertFalse(text.contains("UserDefaults(suiteName"), url.lastPathComponent)
        }
        XCTAssertGreaterThan(scanned, 0)
    }

    // MARK: - Helpers

    /// Drops `//` comments so a source assertion tests code rather than prose.
    private static func strippingSwiftComments(from source: String) -> String {
        source.components(separatedBy: .newlines).map { line -> String in
            guard let range = line.range(of: "//") else { return line }
            return String(line[..<range.lowerBound])
        }.joined(separator: "\n")
    }
}
