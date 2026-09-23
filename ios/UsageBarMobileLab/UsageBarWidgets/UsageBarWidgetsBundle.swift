import SwiftUI
import WidgetKit

/// The widget extension's entry point.
///
/// One extension carries every UsageBar system surface: three Home/Lock Screen
/// widgets and three Control Center controls. They share the same fetch path,
/// keychain group, snapshot cache and presentation code — the sources in
/// `Shared/` are compiled into both this target and the app, so there is
/// exactly one implementation of host validation, transport security and
/// schema-v1 decoding.
///
/// Controls live here rather than in a second extension on purpose. A separate
/// target would mean a new bundle identifier, a new provisioning profile and,
/// worse, a second copy of the credential and transport rules that could drift
/// from this one.
@main
struct UsageBarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        OverviewWidget()
        CodexWidget()
        ClaudeWidget()
        UsageBarOverviewControl()
        UsageBarCodexControl()
        UsageBarClaudeControl()
    }
}
