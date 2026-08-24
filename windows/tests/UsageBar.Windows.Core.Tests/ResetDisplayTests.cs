using System.Globalization;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// How a usage window's reset instant is written into the detailed panel.
///
/// The panel shows one instant twice — as a local clock time and as the
/// countdown it has always shown — while the tray tooltip stays countdown-only.
/// These cases cover that wording, including the ones where the clock must
/// <em>not</em> appear: a window with no reset instant, and a reset already due.
///
/// Every case supplies the instant, <c>now</c> and the time zone explicitly, so
/// no expectation depends on when or where the suite runs.
/// </summary>
public sealed class ResetDisplayTests
{
    private static readonly Localizer Turkish = new(AppLanguage.Turkish);
    private static readonly Localizer English = new(AppLanguage.English);

    /// <summary>
    /// A fixed +03:00 zone — Turkey's year-round offset, written as a custom
    /// zone so the expectations depend on neither the host's time-zone database
    /// nor a daylight-saving rule.
    /// </summary>
    private static readonly TimeZoneInfo Istanbul = TimeZoneInfo.CreateCustomTimeZone(
        "UsageBarTests/+03", TimeSpan.FromHours(3), "UsageBar test zone +03:00", "+03");

    /// <summary>A half-hour zone, so minute-level conversion is covered too.</summary>
    private static readonly TimeZoneInfo HalfHourZone = TimeZoneInfo.CreateCustomTimeZone(
        "UsageBarTests/+0530", TimeSpan.FromMinutes(330), "UsageBar test zone +05:30", "+0530");

    /// <summary>2026-08-24 18:45:00 +03:00 — the instant every case is written around.</summary>
    private static readonly DateTimeOffset ResetsAt = new(2026, 8, 24, 18, 45, 0, TimeSpan.FromHours(3));

    // MARK: - Future reset

    [Fact]
    public void TurkishFutureResetShowsTheClockThenTheCountdown()
    {
        var now = ResetsAt.AddHours(-3).AddMinutes(-12);

        Assert.Equal("Sıfırlama: 18:45 · 3sa 12dk", Line(Turkish, ResetsAt, now));
    }

    [Fact]
    public void EnglishFutureResetShowsTheClockThenTheCountdown()
    {
        var now = ResetsAt.AddHours(-3).AddMinutes(-12);

        Assert.Equal("Resets: 6:45 PM · 3h 12m", Line(English, ResetsAt, now));
    }

    /// <summary>
    /// The clock and the countdown must describe one instant, not two: moving
    /// <c>now</c> alone changes the countdown and leaves the clock alone.
    /// </summary>
    [Fact]
    public void BothSidesDescribeTheSameInstant()
    {
        Assert.Equal(
            "Sıfırlama: 18:45 · 5sa 4dk",
            Line(Turkish, ResetsAt, ResetsAt.AddHours(-5).AddMinutes(-4)));
        Assert.Equal(
            "Sıfırlama: 18:45 · 45dk",
            Line(Turkish, ResetsAt, ResetsAt.AddMinutes(-45)));
        Assert.Equal(
            "Resets: 6:45 PM · 45m",
            Line(English, ResetsAt, ResetsAt.AddMinutes(-45)));
    }

    /// <summary>
    /// A reset days away still shows a bare clock time. The day count is the
    /// countdown's job; a weekday or date would be a different feature.
    /// </summary>
    [Fact]
    public void MultiDayResetKeepsTheAbsoluteSideClockOnly()
    {
        var resetsAt = new DateTimeOffset(2026, 8, 26, 18, 45, 0, TimeSpan.FromHours(3));
        var now = new DateTimeOffset(2026, 8, 24, 15, 45, 0, TimeSpan.FromHours(3));

        var englishLine = Line(English, resetsAt, now);
        var turkishLine = Line(Turkish, resetsAt, now);

        Assert.Equal("Resets: 6:45 PM · 2d 3h", englishLine);
        Assert.Equal("Sıfırlama: 18:45 · 2g 3sa", turkishLine);

        string[] forbidden =
        [
            "Aug", "Ağu", "Wed", "Çar", "2026", "26.08", "8/26", "/", "-",
            "GMT", "UTC", "+03", "today", "bugün", "tomorrow", "yarın"
        ];

        foreach (var token in forbidden)
        {
            Assert.DoesNotContain(token, englishLine, StringComparison.Ordinal);
            Assert.DoesNotContain(token, turkishLine, StringComparison.Ordinal);
        }
    }

