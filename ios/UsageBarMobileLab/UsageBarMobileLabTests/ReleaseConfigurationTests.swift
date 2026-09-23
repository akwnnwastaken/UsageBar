import XCTest

/// The v0.1.0 release contract for the Xcode project.
///
/// UsageBar Mobile is distributed as source that other people sign with their
/// own Apple account. That makes two things testable that were previously just
/// conventions: the project must carry no maintainer identity, and a
/// self-builder must be able to re-namespace it from an untracked local file
/// without editing a tracked one.
final class ReleaseConfigurationTests: XCTestCase {
    private static let releaseVersion = "0.1.0"
    private static let defaultBundleBase = "com.usagebar.mobilelab"

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UsageBarMobileLabTests
            .deletingLastPathComponent()   // UsageBarMobileLab (project dir)
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var pbxproj: String {
        get throws { try text("UsageBarMobileLab.xcodeproj/project.pbxproj") }
    }

    private var signingConfig: String {
        get throws { try text("Config/Signing.xcconfig") }
    }

    /// The settings an xcconfig assigns, last assignment winning, with `$(...)`
    /// references left unresolved — enough to assert the defaults and the
    /// derivation without asking xcodebuild for them.
    private func assignments(in xcconfig: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in xcconfig.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "_" }) else { continue }
            result[key] = String(trimmed[trimmed.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    // MARK: - Version

    func testEveryTargetCarriesTheReleaseVersionThroughOneSetting() throws {
        let project = try pbxproj
        for line in project.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("MARKETING_VERSION") {
                XCTAssertEqual(trimmed, "MARKETING_VERSION = \"$(USAGEBAR_MOBILE_VERSION)\";")
            }
            if trimmed.hasPrefix("CURRENT_PROJECT_VERSION") {
                XCTAssertEqual(trimmed, "CURRENT_PROJECT_VERSION = \"$(USAGEBAR_MOBILE_BUILD)\";")
            }
        }
        XCTAssertTrue(project.contains("MARKETING_VERSION"))

        let settings = assignments(in: try signingConfig)
        XCTAssertEqual(settings["USAGEBAR_MOBILE_VERSION"], Self.releaseVersion)
        XCTAssertEqual(settings["USAGEBAR_MOBILE_BUILD"], "1")
    }

    /// There is no separate Mac host product to keep a version in step with any
    /// more: Mobile Sync is a feature of UsageBar, and UsageBar's own plist is
    /// the Mac side of this release.
    ///
    /// The two numbers are deliberately apart: the phone app carries 0.1.0 and
    /// UsageBar carries 2.3.0. They are versioned separately on purpose — the
    /// companion's own product version advances with its UI work, not with each
    /// desktop release — and this test exists so that stays a decision rather
    /// than an oversight.
    func testThereIsNoSeparateMacHostProductToVersion() throws {
        let repositoryRoot = projectRoot
            .deletingLastPathComponent()   // ios
            .deletingLastPathComponent()   // repository root
        let manager = FileManager.default
        for path in [
            "mobile-lab/macos/Info.plist",
            "scripts/build_mobile_lab_host.sh",
            "scripts/package_mobile_host_release.sh"
        ] {
            XCTAssertFalse(
                manager.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path),
                path
            )
        }

        let plist = try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: repositoryRoot.appendingPathComponent("Info.plist")),
            format: nil
        ) as? [String: Any]
        let info = try XCTUnwrap(plist)
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "local.codex.usagebar")
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "2.3.0")
    }

    // MARK: - Overrideable bundle namespace

    func testBundleIdentifiersAreBuildSettingsNotLiterals() throws {
        let project = try pbxproj
        XCTAssertFalse(
            project.contains(Self.defaultBundleBase),
            "the project file must not hard-code a bundle namespace"
        )
        for setting in ["USAGEBAR_MOBILE_BUNDLE_ID", "USAGEBAR_WIDGET_BUNDLE_ID", "USAGEBAR_TEST_BUNDLE_ID"] {
            XCTAssertTrue(project.contains("$(\(setting))"), "\(setting) is not referenced")
        }
    }

    func testTrackedDefaultsPreserveTheMaintainerNamespace() throws {
        let settings = assignments(in: try signingConfig)
        XCTAssertEqual(settings["USAGEBAR_BUNDLE_ID_BASE"], Self.defaultBundleBase)
        XCTAssertEqual(settings["USAGEBAR_MOBILE_BUNDLE_ID"], "$(USAGEBAR_BUNDLE_ID_BASE)")
        XCTAssertEqual(settings["USAGEBAR_WIDGET_BUNDLE_ID"], "$(USAGEBAR_BUNDLE_ID_BASE).widgets")
        XCTAssertEqual(settings["USAGEBAR_TEST_BUNDLE_ID"], "$(USAGEBAR_BUNDLE_ID_BASE).tests")
        XCTAssertEqual(settings["USAGEBAR_KEYCHAIN_GROUP_SUFFIX"], "$(USAGEBAR_BUNDLE_ID_BASE).shared")
    }

    /// The whole override mechanism is this one ordering. If the local include
    /// moved above the defaults, every value below it would silently win again
    /// and a self-builder's namespace would be discarded without an error.
    func testLocalSigningIsIncludedAfterEveryDefault() throws {
        let config = try signingConfig
        let include = try XCTUnwrap(config.range(of: "#include? \"LocalSigning.xcconfig\""))
        let tail = config[include.upperBound...]
        for setting in [
            "USAGEBAR_BUNDLE_ID_BASE", "USAGEBAR_MOBILE_BUNDLE_ID", "USAGEBAR_WIDGET_BUNDLE_ID",
            "USAGEBAR_TEST_BUNDLE_ID", "USAGEBAR_KEYCHAIN_GROUP_SUFFIX", "USAGEBAR_MOBILE_VERSION"
        ] {
            XCTAssertNil(
                tail.range(of: "\n\(setting) ="),
                "\(setting) is assigned after the local include and would override it"
            )
        }
    }

    /// The widget must be able to read what the app stored. Deriving both from
    /// one base is what guarantees that after a rename; two independent
    /// settings could be changed apart and would fail only on a device.
    func testKeychainGroupDerivesFromTheSameBaseAsTheApp() throws {
        let settings = assignments(in: try signingConfig)
        let suffix = try XCTUnwrap(settings["USAGEBAR_KEYCHAIN_GROUP_SUFFIX"])
        XCTAssertTrue(suffix.hasPrefix("$(USAGEBAR_BUNDLE_ID_BASE)"))

        for target in ["UsageBarMobileLab", "UsageBarWidgets"] {
            let plist = try PropertyListSerialization.propertyList(
                from: try Data(contentsOf: projectRoot.appendingPathComponent("Config/\(target).entitlements")),
                format: nil
            ) as? [String: Any]
            let groups = try XCTUnwrap(try XCTUnwrap(plist)["keychain-access-groups"] as? [String])
            XCTAssertEqual(groups, ["$(AppIdentifierPrefix)$(USAGEBAR_KEYCHAIN_GROUP_SUFFIX)"])
        }
    }

    // MARK: - No maintainer identity

    func testNoTeamIdentifierIsAssignedAnywhereInTrackedConfiguration() throws {
        for path in [
            "UsageBarMobileLab.xcodeproj/project.pbxproj",
            "Config/Signing.xcconfig",
            "Config/LocalSigning.example.xcconfig"
        ] {
            let contents = try text(path)
            XCTAssertNil(
                contents.range(of: #"DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}\b"#, options: .regularExpression),
                "\(path) assigns a literal team id"
            )
        }
    }

    func testTheSelfBuildTemplateExistsAndIsPlaceholdersOnly() throws {
        let template = try text("Config/LocalSigning.example.xcconfig")
        XCTAssertTrue(template.contains("DEVELOPMENT_TEAM = YOUR_TEAM_ID"))
        XCTAssertTrue(template.contains("com.example."))
        // A real tailnet name, address or credential has no business in a
        // template that ships to strangers.
        for forbidden in ["ts.net", "100.", "Bearer ", "@gmail", "@icloud"] {
            XCTAssertFalse(template.contains(forbidden), "template leaks \"\(forbidden)\"")
        }
    }

    // MARK: - Release branding

    func testInstalledAppNameIsTheReleaseName() throws {
        let project = try pbxproj
        XCTAssertTrue(project.contains("INFOPLIST_KEY_CFBundleDisplayName = \"UsageBar Mobile\";"))
        XCTAssertFalse(project.contains("UsageBar Mobile Lab"))
    }

    func testNoUserFacingSurfaceStillSaysLab() throws {
        let manager = FileManager.default
        var scanned = 0
        for root in ["Shared", "UsageBarMobileLab", "UsageBarWidgets"] {
            let base = projectRoot.appendingPathComponent(root)
            guard let walker = manager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let contents = try String(contentsOf: url, encoding: .utf8)
                scanned += 1
                XCTAssertFalse(
                    contents.contains("Mobile Lab"),
                    "\(url.lastPathComponent) still shows the lab name"
                )
            }
        }
        XCTAssertGreaterThan(scanned, 0)
    }

    // MARK: - Architecture unchanged by the release

    func testTheReleaseAddsNoAppGroup() throws {
        let project = try pbxproj
        XCTAssertFalse(project.contains("application-groups"))
        XCTAssertFalse(project.contains("group.com.usagebar"))
        XCTAssertFalse(try signingConfig.contains("application-groups"))
        XCTAssertFalse(try text("Config/LocalSigning.example.xcconfig").contains("application-groups"))
    }
}
