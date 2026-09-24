import ImageIO
import XCTest

/// The Home Screen icon is compiled into the app, not merely present in the
/// repository.
///
/// These tests run inside the app as their host, so `Bundle.main` is the built
/// UsageBar Mobile bundle: what they read is what an iPhone installs.
final class AppIconConfigurationTests: XCTestCase {
    /// actool writes the primary icon's name into the built Info.plist only
    /// when the target's `ASSETCATALOG_COMPILER_APPICON_NAME` resolved to an
    /// icon set it actually compiled.
    func testBuiltAppDeclaresTheAppIconSet() throws {
        let icons = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            "the built app declares no icon at all"
        )
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
    }

    /// actool also emits the 60pt @2x Home Screen rendition beside the
    /// compiled catalog and lists it in the built Info.plist — proof the icon
    /// set was rendered for the iPhone, not just shipped as a source file.
    func testBuiltAppCarriesTheRenderedHomeScreenIcon() throws {
        XCTAssertNotNil(Bundle.main.url(forResource: "Assets", withExtension: "car"))

        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        XCTAssertEqual(primary?["CFBundleIconFiles"] as? [String], ["AppIcon60x60"])

        let rendered = try XCTUnwrap(
            Bundle.main.url(forResource: "AppIcon60x60@2x", withExtension: "png"),
            "no Home Screen icon rendition in the built app"
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(rendered as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 120)
        XCTAssertEqual(image.height, 120)
    }

    /// The source is the single 1024pt square iOS expects: opaque, because iOS
    /// applies its own mask and an alpha channel is rejected for app icons.
    func testIconSourceIsAnOpaque1024Square() throws {
        let set = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UsageBarMobileLab/Assets.xcassets/AppIcon.appiconset")

        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: set.appendingPathComponent("Contents.json"))
        ) as? [String: Any]
        let images = try XCTUnwrap(manifest?["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1, "one universal 1024pt source, sized by Xcode")
        XCTAssertEqual(images[0]["size"] as? String, "1024x1024")
        XCTAssertEqual(images[0]["platform"] as? String, "ios")
        let filename = try XCTUnwrap(images[0]["filename"] as? String)

        let source = try XCTUnwrap(
            CGImageSourceCreateWithURL(set.appendingPathComponent(filename) as CFURL, nil)
        )
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1024)
        XCTAssertEqual(image.height, 1024)
        XCTAssertTrue(
            [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo),
            "an app icon must not carry an alpha channel"
        )
    }
}
