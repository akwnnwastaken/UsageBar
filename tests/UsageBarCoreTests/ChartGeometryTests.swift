import CoreGraphics
import XCTest
@testable import UsageBarCore

/// The coordinate mapping the usage-history chart draws with.
///
/// `UsageHistoryChartModel` already decides *which* sample a normalized
/// position refers to, and that rule is covered in `CorePolicyTests`. These
/// tests cover the part that used to live inside the AppKit view and could not
/// be checked without synthesising pointer events: the chart rectangle, where a
/// sample lands inside it, and how a pointer location becomes a selection.
///
/// The numbers are deliberately literal. If the chart insets or the placement
/// formula ever change, that is a visible change and these must be updated
/// consciously.
final class ChartGeometryTests: XCTestCase {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)

    /// Samples at explicit second offsets, so uneven spacing is expressible.
    private func series(_ points: [(offset: Double, percent: Int)]) -> [UsageHistorySample] {
        points.map {
            UsageHistorySample(
                recordedAt: Self.base.addingTimeInterval($0.offset),
                remainingPercent: $0.percent
            )
        }
    }

    private func geometry(_ points: [(offset: Double, percent: Int)]) -> UsageHistoryChartGeometry {
        UsageHistoryChartGeometry(model: UsageHistoryChartModel(samples: series(points)))
    }

    /// The chart size the menu actually builds its sparkline at.
    private let bounds = CGRect(x: 0, y: 0, width: 180, height: 34)

    // MARK: - Chart rectangle

    func testChartRectInsetsBoundsByOneAndTwoPoints() {
        XCTAssertEqual(UsageHistoryChartGeometry.horizontalInset, 1)
        XCTAssertEqual(UsageHistoryChartGeometry.verticalInset, 2)

        let rect = geometry([(0, 50)]).chartRect(in: bounds)
        XCTAssertEqual(rect, CGRect(x: 1, y: 2, width: 178, height: 30))
    }

    func testChartRectHonoursANonZeroOrigin() {
        let offset = CGRect(x: 12, y: 7, width: 180, height: 34)
        XCTAssertEqual(
            geometry([(0, 50)]).chartRect(in: offset),
            CGRect(x: 13, y: 9, width: 178, height: 30)
        )
    }

    /// Nothing is cached, so a resized view is measured freshly. A stale
    /// rectangle would put the line and the hover guide in different places.
    func testChartRectIsRederivedForEveryBounds() {
        let chart = geometry([(0, 50), (120, 40)])
        XCTAssertEqual(chart.chartRect(in: bounds).width, 178)
        XCTAssertEqual(chart.chartRect(in: CGRect(x: 0, y: 0, width: 90, height: 20)).width, 88)
        XCTAssertEqual(chart.chartRect(in: CGRect(x: 0, y: 0, width: 300, height: 60)).width, 298)
        // ...and the first call's answer is unaffected by the later ones.
        XCTAssertEqual(chart.chartRect(in: bounds), CGRect(x: 1, y: 2, width: 178, height: 30))
    }

    // MARK: - Sample placement

    func testFirstAndLastSamplesSitOnTheChartEdges() {
        let chart = geometry([(0, 50), (120, 46), (240, 44)])
        let rect = chart.chartRect(in: bounds)
        let drawn = chart.model.displaySamples

        XCTAssertEqual(chart.point(for: drawn[0], in: rect).x, rect.minX, accuracy: 0.0001)
        XCTAssertEqual(chart.point(for: drawn[2], in: rect).x, rect.maxX, accuracy: 0.0001)
    }

    /// X follows elapsed time, not array position. Here the middle sample sits
    /// five sixths of the way along in time; an index-based chart would put it
    /// at the halfway point.
    func testIntermediateSampleIsPlacedByElapsedTimeNotIndex() {
        let chart = geometry([(0, 50), (600, 46), (720, 44)])
        let rect = chart.chartRect(in: bounds)
        let drawn = chart.model.displaySamples

        let middle = chart.point(for: drawn[1], in: rect).x
        XCTAssertEqual(middle, rect.minX + rect.width * 600.0 / 720.0, accuracy: 0.0001)
        // The index-based answer would be the centre; it must not be that.
        XCTAssertNotEqual(middle, rect.midX, accuracy: 1)
    }

    func testASingleSampleIsCentredHorizontally() {
        let chart = geometry([(0, 42)])
        let rect = chart.chartRect(in: bounds)
        let point = chart.point(for: chart.model.displaySamples[0], in: rect)

        XCTAssertEqual(point.x, rect.midX, accuracy: 0.0001)
        XCTAssertEqual(point.x, 90, accuracy: 0.0001)
    }

    /// Samples sharing one timestamp span no time. The minimum-duration guard
    /// keeps that finite and collapses them onto the left edge — they are not
    /// silently spread out as if they were evenly spaced.
    func testDuplicateTimestampsCollapseRatherThanSpreadEvenly() {
        let chart = UsageHistoryChartGeometry(model: UsageHistoryChartModel(samples: [
            UsageHistorySample(recordedAt: Self.base, remainingPercent: 50),
            UsageHistorySample(recordedAt: Self.base, remainingPercent: 44)
        ]))
        let rect = chart.chartRect(in: bounds)

        XCTAssertEqual(chart.model.displaySamples.count, 2)
        for sample in chart.model.displaySamples {
            XCTAssertEqual(chart.point(for: sample, in: rect).x, rect.minX, accuracy: 0.0001)
        }
        // Evenly spaced would have put the second sample on the right edge.
        XCTAssertNotEqual(chart.point(for: chart.model.displaySamples[1], in: rect).x, rect.maxX)
    }

    func testAnEmptyChartPlacesSamplesAtTheCentre() {
        let empty = UsageHistoryChartGeometry(model: UsageHistoryChartModel(samples: []))
        let rect = empty.chartRect(in: bounds)
        let orphan = UsageHistorySample(recordedAt: Self.base, remainingPercent: 50)

        XCTAssertEqual(empty.point(for: orphan, in: rect), CGPoint(x: rect.midX, y: rect.midY))
    }

    // MARK: - Percentage to Y

    /// Y spans the chart between the model's own adaptive bounds, and is not
    /// inverted: a higher remaining percentage is drawn higher.
    func testPercentageMapsAcrossTheChartHeightWithoutInverting() {
        let chart = geometry([(0, 33)])
        let rect = chart.chartRect(in: bounds)
        // A flat series pads to a 10-point window around the value.
        XCTAssertEqual(chart.model.lowerBound, 28)
        XCTAssertEqual(chart.model.upperBound, 38)

        func y(_ percent: Int) -> CGFloat {
            chart.point(
                for: UsageHistorySample(recordedAt: Self.base, remainingPercent: percent),
                in: rect
            ).y
        }

        XCTAssertEqual(y(28), rect.minY, accuracy: 0.0001)
        XCTAssertEqual(y(38), rect.maxY, accuracy: 0.0001)
        XCTAssertEqual(y(33), rect.midY, accuracy: 0.0001)
        XCTAssertGreaterThan(y(36), y(30))
    }

    /// The model clamps the *percentage* into 0...100 before projecting it, so
    /// an impossible reading cannot move the point further. It does not clamp
    /// the projected position: a percentage outside the chart's adaptive window
    /// lands outside the rectangle. Production never draws that, because the
    /// window is derived from the very samples being drawn — asserted below.
    func testPercentageIsClampedBeforeProjection() {
        let chart = geometry([(0, 33)])
        let rect = chart.chartRect(in: bounds)

        func y(_ percent: Int) -> CGFloat {
            chart.point(
                for: UsageHistorySample(recordedAt: Self.base, remainingPercent: percent),
                in: rect
            ).y
        }

        XCTAssertEqual(y(-40), y(0), accuracy: 0.0001)
        XCTAssertEqual(y(-1_000), y(0), accuracy: 0.0001)
        XCTAssertEqual(y(140), y(100), accuracy: 0.0001)
        XCTAssertEqual(y(1_000), y(100), accuracy: 0.0001)
    }

    /// What actually gets drawn always fits: the vertical window is computed
    /// from the displayed samples, so every drawn point sits inside the chart.
    func testEveryDrawnSampleLandsInsideTheChartRectangle() {
        for points in [
            [(0.0, 100), (120.0, 60), (240.0, 3)],
            [(0.0, 42)],
            [(0.0, 50), (120.0, 49), (240.0, 50)],
            [(0.0, 0), (120.0, 0)]
        ] {
            let chart = geometry(points.map { (offset: $0.0, percent: $0.1) })
            let rect = chart.chartRect(in: bounds)
            for sample in chart.model.displaySamples {
                let point = chart.point(for: sample, in: rect)
                XCTAssertGreaterThanOrEqual(point.y, rect.minY - 0.0001, "\(points)")
                XCTAssertLessThanOrEqual(point.y, rect.maxY + 0.0001, "\(points)")
                XCTAssertGreaterThanOrEqual(point.x, rect.minX - 0.0001, "\(points)")
                XCTAssertLessThanOrEqual(point.x, rect.maxX + 0.0001, "\(points)")
            }
        }
    }

    // MARK: - Pointer to sample

    func testHoverReturnsNilForAnEmptyChart() {
        let empty = UsageHistoryChartGeometry(model: UsageHistoryChartModel(samples: []))
        XCTAssertNil(empty.hoveredSample(at: CGPoint(x: 90, y: 17), in: bounds))
        XCTAssertNil(empty.hoveredSample(at: CGPoint(x: 0, y: 0), in: bounds))
    }

    func testASingleSampleAnswersEveryEligibleLocation() {
        let chart = geometry([(0, 42)])
        for x in stride(from: CGFloat(0), through: 179, by: 17.9) {
            XCTAssertEqual(
                chart.hoveredSample(at: CGPoint(x: x, y: 17), in: bounds)?.remainingPercent,
                42
            )
        }
    }

    func testHoverSelectsTheSampleUnderThePointer() {
        let chart = geometry([(0, 50), (120, 46), (240, 44)])
        let rect = chart.chartRect(in: bounds)

        XCTAssertEqual(
            chart.hoveredSample(at: CGPoint(x: rect.minX, y: 17), in: bounds)?.remainingPercent,
            50
        )
        XCTAssertEqual(
            chart.hoveredSample(at: CGPoint(x: rect.midX, y: 17), in: bounds)?.remainingPercent,
            46
        )
        XCTAssertEqual(
            chart.hoveredSample(at: CGPoint(x: rect.maxX, y: 17), in: bounds)?.remainingPercent,
            44
        )
    }

    /// Eligibility is the full bounds, not the inset chart rectangle. Tightening
    /// this to `chartRect.contains` would make the outer strips dead zones — a
    /// behaviour change, not a cleanup.
    func testTheInsetStripsStillHover() {
        let chart = geometry([(0, 50), (120, 46), (240, 44)])

        // Left and right strips: outside chartRect horizontally, inside bounds.
        XCTAssertFalse(chart.chartRect(in: bounds).contains(CGPoint(x: 0.5, y: 17)))
        XCTAssertEqual(
            chart.hoveredSample(at: CGPoint(x: 0.5, y: 17), in: bounds)?.remainingPercent,
            50
        )
        XCTAssertFalse(chart.chartRect(in: bounds).contains(CGPoint(x: 179.5, y: 17)))
        XCTAssertEqual(
            chart.hoveredSample(at: CGPoint(x: 179.5, y: 17), in: bounds)?.remainingPercent,
            44
        )

        // Top and bottom strips: outside chartRect vertically, still eligible.
        XCTAssertFalse(chart.chartRect(in: bounds).contains(CGPoint(x: 90, y: 0.5)))
        XCTAssertNotNil(chart.hoveredSample(at: CGPoint(x: 90, y: 0.5), in: bounds))
        XCTAssertNotNil(chart.hoveredSample(at: CGPoint(x: 90, y: 33.5), in: bounds))
    }

    func testLocationsOutsideTheBoundsHoverNothing() {
        let chart = geometry([(0, 50), (120, 46), (240, 44)])
        for outside in [
            CGPoint(x: -1, y: 17),      // left
            CGPoint(x: 181, y: 17),     // right
            CGPoint(x: 90, y: -1),      // below
            CGPoint(x: 90, y: 35),      // above
            // Containment is half-open, so the far edges are already outside.
            CGPoint(x: 180, y: 17),     // exactly maxX
            CGPoint(x: 90, y: 34)       // exactly maxY
        ] {
            XCTAssertNil(chart.hoveredSample(at: outside, in: bounds), "\(outside)")
        }
        // The near edges are inside, so the pointer is not dead on arrival.
        XCTAssertNotNil(chart.hoveredSample(at: CGPoint(x: 0, y: 0), in: bounds))
    }

    func testDegenerateBoundsHoverNothing() {
        let chart = geometry([(0, 50), (120, 46)])
        // Too narrow for the 1-point insets to leave any width.
        for narrow in [
            CGRect(x: 0, y: 0, width: 0, height: 34),
            CGRect(x: 0, y: 0, width: 2, height: 34),
            CGRect(x: 0, y: 0, width: 1, height: 34),
            CGRect.zero
        ] {
            XCTAssertLessThanOrEqual(chart.chartRect(in: narrow).width, 0)
            XCTAssertNil(chart.hoveredSample(at: CGPoint(x: 0, y: 0), in: narrow), "\(narrow)")
        }
    }

    func testNonFinitePointerLocationsHoverNothing() {
        let chart = geometry([(0, 50), (120, 46), (240, 44)])
        for broken in [
            CGPoint(x: CGFloat.nan, y: 17),
            CGPoint(x: 90, y: CGFloat.nan),
            CGPoint(x: CGFloat.infinity, y: 17),
            CGPoint(x: -CGFloat.infinity, y: 17),
            CGPoint(x: 90, y: CGFloat.infinity)
        ] {
            XCTAssertNil(chart.hoveredSample(at: broken, in: bounds), "\(broken)")
        }
    }

    // MARK: - Composition with the selection model

    /// The geometry must agree with the already-tested model: converting a
    /// location and asking the model directly are the same answer, including
    /// the tie-to-the-earlier-sample rule.
    func testGeometryAgreesWithTheModelIncludingTies() {
        let chart = geometry([(0, 48), (300, 46)])
        let rect = chart.chartRect(in: bounds)

        for step in 0...40 {
            let x = rect.minX + rect.width * CGFloat(step) / 40
            let progress = (x - rect.minX) / rect.width
            XCTAssertEqual(
                chart.hoveredSample(at: CGPoint(x: x, y: 17), in: bounds),
                chart.model.nearestDisplaySample(toNormalizedX: progress)
            )
        }

        // Exactly halfway resolves to the earlier sample, never an average.
        let middle = chart.hoveredSample(at: CGPoint(x: rect.midX, y: 17), in: bounds)
        XCTAssertEqual(middle?.remainingPercent, 48)
        XCTAssertEqual(middle?.recordedAt, Self.base)
    }

    /// Only samples drawn since the most recent reset can be hovered; the
    /// pre-reset history is not on the line.
    func testHoverCannotReachSamplesBeforeTheLatestReset() {
        let chart = geometry([(0, 80), (120, 50), (240, 30), (360, 100), (480, 90), (600, 70)])
        XCTAssertEqual(chart.model.displaySamples.map(\.remainingPercent), [100, 90, 70])

        // Sweep the whole width, stopping short of maxX which is not contained.
        for step in 0...35 {
            let x = CGFloat(step) * 5
            let selected = chart.hoveredSample(at: CGPoint(x: x, y: 17), in: bounds)
            XCTAssertNotNil(selected, "x=\(x)")
            guard let selected else { continue }
            XCTAssertTrue(chart.model.displaySamples.contains(selected))
            XCTAssertTrue([100, 90, 70].contains(selected.remainingPercent))
        }
    }

    /// The hovered value matches the drawn line, so an isolated one-point spike
    /// reports its smoothed value rather than the raw reading.
    func testHoverReportsTheSmoothedValueThatIsDrawn() {
        let chart = geometry([(0, 33), (120, 34), (240, 33)])
        XCTAssertEqual(chart.model.samples.map(\.remainingPercent), [33, 34, 33])

        let rect = chart.chartRect(in: bounds)
        let middle = chart.hoveredSample(at: CGPoint(x: rect.midX, y: 17), in: bounds)
        XCTAssertEqual(middle?.recordedAt, Self.base.addingTimeInterval(120))
        XCTAssertEqual(middle?.remainingPercent, 33)

        // And the point drawn for it uses the same smoothed value.
        guard let middle else { return XCTFail("no hovered sample") }
        XCTAssertEqual(
            chart.point(for: middle, in: rect).y,
            chart.point(
                for: UsageHistorySample(recordedAt: middle.recordedAt, remainingPercent: 33),
                in: rect
            ).y,
            accuracy: 0.0001
        )
    }
}
