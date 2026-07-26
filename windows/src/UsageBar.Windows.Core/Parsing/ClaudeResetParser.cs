using System.Globalization;
using System.Text.RegularExpressions;

namespace UsageBar.Windows.Core.Parsing;

/// <summary>
/// Parses the reset text Claude prints after "resets", e.g.
/// <c>Jul 26 at 10pm (Europe/Istanbul)</c>, <c>5pm</c>, <c>4:59pm</c>,
/// <c>in 2 hours 15 minutes</c>.
///
/// All date math happens in the reset's own time zone, never the machine's, so
/// a roll-forward across a DST boundary preserves the wall-clock hour.
/// </summary>
public static partial class ClaudeResetParser
{
    private static readonly string[] MonthNames =
    {
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
    };

    [GeneratedRegex(@"^\s*(?:at|by)\s+", RegexOptions.IgnoreCase)]
    private static partial Regex LeadingPrepositionPattern();

    [GeneratedRegex(@"^\s*in\s+", RegexOptions.IgnoreCase)]
    private static partial Regex RelativePrefixPattern();

    [GeneratedRegex(@"\(([^()]+)\)\s*$")]
    private static partial Regex TrailingZonePattern();

    [GeneratedRegex(@"(\d+)\s*(?:days?|d)\b", RegexOptions.IgnoreCase)]
    private static partial Regex RelativeDaysPattern();

    [GeneratedRegex(@"(\d+)\s*(?:hours?|hrs?|h)\b", RegexOptions.IgnoreCase)]
    private static partial Regex RelativeHoursPattern();

    [GeneratedRegex(@"(\d+)\s*(?:minutes?|mins?|m)\b", RegexOptions.IgnoreCase)]
    private static partial Regex RelativeMinutesPattern();

    [GeneratedRegex(@"([A-Za-z])([0-9])")]
    private static partial Regex LetterDigitBoundaryPattern();

    [GeneratedRegex(@"([0-9])([A-Za-z])")]
    private static partial Regex DigitLetterBoundaryPattern();

    [GeneratedRegex(@"([0-9])\s+([AaPp][Mm])\b")]
    private static partial Regex DetachedMeridiemPattern();

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRunPattern();

    /// <summary>
    /// Absolute date/time shapes Claude is known to print. All parts are
    /// optional except that at least a date or a time must be present:
    /// optional weekday, optional "MMM d[, yyyy]", optional "," / "at"
    /// separator, optional "h[:mm]am/pm".
    /// </summary>
    [GeneratedRegex(
        """
        ^
        (?:(?<weekday>mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)[a-z]*\.?,?\s+)?
        (?:(?<month>jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(?<day>\d{1,2})(?:\s*,\s*(?<year>\d{4}))?)?
        (?:\s*(?:,|at)\s*)?
        (?:(?<hour>\d{1,2})(?::(?<minute>\d{2}))?\s*(?<meridiem>[ap])\.?m\.?)?
        \s*$
        """,
        RegexOptions.IgnoreCase | RegexOptions.IgnorePatternWhitespace)]
    private static partial Regex AbsoluteResetPattern();

    public static DateTimeOffset? Parse(string? raw, DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        var value = LeadingPrepositionPattern().Replace(raw, string.Empty).Trim();

        if (RelativePrefixPattern().IsMatch(value))
        {
            var relative = ParseRelative(value);
            if (relative is TimeSpan offset && offset > TimeSpan.Zero)
            {
                return now + offset;
            }
        }

        var zone = TimeZoneInfo.Local;
        var dateText = value;
        var zoneMatch = TrailingZonePattern().Match(dateText);
        if (zoneMatch.Success)
        {
            if (TryFindZone(zoneMatch.Groups[1].Value, out var parsedZone))
            {
                zone = parsedZone;
            }

            dateText = dateText.Remove(zoneMatch.Index, zoneMatch.Length).Trim();
        }

        // Claude's interactive panel positions text with cursor moves rather than
        // literal spaces, so a stripped screen can arrive concatenated
        // ("Jul26at10pm"). Re-insert separators at letter/digit boundaries and
        // reattach the am/pm suffix. Print-mode text is unaffected.
        dateText = LetterDigitBoundaryPattern().Replace(dateText, "$1 $2");
        dateText = DigitLetterBoundaryPattern().Replace(dateText, "$1 $2");
        dateText = DetachedMeridiemPattern().Replace(dateText, "$1$2");
        dateText = WhitespaceRunPattern().Replace(dateText, " ").Trim();

        return ParseAbsolute(dateText, zone, now);
    }

    private static TimeSpan? ParseRelative(string value)
    {
        var total = TimeSpan.Zero;
        var matched = false;

        foreach (var (pattern, unit) in new (Regex, TimeSpan)[]
                 {
                     (RelativeDaysPattern(), TimeSpan.FromDays(1)),
                     (RelativeHoursPattern(), TimeSpan.FromHours(1)),
                     (RelativeMinutesPattern(), TimeSpan.FromMinutes(1))
                 })
        {
            var match = pattern.Match(value);
            if (match.Success &&
                double.TryParse(match.Groups[1].Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var count))
            {
                total += unit * count;
                matched = true;
            }
        }

        return matched ? total : null;
    }

