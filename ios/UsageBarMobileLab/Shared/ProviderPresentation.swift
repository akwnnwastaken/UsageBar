import Foundation
import SwiftUI
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

    /// A provider's lifecycle, as a value rather than as a string.
    ///
    /// The card needs to *style* these differently — a pill that is subtly
    /// active for one and attention-coloured for another — and matching on
    /// display text to decide a colour would break the moment the wording
    /// changed. These are the same four states the app has always reported; no
    /// new lifecycle state is invented here.
    public enum Status: Equatable, Sendable {
        case collecting
        case paused
        case waitingForData
        case disconnected
    }

    public static func status(for provider: UsageSyncProvider) -> Status {
        if !provider.connected { return .disconnected }
        if !provider.collecting { return .paused }
        if provider.measurement == nil { return .waitingForData }
        return .collecting
    }

    /// The lifecycle sentence for a provider card.
    public static func statusLabel(for provider: UsageSyncProvider) -> String {
        label(for: status(for: provider))
    }

    public static func label(for status: Status) -> String {
        switch status {
        case .collecting: return "Collecting"
        case .paused: return "Paused"
        case .waitingForData: return "Waiting for usage data"
        case .disconnected: return "Disconnected"
        }
    }

    /// A paused provider is a deliberate user choice, not a fault, so it must
    /// not be styled as an error. A disconnected one is genuinely absent.
    public static func isAttentionState(_ provider: UsageSyncProvider) -> Bool {
        status(for: provider) == .disconnected
    }
}

/// The restrained visual identity a provider card and its accents carry.
///
/// Centralised here rather than spelled out in the views, so the dashboard, a
/// progress bar and a status pill cannot end up with three different ideas of
/// what "Codex" looks like.
///
/// Deliberately generic: no provider logo, wordmark or trademark artwork is
/// bundled or imitated. A stock SF Symbol and a system colour is the whole
/// vocabulary. System colours are used in preference to literals because they
/// are the ones that already adapt to Light and Dark Mode and to the
/// accessibility contrast settings.
public enum ProviderVisual {
    public static func symbolName(for providerId: String) -> String {
        switch providerId {
        case UsageProviderID.codex:
            return "chevron.left.forwardslash.chevron.right"
        case UsageProviderID.claude:
            return "sparkle"
        default:
            return "gauge.with.dots.needle.bottom.50percent"
        }
    }

