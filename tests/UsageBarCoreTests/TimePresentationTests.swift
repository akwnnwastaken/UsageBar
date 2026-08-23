import XCTest
@testable import UsageBarCore

/// How a usage window's reset instant is written out.
///
/// The detailed menu shows the same instant twice — as a local clock time and
/// as a countdown — while the menu-bar item shows the countdown alone. These
/// tests cover that wording, including the cases where the clock must *not*
/// appear: a window with no reset instant, and a reset that is already due.
///
/// Every case supplies both the instant and `now` explicitly, and pins the time
/// zone, so no expectation depends on when or where the suite runs.
final class TimePresentationTests: XCTestCase {
    /// One fixed zone for every case. Nothing here reads the machine's own.
    private static let zone = TimeZone(identifier: "Europe/Istanbul")!

    private func instant(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.zone
        let components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return try XCTUnwrap(calendar.date(from: components))
    }

    private func turkish(_ timeZone: TimeZone = TimePresentationTests.zone) -> TimePresentation {
        TimePresentation(language: .turkish, timeZone: timeZone)
    }

    private func english(_ timeZone: TimeZone = TimePresentationTests.zone) -> TimePresentation {
        TimePresentation(language: .english, timeZone: timeZone)
    }

    /// ICU has written the English am/pm separator as both a plain space and a
    /// narrow no-break space depending on the OS version, so comparisons
    /// normalize it instead of pinning whichever one this machine produces.
    private func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: - Future reset

    func testTurkishFutureResetShowsClockThenCountdown() throws {
        let resetsAt = try instant(2026, 8, 24, 18, 45)
        let now = resetsAt.addingTimeInterval(-(3 * 3_600 + 12 * 60))
        XCTAssertEqual(
            turkish().resetLine(resetsAt, now: now),
            "Sıfırlama: 18:45 · 3sa 12dk"
        )
    }

    func testEnglishFutureResetShowsClockThenCountdown() throws {
        let resetsAt = try instant(2026, 8, 24, 18, 45)
        let now = resetsAt.addingTimeInterval(-(3 * 3_600 + 12 * 60))
        let line = try XCTUnwrap(english().resetLine(resetsAt, now: now))
        XCTAssertEqual(normalized(line), "Resets: 6:45 PM · 3h 12m")
    }

    /// The clock and the countdown must describe one instant, not two: moving
    /// `now` alone changes the countdown and leaves the clock alone.
    func testBothSidesDescribeTheSameInstant() throws {
        let resetsAt = try instant(2026, 8, 24, 18, 45)
        XCTAssertEqual(
            turkish().resetLine(resetsAt, now: resetsAt.addingTimeInterval(-5 * 3_600 - 4 * 60)),
            "Sıfırlama: 18:45 · 5sa 4dk"
        )
        XCTAssertEqual(
            turkish().resetLine(resetsAt, now: resetsAt.addingTimeInterval(-45 * 60)),
            "Sıfırlama: 18:45 · 45dk"
        )
    }

    /// A reset days away still shows a bare clock time. The day count is the
    /// countdown's job; a weekday or date would be a different feature.
    func testMultiDayResetKeepsTheAbsoluteSideClockOnly() throws {
        let resetsAt = try instant(2026, 8, 26, 18, 45)
        let now = try instant(2026, 8, 24, 15, 45)
        let line = try XCTUnwrap(english().resetLine(resetsAt, now: now))
        XCTAssertEqual(normalized(line), "Resets: 6:45 PM · 2d 3h")
        XCTAssertEqual(
            turkish().resetLine(resetsAt, now: now),
            "Sıfırlama: 18:45 · 2g 3sa"
        )

        for forbidden in ["Aug", "Ağu", "Wed", "Çar", "2026", "26.08", "8/26", "/", "-"] {
            XCTAssertFalse(line.contains(forbidden), "\(line) should not carry \(forbidden)")
        }
    }

    // MARK: - Missing, due and past resets

    func testAWindowWithoutAResetInstantHasNoLine() throws {
        let now = try instant(2026, 8, 24, 15, 33)
        XCTAssertNil(turkish().resetLine(nil, now: now))
        XCTAssertNil(english().resetLine(nil, now: now))
    }

    /// The boundary is the instant itself: due at exactly `now`, and one second
    /// past is already past.
    func testAResetAtNowShowsOnlyTheLocalizedNow() throws {
        let resetsAt = try instant(2026, 8, 24, 18, 45)
        XCTAssertEqual(turkish().resetLine(resetsAt, now: resetsAt), "Sıfırlama: şimdi")
        XCTAssertEqual(english().resetLine(resetsAt, now: resetsAt), "Resets: now")

        let oneSecondPast = resetsAt.addingTimeInterval(1)
        XCTAssertEqual(turkish().resetLine(resetsAt, now: oneSecondPast), "Sıfırlama: şimdi")
        XCTAssertEqual(english().resetLine(resetsAt, now: oneSecondPast), "Resets: now")
    }