    // MARK: - Missing, due and past resets

    [Fact]
    public void AWindowWithoutAResetInstantHasNoLine()
    {
        var now = new DateTimeOffset(2026, 8, 24, 15, 33, 0, TimeSpan.FromHours(3));

        Assert.Null(Turkish.ResetDisplay(null, now, Istanbul));
        Assert.Null(English.ResetDisplay(null, now, Istanbul));

        // The machine-zone overload infers nothing either.
        Assert.Null(Turkish.ResetDisplay(null, now));
        Assert.Null(English.ResetDisplay(null, now));
    }

    /// <summary>
    /// The boundary is the instant itself: due at exactly <c>now</c>, and one
    /// second past is already past.
    /// </summary>
    [Fact]
    public void AResetAtNowShowsOnlyTheLocalizedNow()
    {
        Assert.Equal("Sıfırlama: şimdi", Line(Turkish, ResetsAt, ResetsAt));
        Assert.Equal("Resets: now", Line(English, ResetsAt, ResetsAt));

        var oneSecondPast = ResetsAt.AddSeconds(1);
        Assert.Equal("Sıfırlama: şimdi", Line(Turkish, ResetsAt, oneSecondPast));
        Assert.Equal("Resets: now", Line(English, ResetsAt, oneSecondPast));
    }

    /// <summary>A reset in the past must not leave its stale clock time on screen.</summary>
    [Fact]
    public void APastResetShowsOnlyTheLocalizedNow()
    {
        var turkishLine = Line(Turkish, ResetsAt, ResetsAt.AddHours(1));
        Assert.Equal("Sıfırlama: şimdi", turkishLine);
        Assert.DoesNotContain("18:45", turkishLine, StringComparison.Ordinal);

        var englishLine = Line(English, ResetsAt, ResetsAt.AddDays(7));
        Assert.Equal("Resets: now", englishLine);
        Assert.DoesNotContain("6:45", englishLine, StringComparison.Ordinal);
        Assert.DoesNotContain("PM", englishLine, StringComparison.Ordinal);
    }

    /// <summary>
    /// A reset that has not happened yet keeps its clock time, including inside
    /// the final minute where the countdown has already floored to "now".
    ///
    /// Dropping the clock there would call a still-future instant due, and
    /// stopping the countdown from flooring would rewrite rounding the tray
    /// tooltip has always used. Neither is acceptable, so both are shown.
    /// Due-ness is decided by comparing the instants, never by reading the
    /// countdown.
    /// </summary>
    [Fact]
    public void AFutureResetKeepsItsClockThroughTheFinalMinute()
    {
        var fiftyNineSecondsBefore = ResetsAt.AddSeconds(-59);

        Assert.Equal("Sıfırlama: 18:45 · şimdi", Line(Turkish, ResetsAt, fiftyNineSecondsBefore));
        Assert.Equal("Resets: 6:45 PM · now", Line(English, ResetsAt, fiftyNineSecondsBefore));

        // One second ahead is still ahead.
        var oneSecondBefore = ResetsAt.AddSeconds(-1);
        Assert.Equal("Sıfırlama: 18:45 · şimdi", Line(Turkish, ResetsAt, oneSecondBefore));
        Assert.Equal("Resets: 6:45 PM · now", Line(English, ResetsAt, oneSecondBefore));

        // The countdown itself is untouched: it still floors to "now" here...
        Assert.Equal("şimdi", Turkish.RelativeReset(ResetsAt, fiftyNineSecondsBefore));
        Assert.Equal("now", English.RelativeReset(ResetsAt, fiftyNineSecondsBefore));

        // ...and still turns over at a whole minute, in both forms.
        var oneMinuteBefore = ResetsAt.AddSeconds(-60);
        Assert.Equal("Sıfırlama: 18:45 · 1dk", Line(Turkish, ResetsAt, oneMinuteBefore));
        Assert.Equal("Resets: 6:45 PM · 1m", Line(English, ResetsAt, oneMinuteBefore));
        Assert.Equal("1dk", Turkish.RelativeReset(ResetsAt, oneMinuteBefore));
        Assert.Equal("1m", English.RelativeReset(ResetsAt, oneMinuteBefore));
    }

    // MARK: - Clock conventions