    public static func accent(for providerId: String) -> Color {
        switch providerId {
        case UsageProviderID.codex:
            return .teal
        case UsageProviderID.claude:
            return .orange
        default:
            return .accentColor
        }
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

    /// How long the headline window has left — "17m left", "2h 59m left",
    /// "1d 3h 14m left".
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

    /// The same interval with the spaces spent as digits — "2h59m" — for the
    /// Lock Screen and Control Center.
    public static func tightReset(
        in measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String? {
        guard let resetsAt = resetsAt(in: measurement) else { return nil }
        return FreshnessPresentation.tightTimeRemaining(until: resetsAt, from: now)
    }

    /// The interval spelled for VoiceOver — "2 hours 59 minutes".
    public static func spokenReset(
        in measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String? {
        guard let resetsAt = resetsAt(in: measurement) else { return nil }
        return FreshnessPresentation.spokenTimeRemaining(until: resetsAt, from: now)
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
    /// The Home Screen has room for the spaced form, so this is where the
    /// countdown reads at its most legible — "5 Hour · 2h 59m left". Nil when
    /// the headline window is not in the snapshot: a label is not invented,
    /// though the percentage is still shown above it.
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
    /// both facts: "2h59m left · 3m ago".
    ///
    /// Both are shortened rather than one being dropped, and the countdown uses
    /// the tight spelling so that *both* of its components survive on a line
    /// this narrow — losing the minutes was the old behaviour this checkpoint
    /// exists to remove. "left" is kept because it is what distinguishes time
    /// remaining from the age sitting next to it. The age is still `measuredAt`
    /// and still carries no stale threshold.
    public static func accessoryFooter(
        of measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String {
        let age = FreshnessPresentation.shortAge(of: measurement, now: now)
        guard let remaining = HeadlinePresentation.tightReset(in: measurement, now: now) else {
            return age
        }
        return "\(remaining) left · \(age)"
    }

    /// The Lock Screen inline string. The percentage comes first so that the
    /// countdown is what a truncation costs, and the countdown is tight so that
    /// it keeps its minutes — "Codex 39% · 4h59m".
    public static func inline(
        name: String,
        percent: Int,
        measurement: UsageSyncMeasurement?,
        now: Date = Date()
    ) -> String {
        guard let measurement,
              let remaining = HeadlinePresentation.tightReset(in: measurement, now: now) else {
            return "\(name) \(percent)%"
        }
        return "\(name) \(percent)% · \(remaining)"
    }

    /// The already-separated countdown an overview row appends after a
    /// percentage, or nil when there is nothing to count down to.
    ///
    /// Tight, because the overview carries two providers on one line and the
    /// alternative to spending the space is dropping the minutes.
    public static func countdownSuffix(
        in measurement: UsageSyncMeasurement?,
        now: Date = Date()
    ) -> String? {
        guard let measurement,
              let remaining = HeadlinePresentation.tightReset(in: measurement, now: now) else {
            return nil
        }
        return "· \(remaining)"
    }
}

/// The floored day/hour/minute remainder of a live countdown.
///
/// One decomposition, shared by the dashboard, the Home Screen widgets, the
/// Lock Screen accessories and Control Center, so no surface can arrive at its
/// own arithmetic. Each surface chooses only how to *spell* the result.
///
/// It replaces an earlier policy that rendered the largest whole unit alone, so
/// that "2h 59m" read as "2h left" and "1d 3h 14m" as "1d left". Flooring to a
/// single unit is safe in the sense that it never overstates the time left, but
/// it discards up to an hour — or up to a day — of real interval, and a person
/// deciding whether to keep working needs the remainder, not its leading digit.
///
/// Seconds are still floored away, because every surface promises minute
/// resolution and a countdown that renders seconds would have to tick to stay
/// true. What is no longer discarded is the part of the interval that matters.
struct ResetRemainder: Equatable {
    let days: Int
    let hours: Int
    let minutes: Int

    /// Nil when the reset is already past: a negative countdown is not
    /// information, and the snapshot it came from is by then stale anyway.
    init?(until resetsAt: Date, from now: Date) {
        let seconds = Int(resetsAt.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        // A window with forty seconds left is still open, and "0m left" would
        // say it had closed. Under a minute is reported as the minute it is
        // still inside.
        let totalMinutes = max(seconds / 60, 1)
        days = totalMinutes / (60 * 24)
        hours = (totalMinutes % (60 * 24)) / 60
        minutes = totalMinutes % 60
    }

    /// The significant components, largest first, with zeroes dropped.
    ///
    /// This is the whole policy: `2h 59m` keeps its minutes and `1d 3h 14m`
    /// keeps all three parts, while `1d 0h 0m` collapses to a bare "1d",
    /// because a zero component is noise rather than precision. `1d 0h 14m`
    /// therefore reads "1d 14m" — the hours are genuinely zero, so printing
    /// them would say nothing.
    private var units: [(value: Int, short: String, spoken: String)] {
        [
            (days, "d", "day"),
            (hours, "h", "hour"),
            (minutes, "m", "minute")
        ].filter { $0.value > 0 }
    }

    /// "1d 3h 14m" — for surfaces with room to breathe.
    var spaced: String {
        units.map { "\($0.value)\($0.short)" }.joined(separator: " ")
    }

    /// "1d3h14m" — for Control Center and the Lock Screen, where a space is a
    /// character that could have been a digit. Every component survives; only
    /// the whitespace is spent.
    var tight: String {
        units.map { "\($0.value)\($0.short)" }.joined()
    }

    /// "1 day 3 hours 14 minutes" — what VoiceOver should say, since "1d3h14m"
    /// is not a sentence.
    var spoken: String {
        units
            .map { "\($0.value) \($0.spoken)\($0.value == 1 ? "" : "s")" }
            .joined(separator: " ")
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

    /// How long a window has left, at minute resolution — "17m left",
    /// "1h 7m left", "2h 59m left", "1d 3h 14m left".
    ///
    /// Returns `nil` when the window has no reset time, or when that time has
    /// already passed.
    public static func compactTimeRemaining(until resetsAt: Date, from now: Date = Date()) -> String? {
        ResetRemainder(until: resetsAt, from: now).map { "\($0.spaced) left" }
    }

    /// The same interval with its spaces spent — "2h59m" — for the one-line
    /// surfaces. No "left" suffix: the caller adds one where the line has room
    /// and the word earns its place.
    public static func tightTimeRemaining(until resetsAt: Date, from now: Date = Date()) -> String? {
        ResetRemainder(until: resetsAt, from: now)?.tight
    }

    /// The interval as VoiceOver should read it — "2 hours 59 minutes".
    public static func spokenTimeRemaining(until resetsAt: Date, from now: Date = Date()) -> String? {
        ResetRemainder(until: resetsAt, from: now)?.spoken
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

    /// The headline's two facts in one sentence: how old the reading is, and
    /// how long its window has left.
    ///
    /// The card renders them on separate lines so that neither can be mistaken
    /// for the other, and uses this composed form as the accessibility label —
    /// VoiceOver reads one sentence where the eye reads two rows. A future
    /// reset must never make an old measurement look fresh — a desktop asleep
    /// for two days can still hold a reading whose five-hour window resets in
    /// an hour — so the age is always present and always first.
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
        return "Resets \(absoluteReset(resetsAt, now: now))"
    }

    /// A detail row's reset fact, in full: how long is left, and when exactly —
    /// "Resets in 4h 59m · 4:59 PM".
    ///
    /// The two are not redundant. The countdown answers "how much longer may I
    /// keep going?", which is the question a quota provokes; the clock time
    /// answers "when exactly?", which is what someone plans an afternoon
    /// around. A multi-day window needs the date as well, so the absolute part
    /// widens to "Sep 27, 9:59 PM" once the reset is not today.
    ///
    /// Once the reset has passed there is no interval left to state, so the row
    /// falls back to the absolute instant alone rather than printing a zero or
    /// a negative countdown.
    public static func resetSummary(for window: UsageSyncWindow, now: Date = Date()) -> String? {
        guard let resetsAt = window.resetsAt else { return nil }
        let clock = absoluteReset(resetsAt, now: now)
        guard let remainder = ResetRemainder(until: resetsAt, from: now) else {
            return "Resets \(clock)"
        }
        return "Resets in \(remainder.spaced) · \(clock)"
    }

    /// What VoiceOver should say for a detail row's reset.
    public static func spokenResetSummary(for window: UsageSyncWindow, now: Date = Date()) -> String? {
        guard let resetsAt = window.resetsAt else { return nil }
        let clock = absoluteReset(resetsAt, now: now)
        guard let remainder = ResetRemainder(until: resetsAt, from: now) else {
            return "Resets at \(clock)"
        }
        return "Resets in \(remainder.spoken), at \(clock)"
    }

    /// The locale's own rendering of an instant. `Locale.autoupdatingCurrent`
    /// decides 12- or 24-hour; this code never assumes one.
    private static func absoluteReset(_ resetsAt: Date, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        if Calendar.current.isDate(resetsAt, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: resetsAt)
    }
}
