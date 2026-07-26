namespace UsageBar.Windows.Core.Policies;

/// <summary>
/// Providers report the remaining percentage as a rounded integer, so two
/// consecutive readings can oscillate (41 ↔ 42) when the true value sits on a
/// rounding boundary. A freshly spawned reader session can also receive a
/// server-side cached snapshot that lags the live value, which surfaces as a
/// several-point rebound (33 → 38).
///
/// Remaining cannot genuinely rise inside a window, so every rise below
/// <see cref="RiseHoldThreshold"/> is held until it persists across
/// <see cref="RisePersistenceThreshold"/> consecutive readings. A reset (a large
/// jump back toward ~100%) stays above the threshold and displays immediately.
/// Recorded history always stays raw.
/// </summary>
public static class UsageDisplayNoiseFilter
{
    /// <summary>Consecutive readings a rise needs before it is believed.</summary>
    public const int RisePersistenceThreshold = 3;

    /// <summary>
    /// Rises below this are treated as noise (rounding or a stale snapshot
    /// rebound) and held; this value and above is a real reset and passes
    /// straight through.
    /// </summary>
    public const int RiseHoldThreshold = 12;

    public readonly record struct Decision(int Displayed, int? PendingRise, int PendingCount);

    public static Decision Decide(int raw, int? previouslyDisplayed, int? pendingRise, int pendingCount)
    {
        var accepted = new Decision(raw, PendingRise: null, PendingCount: 0);
        if (previouslyDisplayed is not int previous)
        {
            return accepted;
        }

        // Falls are real, and a reset-sized jump is real too. Only the small
        // rises in between are held back.
        var rise = raw - previous;
        if (rise < 1 || rise >= RiseHoldThreshold)
        {
            return accepted;
        }

        var count = (pendingRise == raw ? pendingCount : 0) + 1;
        return count >= RisePersistenceThreshold
            ? accepted
            : new Decision(previous, raw, count);
    }
}