    [Fact]
    public void EachLanguageKeepsItsOwnClockConvention()
    {
        var morning = new DateTimeOffset(2026, 8, 24, 9, 5, 0, TimeSpan.FromHours(3));

        Assert.Equal("18:45", Turkish.FormattedTime(ResetsAt, Istanbul));
        Assert.Equal("09:05", Turkish.FormattedTime(morning, Istanbul));
        Assert.Equal("6:45 PM", Normalized(English.FormattedTime(ResetsAt, Istanbul)));
        Assert.Equal("9:05 AM", Normalized(English.FormattedTime(morning, Istanbul)));
    }

    /// <summary>No seconds and no zone suffix, at an instant that has both.</summary>
    [Fact]
    public void TheClockCarriesNeitherSecondsNorAZoneSuffix()
    {
        var resetsAt = ResetsAt.AddSeconds(37);

        Assert.Equal("18:45", Turkish.FormattedTime(resetsAt, Istanbul));
        Assert.Equal("6:45 PM", Normalized(English.FormattedTime(resetsAt, Istanbul)));

        var line = Line(Turkish, resetsAt, resetsAt.AddHours(-1));
        Assert.Equal("Sıfırlama: 18:45 · 1sa 0dk", line);
        Assert.DoesNotContain(":37", line, StringComparison.Ordinal);
        Assert.DoesNotContain("+03", line, StringComparison.Ordinal);
    }

    /// <summary>The clock follows the zone it is given; the countdown never does.</summary>
    [Fact]
    public void TheClockFollowsTheTimeZoneWhileTheCountdownDoesNot()
    {
        var now = ResetsAt.AddHours(-3).AddMinutes(-12);

        Assert.Equal("Sıfırlama: 18:45 · 3sa 12dk", Line(Turkish, ResetsAt, now, Istanbul));
        Assert.Equal("Sıfırlama: 15:45 · 3sa 12dk", Line(Turkish, ResetsAt, now, TimeZoneInfo.Utc));
        Assert.Equal("Sıfırlama: 21:15 · 3sa 12dk", Line(Turkish, ResetsAt, now, HalfHourZone));
        Assert.Equal("Resets: 3:45 PM · 3h 12m", Line(English, ResetsAt, now, TimeZoneInfo.Utc));

        // The countdown is identical in every one of them.
        Assert.Equal("3sa 12dk", Turkish.RelativeReset(ResetsAt, now));
        Assert.Equal("3h 12m", English.RelativeReset(ResetsAt, now));
    }

    /// <summary>
    /// The application shows the machine's own local time. The zone parameter
    /// exists for the assertions above and must not change what users see, so
    /// the short overload is pinned to the local zone, and the clock is still
    /// written exactly as it was before that parameter existed — checked across
    /// a year, so any daylight-saving transition of the host zone is included.
    /// </summary>
    [Fact]
    public void TheMachineZoneOverloadKeepsTheExistingLocalClock()
    {
        var now = ResetsAt.AddHours(-3).AddMinutes(-12);

        Assert.Equal(Turkish.ResetDisplay(ResetsAt, now, TimeZoneInfo.Local), Turkish.ResetDisplay(ResetsAt, now));
        Assert.Equal(English.ResetDisplay(ResetsAt, now, TimeZoneInfo.Local), English.ResetDisplay(ResetsAt, now));

        for (var hours = 0; hours < 366 * 24; hours += 7)
        {
            var instant = ResetsAt.AddHours(hours);

            Assert.Equal(
                instant.ToLocalTime().ToString("HH:mm", CultureInfo.GetCultureInfo("tr-TR")),
                Turkish.FormattedTime(instant));
            Assert.Equal(
                instant.ToLocalTime().ToString("h:mm tt", CultureInfo.GetCultureInfo("en-US")),
                English.FormattedTime(instant));
        }
    }

    // MARK: - The countdown is unchanged

    /// <summary>
    /// The countdown wording is unchanged, including its rounding: the detailed
    /// line ends with exactly what the tray tooltip shows.
    /// </summary>
    [Fact]
    public void TheDetailedLineEndsWithTheUnchangedCountdown()
    {
        var now = new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.FromHours(3));

        // Every future offset, down to a single second: the detailed line never
        // drops the countdown, and the countdown is never rewritten to suit it.
        int[] offsets =
        [
            1, 59, 60, 59 * 60, 3_600 + 15 * 60, 5 * 3_600 + 59 * 60 + 59,
            86_400, 6 * 86_400 + 21 * 3_600
        ];

