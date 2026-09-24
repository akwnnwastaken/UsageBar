import XCTest
import UsageBarSync
@testable import UsageBarMobileLab

/// The semantic remaining-usage colour, tested as arithmetic.
///
/// Deliberately no pixel assertions: what matters is that the mapping is
/// clamped, monotonic and bounded, not what a particular device renders those
/// numbers as. `hue` is the single scalar every colour derives from, so pinning
/// it pins the policy.
final class UsageLevelPresentationTests: XCTestCase {
    private let pinned = [0, 1, 12, 25, 50, 79, 100]

    // MARK: - Presentation clamp

    /// Clamping is presentation-side only. Nothing here writes back to a
    /// validated snapshot; it keeps a malformed reading from producing a
    /// nonsense colour or a bar drawn outside its own track.
    func testDisplayPercentClampsWithoutTouchingValidValues() {
        XCTAssertEqual(UsageLevelPresentation.displayPercent(-1), 0)
        XCTAssertEqual(UsageLevelPresentation.displayPercent(-999), 0)
        XCTAssertEqual(UsageLevelPresentation.displayPercent(101), 100)
        XCTAssertEqual(UsageLevelPresentation.displayPercent(9_999), 100)
        for value in pinned {
            XCTAssertEqual(UsageLevelPresentation.displayPercent(value), value)
        }
    }

    func testLevelIsTheClampedFraction() {
        XCTAssertEqual(UsageLevelPresentation.level(for: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(UsageLevelPresentation.level(for: 50), 0.5, accuracy: 0.0001)
        XCTAssertEqual(UsageLevelPresentation.level(for: 100), 1.0, accuracy: 0.0001)
        XCTAssertEqual(UsageLevelPresentation.level(for: -40), 0.0, accuracy: 0.0001)
        XCTAssertEqual(UsageLevelPresentation.level(for: 140), 1.0, accuracy: 0.0001)
    }

    // MARK: - The scale

    /// Empty is red, full is green, and the scale stops there.
    func testScaleRunsFromRedToGreenAndNoFurther() {
        XCTAssertEqual(UsageLevelPresentation.hue(for: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(UsageLevelPresentation.hue(for: 100), 0.34, accuracy: 0.0001)
        for value in [-50, 0, 1, 12, 25, 50, 79, 100, 150] {
            let hue = UsageLevelPresentation.hue(for: value)
            XCTAssertGreaterThanOrEqual(hue, 0.0, "\(value)")
            // Past green lies cyan and then blue. Stopping here is what keeps
            // the scale from reading as a rainbow.
            XCTAssertLessThanOrEqual(hue, 0.34, "\(value)")
        }
    }

    /// More remaining is always further along the scale — no band where two
    /// different readings share a colour.
    func testScaleIsStrictlyMonotonic() {
        for (lower, higher) in zip(pinned, pinned.dropFirst()) {
            XCTAssertLessThan(
                UsageLevelPresentation.hue(for: lower),
                UsageLevelPresentation.hue(for: higher),
                "\(lower)% must not colour the same as or greener than \(higher)%"
            )
        }
    }

    /// The owner's reference points, expressed as the bands they must land in:
    /// red, orange, yellow, green-ish, green.
    func testPinnedReadingsLandInTheExpectedBands() {
        // Red through orange: below the yellow midpoint.
        XCTAssertLessThan(UsageLevelPresentation.hue(for: 0), 0.02)
        XCTAssertLessThan(UsageLevelPresentation.hue(for: 12), 0.06)
        XCTAssertLessThan(UsageLevelPresentation.hue(for: 25), 0.10)
        // Yellow, around the middle of the ramp.
        XCTAssertEqual(UsageLevelPresentation.hue(for: 50), 0.17, accuracy: 0.02)
        // Green-leaning.
        XCTAssertGreaterThan(UsageLevelPresentation.hue(for: 79), 0.24)
        XCTAssertGreaterThan(UsageLevelPresentation.hue(for: 100), 0.33)
    }

    /// Out-of-range input colours exactly as the boundary it was clamped to.
    func testClampedInputsColourAsTheirBoundary() {
        XCTAssertEqual(
            UsageLevelPresentation.hue(for: -5), UsageLevelPresentation.hue(for: 0), accuracy: 0.0001
        )
        XCTAssertEqual(
            UsageLevelPresentation.hue(for: 150), UsageLevelPresentation.hue(for: 100), accuracy: 0.0001
        )
    }

    // MARK: - Colour is never the only channel

    /// The bar's length carries the same fact as its colour, so the reading
    /// survives tinted rendering, greyscale and colour-blindness. The printed
    /// percentage is the third channel and stays authoritative.
    func testBarLengthTracksTheSameValueAsTheColour() {
        for value in pinned {
            XCTAssertEqual(
                UsageLevelPresentation.level(for: value),
                Double(value) / 100,
                accuracy: 0.0001,
                "bar length must equal the remaining fraction at \(value)%"
            )
        }
    }

    /// No classification is invented anywhere in this policy.
    func testPolicyNamesNoThresholds() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Shared/ProviderPresentation.swift"),
            encoding: .utf8
        )
        let code = source
            .components(separatedBy: .newlines)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return line }
                return String(line[..<range.lowerBound])
            }
            .joined(separator: "\n")
        for invented in ["critical", "warning", "healthy", "danger", "severe"] {
            XCTAssertFalse(
                code.lowercased().contains(invented),
                "presentation must not classify a reading as \(invented)"
            )
        }
    }
}
