import XCTest
import UIKit
import UsageBarSync
@testable import UsageBarMobileLab

/// The Phase-7 architecture contract: controls live in the *existing* widget
/// extension, under the existing bundle identifier, with no App Group and no
/// action that can change anything.
///
/// Several of these read project files rather than types. A `WidgetBundle` and
/// a `ControlWidget` live in an app extension, and an app extension cannot be
/// `@testable`-imported, so the registration itself is only assertable as
/// source. That is a real limitation, not a shortcut: these tests catch a
/// control being dropped from the bundle or a kind being renamed, which are the
/// two regressions that would silently remove controls people have placed.
final class ControlConfigurationTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UsageBarMobileLabTests
            .deletingLastPathComponent()   // UsageBarMobileLab (project dir)
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var pbxproj: String {
        get throws { try source("UsageBarMobileLab.xcodeproj/project.pbxproj") }
    }

    // MARK: - One bundle, widgets and controls together

    func testWidgetBundleStillContainsAllThreeWidgets() throws {
        let bundle = try source("UsageBarWidgets/UsageBarWidgetsBundle.swift")
        for widget in ["OverviewWidget()", "CodexWidget()", "ClaudeWidget()"] {
            XCTAssertTrue(bundle.contains(widget), "widget bundle lost \(widget)")
        }
    }

    func testWidgetBundleContainsAllThreeControls() throws {
        let bundle = try source("UsageBarWidgets/UsageBarWidgetsBundle.swift")
        for control in [
            "UsageBarOverviewControl()", "UsageBarCodexControl()", "UsageBarClaudeControl()"
        ] {
            XCTAssertTrue(bundle.contains(control), "widget bundle is missing \(control)")
        }
    }

    /// The temporary feasibility probe must not survive into the product.
    func testTemporaryFeasibilityControlIsGone() throws {
        let bundle = try source("UsageBarWidgets/UsageBarWidgetsBundle.swift")
        let controls = try source("UsageBarWidgets/Controls.swift")
        XCTAssertFalse(bundle.contains("UsageBarTestControl"))
        XCTAssertFalse(controls.contains("UsageBarTestControl"))
    }

    // MARK: - Stable control kinds

    /// iOS keys a *placed* control by its kind. Changing one of these strings
    /// does not rename a control; it deletes the one the user added and offers
    /// a new one. Pinned deliberately.
    func testOverviewControlKindIsStable() {
        XCTAssertEqual(ControlKindID.overview, "UsageBarControlOverview")
    }

    func testCodexControlKindIsStable() {
        XCTAssertEqual(ControlKindID.codex, "UsageBarControlCodex")
    }

    func testClaudeControlKindIsStable() {
        XCTAssertEqual(ControlKindID.claude, "UsageBarControlClaude")
    }

    func testControlKindsAreDistinctAndUsedByTheControls() throws {
        let kinds = [ControlKindID.overview, ControlKindID.codex, ControlKindID.claude]
        XCTAssertEqual(Set(kinds).count, 3)

        let controls = try source("UsageBarWidgets/Controls.swift")
        for kind in ["ControlKindID.overview", "ControlKindID.codex", "ControlKindID.claude"] {
            XCTAssertTrue(controls.contains(kind), "\(kind) is not used by any control")
        }
        // And never spelled as a literal, which is how a kind drifts.
        for literal in kinds {
            XCTAssertFalse(
                controls.contains("\"\(literal)\""),
                "control kinds must come from ControlKindID, not a literal"
            )
        }
    }

    /// Control kinds must not collide with widget kinds: they are separate
    /// namespaces to the system but not to a careless rename.
    func testControlKindsDoNotCollideWithWidgetKinds() {
        let controlKinds = Set([ControlKindID.overview, ControlKindID.codex, ControlKindID.claude])
        let widgetKinds: Set<String> = ["UsageBarOverview", "UsageBarCodex", "UsageBarClaude"]
        XCTAssertTrue(controlKinds.isDisjoint(with: widgetKinds))
    }

    // MARK: - No second extension, no new identifier

    func testProjectDeclaresExactlyOneAppExtensionTarget() throws {
        let occurrences = try pbxproj
            .components(separatedBy: "productType = \"com.apple.product-type.app-extension\"")
            .count - 1
        XCTAssertEqual(occurrences, 1, "Phase 7 must not add a second extension target")
    }

    func testProjectDeclaresNoNewBundleIdentifier() throws {
        let text = try pbxproj
        var found = Set<String>()
        for line in text.components(separatedBy: .newlines) {
            guard let range = line.range(of: "PRODUCT_BUNDLE_IDENTIFIER = ") else { continue }
            found.insert(
                line[range.upperBound...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ;\t\""))
            )
        }
        // Since v0.1.0 the identifiers are build settings, so a self-builder can
        // re-namespace the project without editing the project file. The values
        // they resolve to are asserted in ReleaseConfigurationTests.
        XCTAssertEqual(found, [
            "$(USAGEBAR_MOBILE_BUNDLE_ID)",
            "$(USAGEBAR_WIDGET_BUNDLE_ID)",
            "$(USAGEBAR_TEST_BUNDLE_ID)"
        ])
        // The identifier a separate controls extension would have needed.
        XCTAssertFalse(text.contains("com.usagebar.mobilelab.controls"))
    }

    func testControlsAddNoAppGroupOrNewKeychainGroup() throws {
        let text = try pbxproj
        XCTAssertFalse(text.contains("application-groups"))
        XCTAssertFalse(text.contains("group.com.usagebar.mobilelab"))

        for target in ["UsageBarMobileLab", "UsageBarWidgets"] {
            let url = projectRoot.appendingPathComponent("Config/\(target).entitlements")
            let plist = try PropertyListSerialization.propertyList(
                from: try Data(contentsOf: url), format: nil
            ) as? [String: Any]
            let entitlements = try XCTUnwrap(plist)
            XCTAssertNil(entitlements["com.apple.security.application-groups"])
            XCTAssertEqual(
                entitlements["keychain-access-groups"] as? [String],
                ["$(AppIdentifierPrefix)$(USAGEBAR_KEYCHAIN_GROUP_SUFFIX)"],
                "controls must reuse the one existing keychain group"
            )
        }
    }

    /// Controls needed no Apple capability beyond what the extension already
    /// had — proven on hardware, and locked here so a future edit cannot add
    /// one unnoticed.
    func testWidgetExtensionInfoPlistIsUnchangedByControls() throws {
        let url = projectRoot.appendingPathComponent("Config/UsageBarWidgets-Info.plist")
        let plist = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: url), format: nil
        ) as? [String: Any]
        let extensionDict = try XCTUnwrap((try XCTUnwrap(plist))["NSExtension"] as? [String: Any])
        XCTAssertEqual(
            extensionDict["NSExtensionPointIdentifier"] as? String,
            "com.apple.widgetkit-extension",
            "controls ship from the widgetkit extension point, not a new one"
        )
    }

    // MARK: - The action

    func testEveryControlButtonOpensTheApp() throws {
        let controls = try source("UsageBarWidgets/Controls.swift")
        let buttons = controls.components(separatedBy: "ControlWidgetButton(").count - 1
        let opens = controls.components(separatedBy: "ControlWidgetButton(action: OpenUsageBarIntent())").count - 1
        XCTAssertEqual(buttons, 3)
        XCTAssertEqual(opens, 3, "every control button must use the app-opening intent")
    }

    /// The strongest form of "controls cannot change provider state": there is
    /// no intent in the project that could. A control is one brush of a thumb
    /// away in Control Center, so the safety here is structural rather than
    /// conditional.
    func testNoDestructiveOrProviderChangingIntentExists() throws {
        let manager = FileManager.default
        var intentTypes = Set<String>()
        var scanned = 0

        for root in ["Shared", "UsageBarMobileLab", "UsageBarWidgets"] {
            let base = projectRoot.appendingPathComponent(root)
            guard let walker = manager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                scanned += 1
                for line in text.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("struct ") || trimmed.hasPrefix("public struct ") else { continue }
                    guard trimmed.contains("Intent") else { continue }
                    guard let colon = trimmed.firstIndex(of: ":") else { continue }
                    let name = trimmed[..<colon]
                        .replacingOccurrences(of: "public struct ", with: "")
                        .replacingOccurrences(of: "struct ", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    intentTypes.insert(name)
                }
            }
        }

        XCTAssertGreaterThan(scanned, 0)
        XCTAssertEqual(
            intentTypes, ["OpenUsageBarIntent"],
            "the only app intent in this project must be the one that opens the app"
        )
    }

    /// A control's action is stored by the system and surfaced in Shortcuts, so
    /// what it carries leaves the app's control. It must carry exactly one
    /// thing: which screen to open.
    func testControlActionCarriesNoCredentialOrEndpoint() throws {
        let mirror = Mirror(reflecting: OpenUsageBarIntent())
        XCTAssertEqual(mirror.children.count, 1, "the intent must hold only its target")
        let label = try XCTUnwrap(mirror.children.first?.label)
        XCTAssertTrue(label.contains("target"))

        // Comments are stripped first: this is a claim about what the intent
        // *does*, and its documentation legitimately names the things it must
        // never touch.
        let code = Self.strippingComments(from: try source("Shared/OpenUsageBarIntent.swift")).lowercased()
        for forbidden in [
            "accesskey", "bearer", "authorization", "keychain", "connectionstore",
            "ts.net", "tailscale", "urlsession", "snapshot", "100."
        ] {
            XCTAssertFalse(code.contains(forbidden), "the open intent references \"\(forbidden)\"")
        }
    }

    func testOpenIntentOpensTheContainingApp() {
        XCTAssertTrue(
            OpenUsageBarIntent.openAppWhenRun,
            "a control that did not open the app would perform no action at all"
        )
        XCTAssertEqual(OpenUsageBarIntent().target, .dashboard)
    }

    /// Apple requires the app-opening intent to be a member of both the app and
    /// the widget extension. It is in `Shared/`, so the proof is that both
    /// Sources phases compile it.
    func testOpenIntentIsBuiltIntoBothAppAndExtension() throws {
        let occurrences = try pbxproj
            .components(separatedBy: "OpenUsageBarIntent.swift in Sources */,")
            .count - 1
        XCTAssertEqual(occurrences, 2, "the intent must be in both target Sources phases")
    }

    /// Drops `//` comments so a source assertion tests code rather than prose.
    /// Sufficient here because these files contain no block comments and no
    /// string literal containing "//".
    private static func strippingComments(from source: String) -> String {
        source
            .components(separatedBy: .newlines)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return line }
                return String(line[..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - Symbols

    /// Control Center may render the glyph and drop every word, so a symbol
    /// that does not resolve is an empty control, not a cosmetic issue.
    func testControlSymbolsExistInTheInstalledSDK() {
        for symbol in [ControlSymbol.overview, ControlSymbol.codex, ControlSymbol.claude] {
            XCTAssertNotNil(UIImage(systemName: symbol), "missing SF Symbol \(symbol)")
        }
    }

    func testControlSymbolsAreDistinct() {
        XCTAssertEqual(
            Set([ControlSymbol.overview, ControlSymbol.codex, ControlSymbol.claude]).count, 3,
            "identical glyphs would make the three controls indistinguishable once text is dropped"
        )
    }

    // MARK: - Cache reuse

    /// Controls run in the same extension as the widgets, so they share its one
    /// private cache rather than adding a third. The app's cache stays separate.
    func testControlsAndWidgetsShareTheExtensionCacheButNotTheAppsCache() {
        XCTAssertEqual(UsageSurfaceResolver.extensionCacheFileName, "widget-snapshot-v1.json")
        let extensionCache = FileSnapshotCache(fileName: UsageSurfaceResolver.extensionCacheFileName)
        let appCache = FileSnapshotCache()
        XCTAssertNotEqual(extensionCache.fileURL, appCache.fileURL)
    }
}
