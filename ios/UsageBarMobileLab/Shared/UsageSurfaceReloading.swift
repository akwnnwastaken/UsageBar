import Foundation

/// A seam over the two system surfaces the app can ask to re-evaluate:
/// WidgetKit timelines and Control Center controls.
///
/// Both are *requests*, never guarantees — the system decides when a widget
/// timeline or a control value is actually rebuilt — so app correctness must
/// never depend on either call succeeding. Keeping them behind one protocol
/// means the app has a single place that knows "the connection changed, tell
/// the surfaces", instead of `WidgetCenter` and `ControlCenter` calls
/// scattered through the store, and it lets tests observe the requests.
///
/// Widgets and controls are separate methods rather than one `reloadAll()`
/// because they are separate system subsystems with separate budgets, and a
/// future caller may legitimately need only one of them.
public protocol UsageSurfaceReloading: Sendable {
    func reloadWidgets()
    func reloadControls()
}

/// Records requests instead of making them.
public final class RecordingSurfaceReloader: UsageSurfaceReloading, @unchecked Sendable {
    public private(set) var widgetReloadCount = 0
    public private(set) var controlReloadCount = 0

    /// Called *before* each recorded request, so a test can assert what the
    /// world looked like at the moment the reload was asked for — which is how
    /// "credentials are gone before the surfaces are told" gets proven rather
    /// than assumed.
    public var onReloadRequested: (() -> Void)?

    public init() {}

    public func reloadWidgets() {
        onReloadRequested?()
        widgetReloadCount += 1
    }

    public func reloadControls() {
        onReloadRequested?()
        controlReloadCount += 1
    }
}
