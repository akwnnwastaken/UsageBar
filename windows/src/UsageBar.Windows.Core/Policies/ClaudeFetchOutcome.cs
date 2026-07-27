namespace UsageBar.Windows.Core.Policies;

public enum ClaudeFetchOutcome
{
    /// <summary>Usage was parsed from the output.</summary>
    Usage,

    /// <summary>The output exceeded the capture limit.</summary>
    OutputTooLarge,

    /// <summary>Claude ran but is not signed in.</summary>
    NotLoggedIn,

    /// <summary>Claude reported it could not find Git Bash.</summary>
    GitBashMissing,

    /// <summary>The run was ended by UsageBar's deadline.</summary>
    TimedOut,

    /// <summary>The run was stopped by the application, not by a failure.</summary>
    Cancelled,

    /// <summary>Claude exited non-zero without producing readable usage.</summary>
    CommandFailed,

    /// <summary>Claude ran and exited cleanly, but its output could not be read.</summary>
    Unreadable
}

/// <summary>
/// Classifies a Claude usage query from pure inputs, so the ordering is testable
/// without an installed Claude.
///
/// The ordering mirrors the Codex classifier for the same reason it exists
/// there: UsageBar terminates a timed-out or cancelled run itself, which leaves
/// the child with a non-zero exit code. That code must never be read as a
/// command failure. A verdict the parser could reach on its own — signed out, or
/// a Git Bash complaint — outranks the exit code too, because it is a better
/// explanation than "the command failed".
/// </summary>
public static class ClaudeFetchOutcomeClassifier
{
    public static ClaudeFetchOutcome Classify(
        bool hasUsage,
        bool outputExceeded,
        bool notLoggedIn,
        bool gitBashMissing,
        bool didTimeout,
        bool wasCancelled,
        int exitCode)
    {
        if (outputExceeded)
        {
            return ClaudeFetchOutcome.OutputTooLarge;
        }

        if (hasUsage)
        {
            return ClaudeFetchOutcome.Usage;
        }

        // A stopped run explains itself; the exit code it produced is ours.
        if (wasCancelled)
        {
            return ClaudeFetchOutcome.Cancelled;
        }

        if (didTimeout)
        {
            return ClaudeFetchOutcome.TimedOut;
        }

        if (notLoggedIn)
        {
            return ClaudeFetchOutcome.NotLoggedIn;
        }

        if (gitBashMissing)
        {
            return ClaudeFetchOutcome.GitBashMissing;
        }

        return exitCode != 0 ? ClaudeFetchOutcome.CommandFailed : ClaudeFetchOutcome.Unreadable;
    }
}

/// <summary>
/// Which Claude installation form UsageBar should use. "Automatic" tries the
/// native Windows installation first and falls back to WSL.
/// </summary>
public enum ClaudeAdapterMode
{
    Automatic,
    NativeWindows,
    Wsl
}

public static class ClaudeAdapterModes
{
    public static IReadOnlyList<ClaudeAdapterMode> All { get; } = new[]
    {
        ClaudeAdapterMode.Automatic,
        ClaudeAdapterMode.NativeWindows,
        ClaudeAdapterMode.Wsl
    };

    public static string StorageValue(this ClaudeAdapterMode mode) => mode switch
    {
        ClaudeAdapterMode.NativeWindows => "nativeWindows",
        ClaudeAdapterMode.Wsl => "wsl",
        _ => "automatic"
    };

    public static ClaudeAdapterMode Resolved(string? storedValue) => storedValue switch
    {
        "nativeWindows" => ClaudeAdapterMode.NativeWindows,
        "wsl" => ClaudeAdapterMode.Wsl,
        _ => ClaudeAdapterMode.Automatic
    };

    /// <summary>Whether a given adapter may be tried under the selected mode.</summary>
    public static bool AllowsNativeWindows(this ClaudeAdapterMode mode) =>
        mode is ClaudeAdapterMode.Automatic or ClaudeAdapterMode.NativeWindows;

    public static bool AllowsWsl(this ClaudeAdapterMode mode) =>
        mode is ClaudeAdapterMode.Automatic or ClaudeAdapterMode.Wsl;
}