        foreach (var text in new[] { Turkish, English })
        {
            foreach (var offset in offsets)
            {
                var resetsAt = now.AddSeconds(offset);
                var compact = text.RelativeReset(resetsAt, now);
                var detailed = text.ResetDisplay(resetsAt, now, Istanbul);

                Assert.NotNull(detailed);
                Assert.EndsWith($" · {compact}", detailed, StringComparison.Ordinal);
            }
        }
    }

    /// <summary>Rounding is the historical one, floored and clamped.</summary>
    [Fact]
    public void CountdownRoundingIsUnchanged()
    {
        var now = new DateTimeOffset(2026, 8, 24, 12, 0, 0, TimeSpan.FromHours(3));

        Assert.Equal("1h 15m", English.RelativeReset(now.AddSeconds(3_600 + 15 * 60), now));
        Assert.Equal("6d 21h", English.RelativeReset(now.AddSeconds(6 * 86_400 + 21 * 3_600), now));

        // Seconds are dropped, never rounded up.
        Assert.Equal("1m", English.RelativeReset(now.AddSeconds(119), now));
        Assert.Equal("now", English.RelativeReset(now.AddSeconds(59), now));
        Assert.Equal("şimdi", Turkish.RelativeReset(now.AddSeconds(59), now));

        // A past reset clamps to "now" instead of counting upwards.
        Assert.Equal("now", English.RelativeReset(now.AddSeconds(-9_000), now));
        Assert.Equal("şimdi", Turkish.RelativeReset(now.AddSeconds(-9_000), now));
    }

    // MARK: - The usage model is untouched

    /// <summary>
    /// Presentation reads <c>ResetsAt</c>; it never supplies, moves or clears
    /// one. A window that arrived without a reset still has none afterwards, and
    /// one that arrived with a reset still reports the same instant — as does
    /// the summary the tray is built from.
    /// </summary>
    [Fact]
    public void RenderingDoesNotAlterTheUsageModel()
    {
        var now = ResetsAt.AddHours(-3).AddMinutes(-12);
        var windows = new[]
        {
            new UsageWindow(UsageWindowKind.FiveHour, 40, ResetsAt, 300),
            new UsageWindow(UsageWindowKind.Weekly, 12, null, 10_080)
        };
        var usage = new ProviderUsage(ProviderNames.Codex, windows, error: null, lastSuccessfulAt: now);
        var usages = new Dictionary<string, ProviderUsage>(StringComparer.Ordinal)
        {
            [ProviderNames.Codex] = usage
        };

        foreach (var window in usage.Windows)
        {
            _ = Turkish.ResetDisplay(window.ResetsAt, now, Istanbul);
        }

        Assert.Equal(ResetsAt, usage.Windows[0].ResetsAt);
        Assert.Null(usage.Windows[1].ResetsAt);
        Assert.Equal(new[] { 40, 12 }, usage.Windows.Select(window => window.UsedPercent));
        Assert.Equal(new[] { 60, 88 }, usage.Windows.Select(window => window.RemainingPercent));
        Assert.Null(usage.Error);
        Assert.Equal(now, usage.LastSuccessfulAt);
        Assert.False(usage.IsStale);

        var summary = UsageSummaryCalculator.Summary(ProviderNames.Codex, usages);
        Assert.NotNull(summary);
        Assert.Equal(ResetsAt, summary.ResetsAt);
        Assert.Equal("Sıfırlama: 18:45 · 3sa 12dk", Line(Turkish, summary.ResetsAt, now));
        Assert.Equal(ResetsAt, summary.ResetsAt);
        Assert.Equal(60, summary.RemainingPercent);
    }

    private static string? Line(Localizer text, DateTimeOffset? resetsAt, DateTimeOffset now) =>
        Line(text, resetsAt, now, Istanbul);

    private static string? Line(
        Localizer text,
        DateTimeOffset? resetsAt,
        DateTimeOffset now,
        TimeZoneInfo timeZone) =>
        Normalized(text.ResetDisplay(resetsAt, now, timeZone));

    /// <summary>
    /// ICU has written the English am/pm separator as both a plain space and a
    /// narrow no-break space depending on its version, so comparisons normalize
    /// it instead of pinning whichever one the host produces.
    /// </summary>
    private static string? Normalized(string? text) =>
        text?.Replace('\u202F', ' ').Replace('\u00A0', ' ');
}