    /// A reset in the past must not leave its stale clock time on screen.
    func testAPastResetShowsOnlyTheLocalizedNow() throws {
        let resetsAt = try instant(2026, 8, 24, 18, 45)
        let hourLater = resetsAt.addingTimeInterval(3_600)
        let weekLater = resetsAt.addingTimeInterval(7 * 86_400)

        let turkishLine = try XCTUnwrap(turkish().resetLine(resetsAt, now: hourLater))
        XCTAssertEqual(turkishLine, "Sıfırlama: şimdi")
        XCTAssertFalse(turkishLine.contains("18:45"))

        let englishLine = try XCTUnwrap(english().resetLine(resetsAt, now: weekLater))
        XCTAssertEqual(englishLine, "Resets: now")
        XCTAssertFalse(englishLine.contains("6:45"))
        XCTAssertFalse(englishLine.contains("PM"))
    }

    /// A reset that has not happened yet keeps its clock time, including inside
    /// the final minute where the countdown has already floored to "now".
    ///
    /// Dropping the clock there would call a still-future instant due, and
    /// stopping the countdown from flooring would rewrite rounding the menu bar
    /// has always used. Neither is acceptable, so both are shown:
    /// `Sıfırlama: 18:45 · şimdi`. Due-ness is decided by comparing the
    /// instants, never by reading the countdown.
    func testAFutureResetKeepsItsClockThroughTheFinalMinute() throws {
        let resetsAt = try instant(2026, 8, 24, 18, 45)
        let fiftyNineSecondsBefore = resetsAt.addingTimeInterval(-59)

        XCTAssertEqual(
            turkish().resetLine(resetsAt, now: fiftyNineSecondsBefore),
            "Sıfırlama: 18:45 · şimdi"
        )
        XCTAssertEqual(
            normalized(try XCTUnwrap(english().resetLine(resetsAt, now: fiftyNineSecondsBefore))),
            "Resets: 6:45 PM · now"
        )

        // One second ahead is still ahead.
        XCTAssertEqual(
            turkish().resetLine(resetsAt, now: resetsAt.addingTimeInterval(-1)),
            "Sıfırlama: 18:45 · şimdi"
        )
        XCTAssertEqual(
            normalized(try XCTUnwrap(english().resetLine(resetsAt, now: resetsAt.addingTimeInterval(-1)))),
            "Resets: 6:45 PM · now"
        )

        // The countdown itself is untouched: it still floors to "now" here...
        XCTAssertEqual(turkish().relativeReset(resetsAt, now: fiftyNineSecondsBefore), "şimdi")
        XCTAssertEqual(english().relativeReset(resetsAt, now: fiftyNineSecondsBefore), "now")

        // ...and still turns over at a whole minute, in both forms.
        XCTAssertEqual(
            turkish().resetLine(resetsAt, now: resetsAt.addingTimeInterval(-60)),
            "Sıfırlama: 18:45 · 1dk"
        )
        XCTAssertEqual(
            normalized(try XCTUnwrap(english().resetLine(resetsAt, now: resetsAt.addingTimeInterval(-60)))),
            "Resets: 6:45 PM · 1m"
        )
        XCTAssertEqual(turkish().relativeReset(resetsAt, now: resetsAt.addingTimeInterval(-60)), "1dk")
    }

    // MARK: - Clock conventions

    func testEachLanguageKeepsItsOwnClockConvention() throws {
        let evening = try instant(2026, 8, 24, 18, 45)
        let morning = try instant(2026, 8, 24, 9, 5)

        XCTAssertEqual(turkish().clock(evening), "18:45")
        XCTAssertEqual(turkish().clock(morning), "09:05")
        XCTAssertEqual(normalized(english().clock(evening)), "6:45 PM")
        XCTAssertEqual(normalized(english().clock(morning)), "9:05 AM")
    }

    /// No seconds and no time-zone suffix, at an instant that has both.
    func testTheClockCarriesNeitherSecondsNorAZoneSuffix() throws {
        let resetsAt = try instant(2026, 8, 24, 18, 45).addingTimeInterval(37)
        XCTAssertEqual(turkish().clock(resetsAt), "18:45")
        XCTAssertEqual(normalized(english().clock(resetsAt)), "6:45 PM")
    }

