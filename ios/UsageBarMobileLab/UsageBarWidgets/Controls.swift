import SwiftUI
import WidgetKit

/// Control Center controls.
///
/// A control is not a freely laid-out widget. Apple renders it through a
/// template, and Control Center — not this code — decides which of the label,
/// the title and the status line survive at a given physical control size. So
/// these declare *what* to say and let the system choose how much of it fits,
/// rather than trying to reproduce the Home Screen widget inside Control
/// Center.
///
/// All three share one action: open UsageBar Mobile. There is no control
/// here that resets a quota, contacts a provider, pauses collection or touches
/// Tailscale — Control Center is a surface people brush past, and a destructive
/// action one tap deep in it would be a mistake waiting to happen.
struct UsageBarOverviewControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: ControlKindID.overview,
            provider: UsageControlValueProvider()
        ) { value in
            ControlWidgetButton(action: OpenUsageBarIntent()) {
                Label(
                    ControlPresentation.overviewTitle(for: value),
                    systemImage: ControlSymbol.overview
                )
                .controlWidgetStatus(ControlPresentation.status(for: value))
            }
            // Quota is personal account information, so it is redacted with the
            // rest of the device's sensitive content rather than staying legible
            // on a locked screen.
            .privacySensitive()
        }
        .displayName("UsageBar Overview")
        .description("Codex and Claude remaining quota.")
    }
}

struct UsageBarCodexControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: ControlKindID.codex,
            provider: UsageControlValueProvider()
        ) { value in
            ControlWidgetButton(action: OpenUsageBarIntent()) {
                Label(
                    ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.codex),
                    systemImage: ControlSymbol.codex
                )
                .controlWidgetStatus(ControlPresentation.status(for: value))
            }
            .privacySensitive()
        }
        .displayName("UsageBar Codex")
        .description("Codex remaining quota.")
    }
}

struct UsageBarClaudeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: ControlKindID.claude,
            provider: UsageControlValueProvider()
        ) { value in
            ControlWidgetButton(action: OpenUsageBarIntent()) {
                Label(
                    ControlPresentation.providerTitle(for: value, providerId: UsageProviderID.claude),
                    systemImage: ControlSymbol.claude
                )
                .controlWidgetStatus(ControlPresentation.status(for: value))
            }
            .privacySensitive()
        }
        .displayName("UsageBar Claude")
        .description("Claude remaining quota.")
    }
}
