namespace UsageBar.Windows.Core.Policies;

public enum CodexFetchOutcome
{
    Usage,
    OutputTooLarge,
    Incompatible,
    TimedOut,
    CommandFailed,
    EmptyResponse
}

/// <summary>
/// Classifies a Codex fetch from pure inputs so the ordering is testable without
/// spawning a process. The key rule, carried over from macOS: a fetch that ran
/// out of time is a <b>timeout</b>, even though UsageBar's own termination
/// leaves the child with a non-zero exit code — that code must never be read as
/// a command failure.
/// </summary>
public static class CodexFetchOutcomeClassifier
{
    public static CodexFetchOutcome Classify(
        bool hasUsage,
        bool outputExceeded,
        bool incompatible,
        bool didTimeout,
        int exitCode)
    {
        if (outputExceeded)
        {
            return CodexFetchOutcome.OutputTooLarge;
        }

        if (hasUsage)
        {
            return CodexFetchOutcome.Usage;
        }

        // Timeout wins over a non-zero exit: that exit is a side effect of the
        // job-object termination UsageBar performed itself.
        if (didTimeout)
        {
            return CodexFetchOutcome.TimedOut;
        }

        if (incompatible)
        {
            return CodexFetchOutcome.Incompatible;
        }

        return exitCode != 0 ? CodexFetchOutcome.CommandFailed : CodexFetchOutcome.EmptyResponse;
    }
}