    /// The clock follows the zone it is given; the countdown never does.
    func testTheClockFollowsTheTimeZoneWhileTheCountdownDoesNot() throws {
        let resetsAt = try instant(2026, 8, 24, 18, 45)
        let now = resetsAt.addingTimeInterval(-(3 * 3_600 + 12 * 60))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))

        XCTAssertEqual(turkish(utc).resetLine(resetsAt, now: now), "Sıfırlama: 15:45 · 3sa 12dk")
        XCTAssertEqual(turkish(utc).relativeReset(resetsAt, now: now), "3sa 12dk")
        XCTAssertEqual(turkish().relativeReset(resetsAt, now: now), "3sa 12dk")
    }

    // MARK: - Menu-bar form

    /// The compact form stays countdown-only: no label, no clock, no separator.
    func testTheMenuBarFormStaysRelativeOnly() throws {
        let resetsAt = try instant(2026, 8, 24, 18, 45)
        let now = resetsAt.addingTimeInterval(-(3 * 3_600 + 12 * 60))

        XCTAssertEqual(turkish().relativeReset(resetsAt, now: now), "3sa 12dk")
        XCTAssertEqual(english().relativeReset(resetsAt, now: now), "3h 12m")

        for compact in [turkish().relativeReset(resetsAt, now: now), english().relativeReset(resetsAt, now: now)] {
            XCTAssertFalse(compact.contains("18:45"))
            XCTAssertFalse(compact.contains("6:45"))
            XCTAssertFalse(compact.contains("PM"))
            XCTAssertFalse(compact.contains("·"))
            XCTAssertFalse(compact.contains("Sıfırlama"))
            XCTAssertFalse(compact.contains("Resets"))
        }
    }

    /// The countdown wording itself is unchanged, including its rounding: the
    /// detailed line ends with exactly what the menu bar shows.
    func testTheDetailedLineEndsWithTheUnchangedCountdown() throws {
        let base = try instant(2026, 8, 24, 12, 0)
        // Every future offset, down to a single second: the detailed line never
        // drops the countdown, and the countdown is never rewritten to suit it.
        let offsets: [TimeInterval] = [
            1,
            59,
            60,
            59 * 60,
            3_600 + 15 * 60,
            5 * 3_600 + 59 * 60 + 59,
            86_400,
            6 * 86_400 + 21 * 3_600
        ]

        for language in [AppLanguage.turkish, .english] {
            let presentation = TimePresentation(language: language, timeZone: Self.zone)
            for offset in offsets {
                let resetsAt = base.addingTimeInterval(offset)
                let compact = presentation.relativeReset(resetsAt, now: base)
                let detailed = try XCTUnwrap(presentation.resetLine(resetsAt, now: base))
                XCTAssertTrue(
                    detailed.hasSuffix(" · \(compact)"),
                    "\(detailed) should end with the countdown \(compact)"
                )
            }
        }
    }

    /// Both forms round the same way, because they share one calculation.
    func testCountdownRoundingIsUnchanged() throws {
        let base = try instant(2026, 8, 24, 12, 0)
        let presentation = english()
        XCTAssertEqual(presentation.relativeReset(base.addingTimeInterval(3_600 + 15 * 60), now: base), "1h 15m")
        XCTAssertEqual(presentation.relativeReset(base.addingTimeInterval(6 * 86_400 + 21 * 3_600), now: base), "6d 21h")
        // Seconds are dropped, never rounded up.
        XCTAssertEqual(presentation.relativeReset(base.addingTimeInterval(119), now: base), "1m")
        XCTAssertEqual(presentation.relativeReset(base.addingTimeInterval(59), now: base), "now")
        // A past reset clamps to "now" instead of counting upwards.
        XCTAssertEqual(presentation.relativeReset(base.addingTimeInterval(-9_000), now: base), "now")
    }

    // MARK: - The usage model is untouched

    /// Presentation reads `resetsAt`; it never supplies, moves or clears one.
    /// A window that arrived without a reset still has none afterwards, and one
    /// that arrived with a reset still reports the same instant.
    func testRenderingDoesNotAlterTheUsageModel() throws {
        let resetsAt = try instant(2026, 8, 24, 18, 45)
        let now = resetsAt.addingTimeInterval(-(3 * 3_600 + 12 * 60))
        let usage = ProviderUsage(
            name: "Codex",
            windows: [
                UsageWindow(kind: .fiveHour, usedPercent: 40, resetsAt: resetsAt, durationMinutes: 300),
                UsageWindow(kind: .weekly, usedPercent: 12, resetsAt: nil, durationMinutes: 10_080)
            ],
            error: nil
        )

        let presentation = turkish()
        for window in usage.windows {
            _ = presentation.resetLine(window.resetsAt, now: now)
        }

        XCTAssertEqual(usage.windows.first?.resetsAt, resetsAt)
        XCTAssertNil(usage.windows.last?.resetsAt)
        XCTAssertEqual(usage.windows.map(\.usedPercent), [40, 12])
        XCTAssertNil(usage.error)
        XCTAssertNil(usage.lastSuccessfulAt)

        let summary = try XCTUnwrap(UsageSummaryCalculator.summary(for: "Codex", in: ["Codex": usage]))
        XCTAssertEqual(summary.resetsAt, resetsAt)
        XCTAssertEqual(presentation.resetLine(summary.resetsAt, now: now), "Sıfırlama: 18:45 · 3sa 12dk")
        XCTAssertEqual(summary.resetsAt, resetsAt)
    }
}
