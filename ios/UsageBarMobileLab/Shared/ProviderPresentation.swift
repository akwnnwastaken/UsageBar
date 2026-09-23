import Foundation
import UsageBarSync

/// The provider slugs this app knows by name.
///
/// They are the desktop's own stable identifiers, not display text, and they
/// are the join between a snapshot and the surface that shows it — a widget
/// kind, a control kind and a presentation lookup all key off the same string.
/// Spelling them once means a typo is a compile error rather than a widget that
/// silently renders nothing.
public enum UsageProviderID {
    public static let codex = "codex"
    public static let claude = "claude-code"
}

/// Turns schema facts into screen text.
///
/// Every label here is derived on the phone from structured fields. The desktop
/// sends identifiers and numbers, never localized strings: a display name
/// crossing the wire would be presentation leaking into a data contract, and it
/// would have to be versioned like data forever after.
public enum ProviderPresentation {
    /// Known providers get their product name; anything else gets a readable
    /// label derived from its slug, so a provider added on the desktop after
    /// this app shipped still renders sensibly instead of as a raw id.
    public static func displayName(for providerId: String) -> String {
        switch providerId {
        case UsageProviderID.codex:
            return "Codex"
        case UsageProviderID.claude:
            return "Claude"
        default:
            return providerId
                .split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    /// The lifecycle sentence for a provider card.
    public static func statusLabel(for provider: UsageSyncProvider) -> String {
        if !provider.connected { return "Disconnected" }
        if !provider.collecting { return "Paused" }
        if provider.measurement == nil { return "Waiting for usage data" }
        return "Collecting"
    }

    /// A paused provider is a deliberate user choice, not a fault, so it must
    /// not be styled as an error. A disconnected one is genuinely absent.
    public static func isAttentionState(_ provider: UsageSyncProvider) -> Bool {
        !provider.connected
    }
}

/// Window labels, built from `kind` plus its qualifier.
public enum WindowPresentation {
    public static func label(for window: UsageSyncWindow) -> String {
        switch window.kind {
        case .fiveHour:
            return "5 Hour"
        case .weekly:
            return "Weekly"
        case .weeklyScoped:
            // The scope is a model or model-family slug, e.g. "opus".
            guard let scope = window.scope, !scope.isEmpty else { return "Weekly" }
            return "Weekly · \(prettyScope(scope))"
        case .duration:
            guard let minutes = window.durationMinutes else { return "Limit" }
            return durationLabel(minutes: minutes)
        case .unknown:
            // The forward-compatibility case: the desktop saw a window it could
            // not classify. Say so neutrally rather than inventing a meaning,
            // and never fall back to showing the raw windowId.
            guard let position = window.position else { return "Additional Limit" }
            return "Additional Limit \(position + 1)"
        }
    }

    /// A short form for surfaces with one line of text and no room to spend.
    ///
    /// Control Center renders a control's label and nothing else — no status
    /// line — so the window a headline came from has to share that one line
    /// with the provider name and the percentage. "5H" is the cost of saying
    /// *which* limit the number refers to, which is the difference between a
    /// figure and a fact.
    ///
    /// The `weeklyScoped` scope is deliberately dropped here rather than
    /// abbreviated: "Weekly · Opus" has no honest short form, and the Home
    /// Screen widget already shows it in full.
    public static func compactLabel(for window: UsageSyncWindow) -> String {
        switch window.kind {
        case .fiveHour:
            return "5H"
        case .weekly, .weeklyScoped:
            return "Weekly"
        case .duration:
            guard let minutes = window.durationMinutes else { return "Limit" }
            return compactDurationLabel(minutes: minutes)
        case .unknown:
            return "Limit"
        }
    }

    /// The largest unit that stays exact, so a three-day limit reads "3D".
    static func compactDurationLabel(minutes: Int) -> String {
        if minutes % (60 * 24) == 0 { return "\(minutes / (60 * 24))D" }
        if minutes % 60 == 0 { return "\(minutes / 60)H" }
        return "\(minutes)M"
    }

    private static func prettyScope(_ scope: String) -> String {
        scope
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Renders a window length in the largest unit that stays exact, so a
    /// three-day limit reads as "3 Day" rather than "4320 Minute".
    static func durationLabel(minutes: Int) -> String {
        if minutes % (60 * 24) == 0 {
            let days = minutes / (60 * 24)
            return "\(days) Day"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return "\(hours) Hour"
        }
        return "\(minutes) Minute"
    }
}

/// The one place any mobile surface resolves "which window is the headline".
///
/// The desktop has already chosen. `headlineRemainingPercent` is the number it
/// chose, and `headlineWindowId` names the window that produced it — so every
/// label and every countdown shown beside that percentage has to come from
/// *that* window.
///
/// `windows.first` is not it, and the difference is not theoretical: Codex's
/// headline is its most constrained window, which can legitimately be a
/// multi-day `duration` limit listed after the weekly one. A surface that read
/// the first window would then print a five-hour or weekly label beside a
/// three-day number, and a countdown to the wrong reset — confidently, and
/// wrongly, on a Lock Screen.
///
/// One resolver, used by the dashboard, the widgets and Control Center alike.
public enum HeadlinePresentation {
    /// The window `headlineWindowId` names, or nil when the snapshot does not
    /// contain it. Never a fallback guess: a missing headline window means the
    /// label and countdown are simply not shown, while the percentage — which
    /// is the desktop's own answer either way — still is.
    public static func window(in measurement: UsageSyncMeasurement) -> UsageSyncWindow? {
        measurement.windows.first { $0.windowId == measurement.headlineWindowId }
    }

    /// The headline window's full label, e.g. "5 Hour" or "Weekly · Opus".
    public static func label(in measurement: UsageSyncMeasurement) -> String? {
        window(in: measurement).map(WindowPresentation.label)
    }

    /// The headline window's short label, e.g. "5H", "Weekly", "3D".
    public static func compactLabel(in measurement: UsageSyncMeasurement) -> String? {
        window(in: measurement).map(WindowPresentation.compactLabel)
    }

    /// When the headline window resets, if it says.
    public static func resetsAt(in measurement: UsageSyncMeasurement) -> Date? {
        window(in: measurement)?.resetsAt
    }

    /// How long the headline window has left — "14m left", "2h left", "3d left".
    ///
    /// Nil when the window carries no reset time, when the reset has already
    /// passed, or when the headline window is not in the snapshot. A countdown
    /// that has expired is not information.
    public static func compactReset(
        in measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String? {
        guard let resetsAt = resetsAt(in: measurement) else { return nil }
        return FreshnessPresentation.compactTimeRemaining(until: resetsAt, from: now)
    }
}

/// The composed strings the widgets render.
///
/// They live here rather than inside the widget extension for one practical
/// reason: an app extension cannot be `@testable`-imported, so a line built
/// inline in `WidgetViews.swift` could never be asserted. Keeping the text here
/// means every surface's wording is under test, and the views stay layout only.
public enum SurfaceLinePresentation {
    /// The line under a provider widget's headline: which window the number
    /// belongs to, and how long that window has left.
    ///
    /// Nil when the headline window is not in the snapshot — a label is not
    /// invented, though the percentage is still shown above it.
    public static func headlineWindowLine(
        in measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String? {
        guard let label = HeadlinePresentation.label(in: measurement) else { return nil }
        guard let remaining = HeadlinePresentation.compactReset(in: measurement, now: now) else {
            return label
        }
        return "\(label) · \(remaining)"
    }

    /// The Lock Screen rectangular footer, where one cramped line has to carry
    /// both facts: "2h left · 3m ago".
    ///
    /// Both are shortened rather than one being dropped. The age is still
    /// `measuredAt` and still carries no stale threshold.
    public static func accessoryFooter(
        of measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String {
        let age = FreshnessPresentation.shortAge(of: measurement, now: now)
        guard let remaining = HeadlinePresentation.compactReset(in: measurement, now: now) else {
            return age
        }
        return "\(remaining) · \(age)"
    }

    /// The Lock Screen inline string. The percentage comes first so that the
    /// countdown is what a truncation costs.
    public static func inline(
        name: String,
        percent: Int,
        measurement: UsageSyncMeasurement?,
        now: Date = Date()
    ) -> String {
        guard let measurement,
              let remaining = HeadlinePresentation.compactReset(in: measurement, now: now) else {
            return "\(name) \(percent)%"
        }
        return "\(name) \(percent)% · \(remaining)"
    }

    /// The already-separated countdown an overview row appends after a
    /// percentage, or nil when there is nothing to count down to.
    public static func countdownSuffix(
        in measurement: UsageSyncMeasurement?,
        now: Date = Date()
    ) -> String? {
        guard let measurement,
              let remaining = HeadlinePresentation.compactReset(in: measurement, now: now) else {
            return nil
        }
        return "· \(remaining)"
    }
}

/// Freshness.
public enum FreshnessPresentation {
    /// Age comes from the provider's own `measuredAt` and never from the
    /// snapshot's `generatedAt`.
    ///
    /// `generatedAt` is when the *document* was built, which advances every
    /// time the desktop serializes — including when a provider's reading is
    /// retained, stale or paused. Using it would make a week-old measurement
    /// look seconds fresh, which is precisely the failure the contract was
    /// shaped to prevent.
    public static func age(of measurement: UsageSyncMeasurement, now: Date = Date()) -> String {
        relativeAge(from: measurement.measuredAt, to: now)
    }

    /// How long the headline window has left before it resets, in as few
    /// characters as possible — "3d left", "2h left", "14m left".
    ///
    /// Control Center gives a control one short line, and of the two facts that
    /// could share it with the percentage, this is the one that tells a person
    /// what to do next: 21% with three days to run is a different situation
    /// from 21% with twenty minutes to run.
    ///
    /// It floors rather than rounds. Overstating the time left is the harmful
    /// direction — someone plans around a window that closes sooner than the
    /// control implied — so "2h 59m" reads as "2h left".
    ///
    /// Returns `nil` when the window has no reset time, or when that time has
    /// already passed: a negative countdown is not information, and the
    /// snapshot it came from is by then stale anyway.
    public static func compactTimeRemaining(until resetsAt: Date, from now: Date = Date()) -> String? {
        let seconds = Int(resetsAt.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(minutes, 1))m left" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h left" }
        return "\(hours / 24)d left"
    }

    /// Phase 5 states the age as a fact and draws no conclusion from it. No
    /// "stale" threshold is invented here: what counts as too old is a client
    /// policy question that has not been decided, and a wrong threshold is
    /// worse than none.
    static func relativeAge(from date: Date, to now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded())
        if seconds < 0 { return "Updated just now" }
        if seconds < 60 { return "Updated just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "Updated \(hours) hr ago" }
        let days = hours / 24
        return days == 1 ? "Updated 1 day ago" : "Updated \(days) days ago"
    }

    /// The headline's metadata line: how old the reading is, and how long its
    /// window has left.
    ///
    /// Two different facts, and the app has room for both. A future reset must
    /// never make an old measurement look fresh — a desktop asleep for two days
    /// can still hold a reading whose five-hour window resets in an hour — so
    /// the age is always present and always first.
    public static func headlineMetadata(
        of measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String {
        let age = self.age(of: measurement, now: now)
        guard let remaining = HeadlinePresentation.compactReset(in: measurement, now: now) else {
            return age
        }
        return "\(age) · \(remaining)"
    }

    /// The shortest honest age, for surfaces with one cramped line.
    ///
    /// Same source as every other freshness string — `measuredAt`, never
    /// `generatedAt` — and deliberately no stale threshold: what counts as too
    /// old is a client policy question that has not been decided, and a wrong
    /// threshold is worse than none.
    public static func shortAge(of measurement: UsageSyncMeasurement, now: Date = Date()) -> String {
        shortAge(from: measurement.measuredAt, to: now)
    }

    static func shortAge(from date: Date, to now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded())
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    /// Reset times are absolute instants; show them in the phone's locale.
    public static func resetLabel(for window: UsageSyncWindow, now: Date = Date()) -> String? {
        guard let resetsAt = window.resetsAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        if Calendar.current.isDate(resetsAt, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Resets \(formatter.string(from: resetsAt))"
        }
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Resets \(formatter.string(from: resetsAt))"
    }
}
