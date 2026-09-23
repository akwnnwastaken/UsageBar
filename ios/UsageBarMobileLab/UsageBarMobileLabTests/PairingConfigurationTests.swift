import XCTest
@testable import UsageBarMobileLab

/// The camera, the scanner and the architecture invariants Phase 8 must not
/// have quietly relaxed.
final class PairingConfigurationTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private var pbxproj: String {
        get throws { try source("UsageBarMobileLab.xcodeproj/project.pbxproj") }
    }

    // MARK: - Camera

    /// The description a person reads in the permission prompt has to say what
    /// the camera is actually for, and it is for exactly one thing.
    func testCameraUsageDescriptionNamesPairingOnly() throws {
        let text = try pbxproj
        let key = "INFOPLIST_KEY_NSCameraUsageDescription"
        XCTAssertTrue(text.contains(key))
        let line = try XCTUnwrap(
            text.components(separatedBy: .newlines).first { $0.contains(key) }
        ).lowercased()
        XCTAssertTrue(line.contains("pairing"))
        XCTAssertTrue(line.contains("scan"))
        XCTAssertTrue(line.contains("no photos are taken or saved"))
    }

    /// Nothing else is asked for. A scanner has no business with the photo
    /// library or the microphone.
    func testNoPhotoLibraryOrMicrophonePermissionRequested() throws {
        let text = try pbxproj
        for key in [
            "NSPhotoLibraryUsageDescription",
            "NSPhotoLibraryAddUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSLocationWhenInUseUsageDescription"
        ] {
            XCTAssertFalse(text.contains(key), key)
        }
    }

    // MARK: - Scanner

    func testScannerUsesSystemFrameworksOnly() throws {
        let scanner = try source("UsageBarMobileLab/Views/PairingScannerView.swift")
        XCTAssertTrue(scanner.contains("import AVFoundation"))
        // No third-party scanner package anywhere in the project.
        let text = try pbxproj
        for dependency in ["ZXing", "QRCodeReader", "CodeScanner", "SwiftQRScanner", "EFQRCode"] {
            XCTAssertFalse(text.contains(dependency), dependency)
        }
        XCTAssertFalse(text.contains("XCRemoteSwiftPackageReference"), "no remote packages")
    }

    /// QR only, one scan per presentation, and the camera stops when the view
    /// leaves the screen.
    func testScannerIsNarrowlyScoped() throws {
        let scanner = try source("UsageBarMobileLab/Views/PairingScannerView.swift")
        XCTAssertTrue(scanner.contains("metadataObjectTypes = [.qr]"))
        XCTAssertTrue(scanner.contains("guard !hasScanned else { return }"))
        XCTAssertTrue(scanner.contains("viewWillDisappear"))
        XCTAssertTrue(scanner.contains("session.stopRunning()"))
        // No frame retention of any kind.
        for forbidden in [
            "AVCaptureVideoDataOutput", "AVCapturePhotoOutput", "AVCaptureMovieFileOutput",
            "UIImageWriteToSavedPhotosAlbum", "PHPhotoLibrary", "write(to:"
        ] {
            XCTAssertFalse(scanner.contains(forbidden), forbidden)
        }
    }

    /// A QR that is not a UsageBar payload is ignored, never guessed at.
    func testScannerParsesStrictlyAndIgnoresAnythingElse() throws {
        let scanner = try source("UsageBarMobileLab/Views/PairingScannerView.swift")
        XCTAssertTrue(scanner.contains("UsageBarPairingPayload.decode(text)"))
    }

    // MARK: - Architecture invariants

    func testStillNoAppGroup() throws {
        let text = try pbxproj
        XCTAssertFalse(text.contains("application-groups"))
        XCTAssertFalse(text.contains("group.com.usagebar.mobilelab"))
        for target in ["UsageBarMobileLab", "UsageBarWidgets"] {
            let plist = try PropertyListSerialization.propertyList(
                from: try Data(contentsOf: projectRoot.appendingPathComponent("Config/\(target).entitlements")),
                format: nil
            ) as? [String: Any]
            XCTAssertNil(try XCTUnwrap(plist)["com.apple.security.application-groups"])
        }
    }

    func testStillOneExtensionAndNoNewBundleIdentifier() throws {
        let text = try pbxproj
        XCTAssertEqual(
            text.components(separatedBy: "productType = \"com.apple.product-type.app-extension\"").count - 1,
            1
        )
        var identifiers = Set<String>()
        for line in text.components(separatedBy: .newlines) {
            guard let range = line.range(of: "PRODUCT_BUNDLE_IDENTIFIER = ") else { continue }
            identifiers.insert(
                line[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " ;\t\""))
            )
        }
        XCTAssertEqual(identifiers, [
            "$(USAGEBAR_MOBILE_BUNDLE_ID)",
            "$(USAGEBAR_WIDGET_BUNDLE_ID)",
            "$(USAGEBAR_TEST_BUNDLE_ID)"
        ])
    }

    /// No background scheduler was added. The system surfaces already ask for
    /// values on their own schedule, and Phase 8 hardens locked and offline
    /// behaviour rather than adding another clock.
    func testNoBackgroundTasksOrPushWereAdded() throws {
        let manager = FileManager.default
        for root in ["Shared", "UsageBarMobileLab", "UsageBarWidgets"] {
            let base = projectRoot.appendingPathComponent(root)
            guard let walker = manager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                for forbidden in [
                    "import BackgroundTasks", "BGTaskScheduler", "UNUserNotificationCenter",
                    "registerForRemoteNotifications", "import NetworkExtension", "NEVPNManager"
                ] {
                    XCTAssertFalse(text.contains(forbidden), "\(url.lastPathComponent): \(forbidden)")
                }
            }
        }
        let text = try pbxproj
        XCTAssertFalse(text.contains("com.apple.developer.networking.networkextension"))
        XCTAssertFalse(text.contains("aps-environment"))
        XCTAssertFalse(text.contains("UIBackgroundModes"))
    }

    /// No Tailscale SDK, and the app never asserts an identity.
    func testNoTailscaleSDKAndNoIdentityHeaderIsEverSet() throws {
        let manager = FileManager.default
        var scanned = 0
        for root in ["Shared", "UsageBarMobileLab", "UsageBarWidgets"] {
            let base = projectRoot.appendingPathComponent(root)
            guard let walker = manager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                scanned += 1
                XCTAssertFalse(text.contains("import Tailscale"), url.lastPathComponent)
                XCTAssertFalse(text.contains("tsnet"), url.lastPathComponent)
                XCTAssertFalse(
                    text.contains("setValue(\"") && text.contains("forHTTPHeaderField: \"Tailscale"),
                    url.lastPathComponent
                )
            }
        }
        XCTAssertGreaterThan(scanned, 0)
    }
}
