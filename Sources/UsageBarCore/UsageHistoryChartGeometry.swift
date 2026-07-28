import CoreGraphics
import Foundation

/// Where the usage-history chart draws its samples, and which sample a pointer
/// location refers to.
///
/// The selection rule itself lives in `UsageHistoryChartModel`; this type only
/// converts between coordinates and that model. It is deliberately free of
/// AppKit so the mapping the view draws with can be verified exactly, without
/// constructing an `NSView` or synthesising `NSEvent`s.
///
/// Nothing here is cached: every call derives from the bounds it is given, so a
/// resize or a backing-scale change cannot leave stale coordinates behind.
public struct UsageHistoryChartGeometry {
    /// The chart is inset from the view bounds so the line and its end markers
    /// are not clipped. Horizontal and vertical insets differ because the
    /// markers are wider than the line is tall.
    public static let horizontalInset: CGFloat = 1
    public static let verticalInset: CGFloat = 2

    /// The shortest span the x-axis is allowed to represent. A series whose
    /// samples share one timestamp would otherwise divide by zero.
    public static let minimumDuration: TimeInterval = 1

    public let model: UsageHistoryChartModel

    public init(model: UsageHistoryChartModel) {
        self.model = model
    }

    /// The drawing rectangle for `bounds`, derived fresh on every call.
    public func chartRect(in bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: Self.horizontalInset, dy: Self.verticalInset)
    }

    /// Where `sample` sits inside `chartRect`.
    ///
    /// X comes from elapsed time, not array position, because samples are not
    /// evenly spaced: the first displayed sample sits on `minX`, the last on
    /// `maxX`, and the rest fall proportionally between them. A lone sample is
    /// centred instead, since it spans no time at all.
    ///
    /// Y comes from `UsageHistoryChartModel.normalizedY(for:)`, which already
    /// clamps the percentage and applies the chart's adaptive vertical bounds.
    public func point(for sample: UsageHistorySample, in chartRect: CGRect) -> CGPoint {
        guard
            let first = model.displaySamples.first,
            let last = model.displaySamples.last
        else {
            return CGPoint(x: chartRect.midX, y: chartRect.midY)
        }

        let duration = max(
            Self.minimumDuration,
            last.recordedAt.timeIntervalSince(first.recordedAt)
        )
        let elapsed = sample.recordedAt.timeIntervalSince(first.recordedAt)
        let x = model.displaySamples.count == 1
            ? chartRect.midX
            : chartRect.minX + CGFloat(elapsed / duration) * chartRect.width
        let y = chartRect.minY + model.normalizedY(for: sample.remainingPercent) * chartRect.height
        return CGPoint(x: x, y: y)
    }

    /// The sample a pointer at `location` refers to, or `nil` when nothing is
    /// hovered.
    ///
    /// Eligibility is tested against the **full bounds**, not the inset chart
    /// rectangle: the pointer is still meaningfully over the chart while it is
    /// in the one- or two-point inset strip, and the model clamps the resulting
    /// out-of-range progress onto the first or last sample. A non-finite
    /// location fails the containment test and reports nothing.
    public func hoveredSample(at location: CGPoint, in bounds: CGRect) -> UsageHistorySample? {
        let chartRect = chartRect(in: bounds)
        guard
            chartRect.width > 0,
            !model.displaySamples.isEmpty,
            bounds.contains(location)
        else {
            return nil
        }

        let progress = (location.x - chartRect.minX) / chartRect.width
        return model.nearestDisplaySample(toNormalizedX: progress)
    }
}
