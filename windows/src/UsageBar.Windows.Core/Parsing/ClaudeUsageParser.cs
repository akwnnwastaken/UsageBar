using System.Globalization;
using System.Text.RegularExpressions;
using UsageBar.Windows.Core.Providers;

namespace UsageBar.Windows.Core.Parsing;

/// <summary>
/// Parses the plain-text output of Claude Code's print-mode usage query. Print
/// mode emits one line per window:
/// <code>
/// Current session: 100% used · resets Jul 23 at 10:20pm (Europe/Istanbul)
/// Current week (all models): 53% used · resets Jul 26 at 10pm (Europe/Istanbul)
/// </code>
/// There are no terminal cursor moves, so none of the space-collapse or
/// overlay-height fragility of the interactive panel applies.
/// </summary>
public static partial class ClaudeUsageParser
{
    private const int FiveHourWindowMinutes = 300;
    private const int WeeklyWindowMinutes = 10_080;

    // The label separator is an optional colon: print mode writes
    // "Current session: 41% used", while the older interactive panel wrote
    // "Current session     41% used". Accepting both costs nothing — the
    // percentage still has to be immediately followed by "% used".
    [GeneratedRegex(
        @"Current\s+session\s*:?\s*(\d{1,3}(?:[.,]\d+)?)\s*%\s*used(?:[^\n]*?resets?\s+([^\n]+))?",
        RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex SessionPattern();

    // The label suffix ("(all models)") is lazy so the first percentage after the
    // label wins. A greedy suffix would backtrack into "18% used" and read "8".
    [GeneratedRegex(
        @"Current\s+week[^:\n]*?\s*:?\s*(\d{1,3}(?:[.,]\d+)?)\s*%\s*used(?:[^\n]*?resets?\s+([^\n]+))?",
        RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex WeeklyPattern();

    /// <summary>
    /// Fallback for a reset printed on its own line after the window. The
    /// negative lookahead stops at the next window label so one window can never
    /// pick up another window's reset time.
    /// </summary>
    [GeneratedRegex(
        @"^(?:(?!Current\s+(?:session|week)).){0,1200}?Resets?\s+([^\n]{1,120})",
        RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex FollowingLineResetPattern();

    [GeneratedRegex(@"[│┃].*$", RegexOptions.Singleline)]
    private static partial Regex TrailingBoxDrawingPattern();

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRunPattern();

    /// <summary>
    /// Keywords that mean "not signed in" rather than "unreadable". Deciding
    /// this only after both window lookups failed avoids the historical
    /// false-positive where a banner mentioning "login" aborted a good read.
    /// </summary>
    private static readonly string[] NotLoggedInKeywords =
    {
        "log in", "login", "sign in", "not authenticated", "authenticate"
    };

    public static ProviderUsage Parse(string? raw, DateTimeOffset now)
    {
        var text = raw ?? string.Empty;
        var session = MatchWindow(SessionPattern(), text, now);
        var weekly = MatchWindow(WeeklyPattern(), text, now);

        if (session is null && weekly is null)
        {
            var lower = text.ToLowerInvariant();
            var notLoggedIn = NotLoggedInKeywords.Any(keyword => lower.Contains(keyword, StringComparison.Ordinal));
            return ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                notLoggedIn ? ProviderIssue.ClaudeNotLoggedIn : ProviderIssue.ClaudeUsageUnreadable);
        }

        var windows = new List<UsageWindow>(2);
        if (session is { } sessionWindow)
        {
            windows.Add(new UsageWindow(
                UsageWindowKind.FiveHour,
                sessionWindow.Percent,
                sessionWindow.Reset,
                FiveHourWindowMinutes));
        }

        if (weekly is { } weeklyWindow)
        {
            windows.Add(new UsageWindow(
                UsageWindowKind.Weekly,
                weeklyWindow.Percent,
                weeklyWindow.Reset,
                WeeklyWindowMinutes));
        }

        return new ProviderUsage(ProviderNames.ClaudeCode, windows, error: null);
    }

    private static (int Percent, DateTimeOffset? Reset)? MatchWindow(Regex pattern, string text, DateTimeOffset now)
    {
        var match = pattern.Match(text);
        if (!match.Success)
        {
            return null;
        }

        var normalized = match.Groups[1].Value.Replace(',', '.');
        if (!double.TryParse(normalized, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
        {
            return null;
        }

        var percent = Math.Clamp((int)Math.Round(value, MidpointRounding.AwayFromZero), 0, 100);
        DateTimeOffset? reset = null;
        if (match.Groups.Count > 2 && match.Groups[2].Success)
        {
            reset = ClaudeResetParser.Parse(match.Groups[2].Value.Trim(), now);
        }

        reset ??= FollowingLineReset(text, match.Index + match.Length, now);
        return (percent, reset);
    }

    private static DateTimeOffset? FollowingLineReset(string text, int startIndex, DateTimeOffset now)
    {
        if (startIndex >= text.Length)
        {
            return null;
        }

        // Matched against an explicit substring: the pattern is anchored at the
        // start so the search can never begin past the next window label.
        var match = FollowingLineResetPattern().Match(text[startIndex..]);
        if (!match.Success)
        {
            return null;
        }

        var value = TrailingBoxDrawingPattern().Replace(match.Groups[1].Value, string.Empty);
        value = WhitespaceRunPattern().Replace(value, " ").Trim();
        return ClaudeResetParser.Parse(value, now);
    }
}
