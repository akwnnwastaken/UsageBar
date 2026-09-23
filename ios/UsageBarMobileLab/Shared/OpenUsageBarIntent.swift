import AppIntents

/// Where a control sends the person who taps it.
///
/// Phase 7 has exactly one destination: the app's normal dashboard. The enum
/// exists because `OpenIntent` requires an `AppValue` target, not because the
/// lab has provider-specific navigation to offer. Inventing a case per provider
/// would advertise a deep link that silently lands on the same screen.
enum UsageBarDestination: String, AppEnum {
    case dashboard

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "UsageBar Screen")
    }

    static var caseDisplayRepresentations: [UsageBarDestination: DisplayRepresentation] {
        [.dashboard: DisplayRepresentation(title: "Dashboard")]
    }
}

/// The only action a UsageBar control performs: open the containing app.
///
/// It carries no credential, no host and no snapshot — a control's action is
/// stored by the system and surfaced in Shortcuts, so anything placed in it
/// leaves the app's control. There is deliberately no intent in this project
/// that resets a quota, contacts a provider, toggles collection or changes
/// Tailscale: a Control Center control that could mutate provider state would
/// be one accidental tap away from doing so.
///
/// `OpenIntent` is Apple's documented shape for this. The system requires the
/// intent to be a member of **both** the app and the widget extension targets
/// to open the app, which is why this file lives in `Shared/`.
struct OpenUsageBarIntent: OpenIntent {
    static var title: LocalizedStringResource { "Open UsageBar" }

    static var description: IntentDescription? {
        IntentDescription("Opens UsageBar Mobile.")
    }

    @Parameter(title: "Screen")
    var target: UsageBarDestination

    init() {
        self.target = .dashboard
    }

    init(target: UsageBarDestination) {
        self.target = target
    }
}