    private static DateTimeOffset? ParseAbsolute(string text, TimeZoneInfo zone, DateTimeOffset now)
    {
        if (text.Length == 0)
        {
            return null;
        }

        var match = AbsoluteResetPattern().Match(text);
        if (!match.Success)
        {
            return null;
        }

        var hasDate = match.Groups["month"].Success && match.Groups["day"].Success;
        var hasYear = match.Groups["year"].Success;
        var hasTime = match.Groups["hour"].Success;
        if (!hasDate && !hasTime)
        {
            return null;
        }

        var nowInZone = TimeZoneInfo.ConvertTime(now, zone);

        int year;
        int month;
        int day;
        if (hasDate)
        {
            month = Array.IndexOf(MonthNames, match.Groups["month"].Value.ToLowerInvariant()) + 1;
            if (month == 0)
            {
                return null;
            }

            day = int.Parse(match.Groups["day"].Value, CultureInfo.InvariantCulture);
            year = hasYear
                ? int.Parse(match.Groups["year"].Value, CultureInfo.InvariantCulture)
                : nowInZone.Year;

            if (day < 1 || day > DateTime.DaysInMonth(year, month))
            {
                return null;
            }
        }
        else
        {
            year = nowInZone.Year;
            month = nowInZone.Month;
            day = nowInZone.Day;
        }

        int hour;
        var minute = 0;
        if (hasTime)
        {
            hour = int.Parse(match.Groups["hour"].Value, CultureInfo.InvariantCulture);
            if (hour is < 1 or > 12)
            {
                return null;
            }

            // A minute-less time ("10pm") pins to the top of the hour so the
            // countdown is not offset by the current minute-of-hour.
            if (match.Groups["minute"].Success)
            {
                minute = int.Parse(match.Groups["minute"].Value, CultureInfo.InvariantCulture);
                if (minute > 59)
                {
                    return null;
                }
            }

            var isPm = match.Groups["meridiem"].Value.Equals("p", StringComparison.OrdinalIgnoreCase);
            hour = hour % 12 + (isPm ? 12 : 0);
        }
        else
        {
            // Date-only ("Resets Aug 1"): keep the current hour, top of the hour.
            hour = nowInZone.Hour;
        }

        var wall = new DateTime(year, month, day, hour, minute, 0, DateTimeKind.Unspecified);
        var instant = ToInstant(wall, zone);

        // Roll forward in the reset's own zone. Adding a calendar day or year to
        // the wall clock is DST-aware; adding a fixed 24 hours would land an hour
        // off across a DST change.
        if (!hasDate && instant <= now)
        {
            instant = ToInstant(wall.AddDays(1), zone);
        }
        else if (hasDate && !hasYear && instant < now)
        {
            instant = ToInstant(wall.AddYears(1), zone);
        }

        return instant;
    }

    private static DateTimeOffset ToInstant(DateTime wall, TimeZoneInfo zone)
    {
        // A spring-forward gap has no such wall clock; step forward to the first
        // valid instant. An ambiguous (fall-back) time resolves to the first
        // occurrence, matching the macOS calendar behavior.
        var candidate = DateTime.SpecifyKind(wall, DateTimeKind.Unspecified);
        for (var attempt = 0; attempt < 4 && zone.IsInvalidTime(candidate); attempt++)
        {
            candidate = candidate.AddHours(1);
        }

        if (zone.IsInvalidTime(candidate))
        {
            return new DateTimeOffset(candidate, TimeSpan.Zero);
        }

        var offset = zone.IsAmbiguousTime(candidate)
            ? zone.GetAmbiguousTimeOffsets(candidate).Max()
            : zone.GetUtcOffset(candidate);

        return new DateTimeOffset(candidate, offset);
    }

    private static bool TryFindZone(string identifier, out TimeZoneInfo zone)
    {
        var trimmed = identifier.Trim();
        try
        {
            zone = TimeZoneInfo.FindSystemTimeZoneById(trimmed);
            return true;
        }
        catch (TimeZoneNotFoundException)
        {
        }
        catch (InvalidTimeZoneException)
        {
        }

        // Windows ships Windows zone identifiers; .NET maps IANA identifiers when
        // ICU is available, and this converts the other direction as a fallback.
        if (TimeZoneInfo.TryConvertIanaIdToWindowsId(trimmed, out var windowsId) && windowsId is not null)
        {
            try
            {
                zone = TimeZoneInfo.FindSystemTimeZoneById(windowsId);
                return true;
            }
            catch (TimeZoneNotFoundException)
            {
            }
            catch (InvalidTimeZoneException)
            {
            }
        }

        zone = TimeZoneInfo.Local;
        return false;
    }
}
