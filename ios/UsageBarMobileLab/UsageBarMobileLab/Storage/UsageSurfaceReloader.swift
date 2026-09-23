import Foundation
import WidgetKit

/// The real implementation, used by the app.
///
/// Lives in the app target rather than `Shared/` because the widget extension
/// has no reason to ask *itself* to reload: WidgetKit and Control Center call
/// into the extension, not the other way round.
struct UsageSurfaceReloader: UsageSurfaceReloading {
    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    func reloadControls() {
        // Controls placed in Control Center are keyed by kind; reloading all of
        // them is correct here because every UsageBar control derives from the
        // same connection, so any event worth reloading one for affects all.
        ControlCenter.shared.reloadAllControls()
    }
}
