import XCTest
import WidgetKit
import UsageBarSync
@testable import UsageBarMobileLab

/// The Phase-6 architecture contract: no App Group, credentials shared through
/// the keychain only, caches private per target.
final class WidgetConfigurationTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UsageBarMobileLabTests
            .deletingLastPathComponent()   // UsageBarMobileLab (project dir)
    }

    private func entitlements(_ name: String) throws -> [String: Any] {
        let url = projectRoot.appendingPathComponent("Config/\(name).entitlements")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    // MARK: - No App Group

    /// The hard rule of this checkpoint. If either target ever gains an app
    /// group, the architecture silently stopped being the one that was proven.
    func testNeitherTargetDeclaresAnAppGroup() throws {
        for target in ["UsageBarMobileLab", "UsageBarWidgets"] {
            let keys = try entitlements(target).keys
            XCTAssertFalse(
                keys.contains("com.apple.security.application-groups"),
                "\(target) must not declare an app group"
            )
        }
    }

    func testProjectContainsNoAppGroupIdentifier() throws {
        let pbxproj = projectRoot
            .appendingPathComponent("UsageBarMobileLab.xcodeproj/project.pbxproj")
        let text = try String(contentsOf: pbxproj, encoding: .utf8)
        XCTAssertFalse(text.contains("group.com.usagebar.mobilelab"))
        XCTAssertFalse(text.contains("application-groups"))
    }

    // MARK: - Shared keychain

    func testBothTargetsDeclareTheSameKeychainAccessGroup() throws {
        let app = try XCTUnwrap(entitlements("UsageBarMobileLab")["keychain-access-groups"] as? [String])
        let widget = try XCTUnwrap(entitlements("UsageBarWidgets")["keychain-access-groups"] as? [String])
        XCTAssertEqual(app, widget)
        XCTAssertEqual(app, ["$(AppIdentifierPrefix)$(USAGEBAR_KEYCHAIN_GROUP_SUFFIX)"])
    }

    /// The literal team prefix must never be written down; it is substituted at
    /// build time from the signing identity.
    func testAccessGroupUsesBuildTimePrefixNotALiteralTeamID() throws {
        for target in ["UsageBarMobileLab", "UsageBarWidgets"] {
            let groups = try XCTUnwrap(entitlements(target)["keychain-access-groups"] as? [String])
            for group in groups {
                XCTAssertTrue(group.hasPrefix("$(AppIdentifierPrefix)"))
                // A literal Apple team id is 10 uppercase alphanumerics.
                let literal = group.range(
                    of: #"^[A-Z0-9]{10}\."#,
                    options: .regularExpression
                )
                XCTAssertNil(literal, "\(target) entitlement embeds a literal team id")
            }
        }
    }

    func testNoLiteralTeamIdentifierInTrackedProjectSources() throws {
        let manager = FileManager.default
        let roots = ["Shared", "UsageBarMobileLab", "UsageBarWidgets", "UsageBarMobileLabTests", "Config"]
        var scanned = 0
        for root in roots {
            let base = projectRoot.appendingPathComponent(root)
            guard let walker = manager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker {
                guard ["swift", "entitlements", "plist"].contains(url.pathExtension) else { continue }
                // LocalSigning.xcconfig is untracked and deliberately excluded.
                guard url.lastPathComponent != "LocalSigning.xcconfig" else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                scanned += 1
                XCTAssertNil(
                    text.range(of: #"DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}"#, options: .regularExpression),
                    "\(url.lastPathComponent) contains a literal team id"
                )
            }
        }
        XCTAssertGreaterThan(scanned, 0)
    }

    // MARK: - Caches stay separate

    /// The app and the widget must not share a cache file. Without an App Group
    /// they are in different containers anyway, but the file names differ too so
    /// the distinction survives any future container change.
    func testAppAndWidgetUseDistinctCacheFiles() {
        let appCache = FileSnapshotCache()
        let widgetCache = FileSnapshotCache(fileName: UsageSurfaceResolver.extensionCacheFileName)
        XCTAssertNotEqual(appCache.fileURL, widgetCache.fileURL)
        XCTAssertEqual(appCache.fileURL.lastPathComponent, "snapshot-v1.json")
        XCTAssertEqual(widgetCache.fileURL.lastPathComponent, "widget-snapshot-v1.json")
    }

    /// Credentials live in the keychain and must never reach a snapshot cache.
    func testWidgetCacheHoldsNoCredentialOrHost() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-cache-\(UUID().uuidString).json")
        let cache = FileSnapshotCache(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try cache.store(try TestFixtures.decodedBasicSnapshot())
        let raw = try String(contentsOf: url, encoding: .utf8).lowercased()
        for forbidden in [
            "ts.net", "example-tail", "usagebar-test", "bearer", "authorization",
            TestFixtures.accessKey.lowercased(), "tailscale", "100.", "https"
        ] {
            XCTAssertFalse(raw.contains(forbidden), "widget cache leaked \"\(forbidden)\"")
        }
    }

    /// The widget reads credentials through the same abstraction the app writes
    /// through — one store type, one keychain group.
    func testWidgetReadsConnectionThroughSharedStoreAbstraction() async throws {
        let shared = InMemoryConnectionStore()
        try shared.save(TestFixtures.connection)

        let fetched = try TestFixtures.decodedBasicSnapshot()
        let provider = UsageTimelineProvider(
            store: shared,
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(fetched))
        )
        let entry = await provider.currentEntry()
        XCTAssertEqual(entry.state, .loaded(fetched))
    }

    // MARK: - Supported families

    func testOverviewSupportsHomeAndLockScreenFamilies() {
        XCTAssertEqual(
            Set(WidgetFamilySupport.overview),
            Set([.systemSmall, .systemMedium, .accessoryRectangular])
        )
    }

    func testProviderWidgetsSupportAllAccessoryFamilies() {
        let families = Set(WidgetFamilySupport.provider)
        XCTAssertTrue(families.contains(.accessoryCircular))
        XCTAssertTrue(families.contains(.accessoryRectangular))
        XCTAssertTrue(families.contains(.accessoryInline))
        XCTAssertTrue(families.contains(.systemSmall))
    }

    // MARK: - Surface reload requests

    /// Widgets and controls both read the shared keychain, so every event that
    /// changes the connection has to reach both surfaces. These assert each
    /// one separately: a single `reloadCount` could not tell a regression that
    /// dropped controls apart from one that worked.
    func testSuccessfulConnectRequestsWidgetAndControlReload() async throws {
        let reloader = RecordingSurfaceReloader()
        let store = await AppSnapshotStore(
            store: InMemoryConnectionStore(),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(try TestFixtures.decodedBasicSnapshot())),
            surfaces: reloader
        )
        _ = await store.connect(host: TestFixtures.host, accessKey: TestFixtures.accessKey)
        XCTAssertEqual(reloader.widgetReloadCount, 1)
        XCTAssertEqual(reloader.controlReloadCount, 1)
    }

    func testSuccessfulRefreshRequestsWidgetAndControlReload() async throws {
        let reloader = RecordingSurfaceReloader()
        let store = await AppSnapshotStore(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .success(try TestFixtures.decodedBasicSnapshot())),
            surfaces: reloader
        )
        await store.refresh()
        XCTAssertEqual(reloader.widgetReloadCount, 1)
        XCTAssertEqual(reloader.controlReloadCount, 1)
    }

    /// Forget must reload promptly: that is what turns credential removal into
    /// an immediate revocation of the widget's and the control's display
    /// authorization.
    func testForgetConnectionRequestsWidgetAndControlReload() async throws {
        let reloader = RecordingSurfaceReloader()
        let store = await AppSnapshotStore(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(snapshot: try TestFixtures.decodedBasicSnapshot()),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure)),
            surfaces: reloader
        )
        await store.forgetConnection()
        XCTAssertEqual(reloader.widgetReloadCount, 1)
        XCTAssertEqual(reloader.controlReloadCount, 1)
    }

    /// Ordering, not just occurrence. If the surfaces were told to rebuild
    /// while the keychain still held the connection, a control could re-read
    /// the credential it was supposed to have lost and legitimately redisplay
    /// the usage the user just disconnected from.
    func testForgetConnectionRemovesCredentialsBeforeRequestingReload() async throws {
        let connectionStore = InMemoryConnectionStore(connection: TestFixtures.connection)
        let reloader = RecordingSurfaceReloader()
        var credentialsAtReload: [UsageSyncConnection?] = []
        reloader.onReloadRequested = { credentialsAtReload.append(connectionStore.load()) }

        let store = await AppSnapshotStore(
            store: connectionStore,
            cache: InMemorySnapshotCache(snapshot: try TestFixtures.decodedBasicSnapshot()),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure)),
            surfaces: reloader
        )
        await store.forgetConnection()

        XCTAssertEqual(credentialsAtReload.count, 2, "both surfaces should have been asked")
        XCTAssertTrue(
            credentialsAtReload.allSatisfy { $0 == nil },
            "the connection must already be gone when the surfaces are told to re-evaluate"
        )
    }

    /// A failed refresh changes nothing the surfaces display — the cached
    /// reading they already hold is still the right answer — so it spends none
    /// of the system's reload budget. Widgets and controls behave identically
    /// here on purpose.
    func testFailedRefreshRequestsNeitherReload() async {
        let reloader = RecordingSurfaceReloader()
        let store = await AppSnapshotStore(
            store: InMemoryConnectionStore(connection: TestFixtures.connection),
            cache: InMemorySnapshotCache(),
            client: ScriptedFetcher(outcome: .failure(SnapshotFetchError.transportFailure)),
            surfaces: reloader
        )
        await store.refresh()
        XCTAssertEqual(reloader.widgetReloadCount, 0)
        XCTAssertEqual(reloader.controlReloadCount, 0)
    }
}
