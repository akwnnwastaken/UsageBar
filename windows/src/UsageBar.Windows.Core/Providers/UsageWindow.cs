namespace UsageBar.Windows.Core.Providers;

/// <summary>
/// Classification of a provider-returned quota window. Windows are classified by
/// their duration instead of by position, so an account that only exposes a
/// weekly window is never misread as a five-hour one.
/// </summary>
public readonly record struct UsageWindowKind
{
    public enum Category
    {
        FiveHour,
        /// <summary>The ordinary weekly limit that applies across all models.</summary>
        Weekly,
        /// <summary>
        /// A weekly limit that applies to one model or model family only,
        /// reported beside the ordinary one ("Current week (Opus)").
        /// </summary>
        WeeklyScoped,
        Duration,
        Unknown
    }

    /// <summary>
    /// Longest scope slug kept; anything past it is cut so a history key can
    /// never grow with whatever the provider printed.
    /// </summary>
    public const int MaximumWeeklyScopeLength = 32;

    private UsageWindowKind(Category category, int value, string scope = "")
    {
        CategoryKind = category;
        Value = value;
        Scope = scope;
    }

    public Category CategoryKind { get; }

    /// <summary>Duration in minutes for <see cref="Category.Duration"/>, position for <see cref="Category.Unknown"/>.</summary>
    public int Value { get; }

    /// <summary>
    /// Normalized slug for <see cref="Category.WeeklyScoped"/> (see
    /// <see cref="WeeklyKind"/>), empty for every other category. Never raw
    /// provider text: it becomes part of the history series key.
    /// </summary>
    public string Scope { get; }

    public static UsageWindowKind FiveHour { get; } = new(Category.FiveHour, 0);

    public static UsageWindowKind Weekly { get; } = new(Category.Weekly, 0);

    public static UsageWindowKind WeeklyScoped(string scope) => new(Category.WeeklyScoped, 0, scope);

    public static UsageWindowKind Duration(int minutes) => new(Category.Duration, minutes);

    public static UsageWindowKind Unknown(int position) => new(Category.Unknown, position);

    /// <summary>
    /// Maps the parenthesised qualifier of a "Current week (…)" row to a kind.
    /// No qualifier or "all models" is the ordinary weekly limit. Anything else
    /// is a scoped weekly limit whose scope is a lowercase ASCII slug: runs of
    /// other characters collapsed to "-", one trailing "only" dropped, then cut
    /// to <see cref="MaximumWeeklyScopeLength"/>. A qualifier that leaves no
    /// safe slug behind yields null: the row is skipped rather than mistaken
    /// for the all-models limit.
    /// </summary>
    public static UsageWindowKind? WeeklyKind(string? qualifier)
    {
        var trimmed = (qualifier ?? string.Empty).Trim().ToLowerInvariant();
        if (trimmed.Length == 0 || trimmed == "all models")
        {
            return Weekly;
        }

        // The whole slug first; a separator is only ever written in front of a
        // safe character, so it never leads or trails.
        var slug = new System.Text.StringBuilder(trimmed.Length);
        var pendingSeparator = false;
        foreach (var character in trimmed)
        {
            var isSafe = character is >= 'a' and <= 'z' or >= '0' and <= '9';
            if (isSafe)
            {
                if (pendingSeparator && slug.Length > 0)
                {
                    slug.Append('-');
                }

                pendingSeparator = false;
                slug.Append(character);
            }
            else
            {
                pendingSeparator = true;
            }
        }

        // The semantic suffix goes before the bound, so a cut can never leave
        // a partial "-on" / "-onl" behind.
        var scope = slug.ToString();
        if (scope.EndsWith("-only", StringComparison.Ordinal))
        {
            scope = scope[..^"-only".Length];
        }

        // The bound is the last step; a cut that lands on a separator drops it.
        if (scope.Length > MaximumWeeklyScopeLength)
        {
            scope = scope[..MaximumWeeklyScopeLength];
        }

        scope = scope.TrimEnd('-');
        return scope.Length == 0 ? null : WeeklyScoped(scope);
    }

    /// <summary>
    /// Display name for a scoped weekly limit. Known model families are proper
    /// nouns and are not translated; an unknown slug is shown word by word with
    /// initial capitals ("premium-models" → "Premium Models").
    /// </summary>
    public static string WeeklyScopeDisplayName(string scope) => scope switch
    {
        "opus" => "Opus",
        "sonnet" => "Sonnet",
        "haiku" => "Haiku",
        "fable" => "Fable",
        _ => string.Join(
            ' ',
            scope.Split('-', StringSplitOptions.RemoveEmptyEntries)
                .Select(word => char.ToUpperInvariant(word[0]) + word[1..]))
    };

    /// <summary>
    /// Duration-based classification, matching the macOS rule: 4–6 hours is the
    /// five-hour window, 6–8 days is the weekly window, anything else keeps its
    /// own duration, and a window with no duration is positional/unknown.
    /// </summary>
    public static UsageWindowKind Classified(int? durationMinutes, int position)
    {
        if (durationMinutes is not int minutes)
        {
            return Unknown(position);
        }

        if (minutes >= 4 * 60 && minutes <= 6 * 60)
        {
            return FiveHour;
        }

        if (minutes >= 6 * 24 * 60 && minutes <= 8 * 24 * 60)
        {
            return Weekly;
        }

        return Duration(minutes);
    }

    /// <summary>Stable key used for history series and diagnostics.</summary>
    public string HistoryKey => CategoryKind switch
    {
        Category.FiveHour => "five-hour",
        Category.Weekly => "weekly",
        Category.WeeklyScoped => $"weekly-{Scope}",
        Category.Duration => $"duration-{Value}",
        _ => $"unknown-{Value}"
    };

    public override string ToString() => HistoryKey;
}

/// <summary>A single quota window as reported by a provider.</summary>
public sealed record UsageWindow
{
    public UsageWindow(
        UsageWindowKind kind,
        int usedPercent,
        DateTimeOffset? resetsAt,
        int? durationMinutes)
    {
        Kind = kind;
        UsedPercent = usedPercent;
        ResetsAt = resetsAt;
        DurationMinutes = durationMinutes;
    }

    public static UsageWindow Classified(
        int usedPercent,
        DateTimeOffset? resetsAt,
        int? durationMinutes,
        int position = 0) =>
        new(UsageWindowKind.Classified(durationMinutes, position), usedPercent, resetsAt, durationMinutes);

    public UsageWindowKind Kind { get; }

    public int UsedPercent { get; }

    public DateTimeOffset? ResetsAt { get; }

    public int? DurationMinutes { get; }

    /// <summary>
    /// The value UsageBar shows. The application never displays "used" — every
    /// user-facing percentage is what is left.
    /// </summary>
    public int RemainingPercent => Math.Clamp(100 - UsedPercent, 0, 100);

    public UsageWindow WithRemainingPercent(int remainingPercent) =>
        new(Kind, 100 - Math.Clamp(remainingPercent, 0, 100), ResetsAt, DurationMinutes);
}
