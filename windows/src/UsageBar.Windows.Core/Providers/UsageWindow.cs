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
        Weekly,
        Duration,
        Unknown
    }

    private UsageWindowKind(Category category, int value)
    {
        CategoryKind = category;
        Value = value;
    }

    public Category CategoryKind { get; }

    /// <summary>Duration in minutes for <see cref="Category.Duration"/>, position for <see cref="Category.Unknown"/>.</summary>
    public int Value { get; }

    public static UsageWindowKind FiveHour { get; } = new(Category.FiveHour, 0);

    public static UsageWindowKind Weekly { get; } = new(Category.Weekly, 0);

    public static UsageWindowKind Duration(int minutes) => new(Category.Duration, minutes);

    public static UsageWindowKind Unknown(int position) => new(Category.Unknown, position);

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
