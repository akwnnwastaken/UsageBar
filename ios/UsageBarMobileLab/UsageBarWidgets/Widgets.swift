import SwiftUI
import WidgetKit

/// Kind strings are stable identity: iOS keys a user's placed widgets by them,
/// so renaming one silently removes widgets people already added.
enum WidgetKindID {
    static let overview = "UsageBarOverview"
    static let codex = "UsageBarCodex"
    static let claude = "UsageBarClaude"
}

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKindID.overview, provider: UsageTimelineProvider()) { entry in
            OverviewWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("UsageBar Overview")
        .description("Codex and Claude remaining quota together.")
        .supportedFamilies(WidgetFamilySupport.overview)
    }
}

struct CodexWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKindID.codex, provider: UsageTimelineProvider()) { entry in
            ProviderWidgetView(entry: entry, providerId: UsageProviderID.codex)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("UsageBar Codex")
        .description("Codex remaining quota.")
        .supportedFamilies(WidgetFamilySupport.provider)
    }
}

struct ClaudeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKindID.claude, provider: UsageTimelineProvider()) { entry in
            ProviderWidgetView(entry: entry, providerId: UsageProviderID.claude)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("UsageBar Claude")
        .description("Claude remaining quota.")
        .supportedFamilies(WidgetFamilySupport.provider)
    }
}
