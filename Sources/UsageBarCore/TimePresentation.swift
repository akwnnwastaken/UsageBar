import Foundation

/// How UsageBar writes clock times and reset timing in the selected language.
///
/// A window's reset instant is shown two different ways. The detailed menu
/// writes it as a local clock time *and* a countdown — both describing the same
/// instant — while the menu-bar item stays countdown-only, because that text
/// sits next to the percentage in a strip the user cannot widen. They are
/// separate entry points rather than one string a caller trims.
///
/// Nothing here reads the clock or the calendar on its own: `now` is always
/// supplied by the caller and the time zone is a stored property, which is what
/// makes the wording assertable without depending on when or where it runs.
public struct TimePresentation {
    /// The countdown to a reset, split into whole days, hours and minutes.
    ///
    /// Every component is floored and a reset that has already passed clamps to
    /// zero rather than counting upwards — the arithmetic the menu bar has
    /// always used, kept in one place so the two forms cannot disagree.
    struct Countdown: Equatable {
        let days: Int
        let hours: Int
        let minutes: Int
    }

    public let language: AppLanguage
    public let timeZone: TimeZone

    /// `timeZone` defaults to the machine's own zone, which is what the menu has
    /// always displayed. It is a parameter only so the wording can be asserted
    /// from a fixed zone instead of the one the test happens to run in.
    public init(language: AppLanguage, timeZone: TimeZone = .current) {
        self.language = language
        self.timeZone = timeZone
    }

    private func pick(_ turkish: String, _ english: String) -> String {
        language == .turkish ? turkish : english
    }

    /// The word for a reset that is due: `şimdi` / `now`.
    public var nowWord: String { pick("şimdi", "now") }

    /// Local clock time in the language's usual form: `19:22` in Turkish,
    /// `7:22 PM` in English.
    ///
    /// Clock only — never a weekday, date or time-zone suffix, and never
    /// seconds. The locale is fixed per language rather than taken from the
    /// system, so the selected language alone decides the 24- or 12-hour form.
    public func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .turkish ? "tr_TR" : "en_US")
        formatter.dateFormat = language == .turkish ? "HH:mm" : "h:mm a"
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    /// The countdown only: `3sa 12dk` / `3h 12m`. This is the menu-bar form.
    public func relativeReset(_ date: Date, now: Date) -> String {
        countdownText(countdown(to: date, now: now))
    }

    /// The detailed reset line: `Sıfırlama: 18:45 · 3sa 12dk` /
    /// `Resets: 6:45 PM · 3h 12m`.
    ///
    /// A window that reports no reset instant has no line at all — `nil` here,
    /// and the caller adds nothing — because a reset time is never inferred.
    ///
    /// A reset that is due or past — and only that — drops to
    /// `Sıfırlama: şimdi` / `Resets: now`. Its clock time is behind us, so
    /// printing it beside "now" would state two different things about the same
    /// instant.
    ///
    /// Due-ness is decided by comparing the instants, never by reading the
    /// countdown. The countdown floors to whole minutes, so it says "now"
    /// throughout the final minute while the reset is still ahead; treating that
    /// as due would call a future instant past, and widening the countdown to
    /// avoid it would rewrite rounding the menu bar has always used. So the
    /// final minute deliberately shows both: `Sıfırlama: 18:45 · şimdi` /
    /// `Resets: 6:45 PM · now`.
    ///
    /// The absolute side is always clock-only, even when the reset is days away:
    /// the countdown is what carries the day count.
    public func resetLine(_ resetsAt: Date?, now: Date) -> String? {
        guard let resetsAt else { return nil }
        let label = pick("Sıfırlama", "Resets")
        guard resetsAt > now else { return "\(label): \(nowWord)" }
        return "\(label): \(clock(resetsAt)) · \(relativeReset(resetsAt, now: now))"
    }

    func countdown(to date: Date, now: Date) -> Countdown {
        let interval = max(0, Int(date.timeIntervalSince(now)))
        return Countdown(
            days: interval / 86_400,
            hours: (interval % 86_400) / 3_600,
            minutes: (interval % 3_600) / 60
        )
    }

    private func countdownText(_ countdown: Countdown) -> String {
        if language == .turkish {
            if countdown.days > 0 { return "\(countdown.days)g \(countdown.hours)sa" }
            if countdown.hours > 0 { return "\(countdown.hours)sa \(countdown.minutes)dk" }
            if countdown.minutes > 0 { return "\(countdown.minutes)dk" }
            return nowWord
        }

        if countdown.days > 0 { return "\(countdown.days)d \(countdown.hours)h" }
        if countdown.hours > 0 { return "\(countdown.hours)h \(countdown.minutes)m" }
        if countdown.minutes > 0 { return "\(countdown.minutes)m" }
        return nowWord
    }
}
