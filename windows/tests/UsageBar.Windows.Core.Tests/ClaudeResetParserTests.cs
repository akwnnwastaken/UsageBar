using UsageBar.Windows.Core.Parsing;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// Reset parsing must resolve in the reset's own time zone, never the machine's,
/// and roll forward DST-aware. These are the macOS expectations.
/// </summary>
public sealed class ClaudeResetParserTests
{
    private const string Istanbul = "Europe/Istanbul";
    private const string NewYork = "America/New_York";

    private static DateTimeOffset Instant(int year, int month, int day, int hour, int minute, string zoneId)
    {
        var zone = FindZone(zoneId);
        var wall = new DateTime(year, month, day, hour, minute, 0, DateTimeKind.Unspecified);
        return new DateTimeOffset(wall, zone.GetUtcOffset(wall));
    }

    /// <summary>
    /// Resolves an IANA zone. .NET accepts IANA identifiers on Windows when ICU
    /// is available; the conversion is the fallback for a machine without it, so
    /// the expectations hold on any runner.
    /// </summary>
    private static TimeZoneInfo FindZone(string zoneId)
    {
        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById(zoneId);
        }
        catch (TimeZoneNotFoundException)
        {
            if (TimeZoneInfo.TryConvertIanaIdToWindowsId(zoneId, out var windowsId) && windowsId is not null)
            {
                return TimeZoneInfo.FindSystemTimeZoneById(windowsId);
            }

            Assert.Fail($"Time zone {zoneId} is unavailable on this machine.");
            throw;
        }
    }

    private static DateTimeOffset? Reset(string text, DateTimeOffset now) =>
        ClaudeUsageParser.Parse($"Current session: 10% used · resets {text}", now).Session?.ResetsAt;

    [Fact]
    public void ResolvesInTheResetZoneNotTheMachineZone()
    {
        Assert.Equal(
            Instant(2026, 7, 26, 22, 0, Istanbul),
            Reset("Jul 26 at 10pm (Europe/Istanbul)", Instant(2026, 7, 20, 12, 0, Istanbul)));
    }

    [Fact]
    public void MinuteLessTimePinsToTheTopOfTheHourAndRollsForward()
    {
        Assert.Equal(
            Instant(2026, 3, 11, 17, 0, NewYork),
            Reset("5pm (America/New_York)", Instant(2026, 3, 10, 18, 0, NewYork)));
    }

    [Fact]
    public void MinutesAreKeptWhenPresent()
    {
        Assert.Equal(
            Instant(2026, 3, 10, 16, 59, NewYork),
            Reset("4:59pm (America/New_York)", Instant(2026, 3, 10, 12, 0, NewYork)));
    }

    [Fact]
    public void YearEndRollAdvancesAYearInZone()
    {
        Assert.Equal(
            Instant(2027, 1, 1, 1, 0, NewYork),
            Reset("Jan 1 at 1am (America/New_York)", Instant(2026, 12, 15, 12, 0, NewYork)));
    }

    /// <summary>
    /// Spring-forward: rolling 1am forward a day across the US change preserves
    /// the 1am wall clock. Adding a fixed 24 hours would land an hour off.
    /// </summary>
    [Fact]
    public void DayRollPreservesTheWallClockAcrossDst()
    {
        Assert.Equal(
            Instant(2026, 3, 9, 1, 0, NewYork),
            Reset("1am (America/New_York)", Instant(2026, 3, 8, 3, 0, NewYork)));
    }

    [Fact]
    public void RelativeResetsAreAddedToNow()
    {
        var now = Instant(2026, 7, 20, 12, 0, Istanbul);
        Assert.Equal(now.AddHours(2).AddMinutes(15), Reset("in 2 hours 15 minutes", now));
        Assert.Equal(now.AddDays(6).AddHours(21), Reset("in 6 days 21 hours", now));
    }

    [Fact]
    public void DateWithExplicitYearIsNotRolledForward()
    {
        Assert.Equal(
            Instant(2026, 7, 29, 23, 59, Istanbul),
            Reset("Jul 29, 2026, 11:59pm (Europe/Istanbul)", Instant(2026, 7, 20, 12, 0, Istanbul)));
    }

    [Fact]
    public void CollapsedPanelTextIsSeparatedBeforeParsing()
    {
        // The interactive panel could render "Jul 26 at 10pm" without spaces.
        Assert.Equal(
            Instant(2026, 7, 26, 22, 0, Istanbul),
            ClaudeResetParser.Parse("Jul26at10pm (Europe/Istanbul)", Instant(2026, 7, 20, 12, 0, Istanbul)));
    }

    [Fact]
    public void UnparseableResetTextYieldsNull()
    {
        var now = Instant(2026, 7, 20, 12, 0, Istanbul);
        Assert.Null(ClaudeResetParser.Parse(null, now));
        Assert.Null(ClaudeResetParser.Parse("   ", now));
        Assert.Null(ClaudeResetParser.Parse("whenever it feels like it", now));
        Assert.Null(ClaudeResetParser.Parse("Feb 30 at 1am", now));
        Assert.Null(ClaudeResetParser.Parse("25:99pm", now));
    }

    [Fact]
    public void AnUnknownZoneFallsBackWithoutThrowing()
    {
        var now = Instant(2026, 7, 20, 12, 0, Istanbul);
        Assert.NotNull(ClaudeResetParser.Parse("Jul 26 at 10pm (Middle/Earth)", now));
    }
}
