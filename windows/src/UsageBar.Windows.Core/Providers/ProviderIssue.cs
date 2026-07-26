namespace UsageBar.Windows.Core.Providers;

/// <summary>
/// Every failure UsageBar can report for a provider. The codes are a superset of
/// the macOS <c>ProviderIssue</c> codes: the extra ones cover Windows-only
/// failure modes (an installation that cannot be executed without a shell).
/// </summary>
public enum ProviderIssueCode
{
    Refreshing,
    NoData,
    CodexUsageUnavailable,
    CodexLimitMissing,
    CodexNotFound,
    CodexUntrustedExecutable,
    CodexUnsupportedInstallation,
    CodexTimedOut,
    CodexEmptyResponse,
    CodexIncompatible,
    CodexCommandFailed,
    CodexLaunchFailed,
    ClaudeNotFound,
    ClaudeUntrustedExecutable,
    ClaudeUnsupportedInstallation,
    ClaudeNotLoggedIn,
    ClaudeUsageUnreadable,
    ClaudeUsageTimedOut,
    ClaudeLaunchFailed,
    ClaudeCommandFailed,

    /// <summary>
    /// Claude itself reported that it could not find Git Bash. Git for Windows
    /// is optional for a quota query — the query disables tools — so this is
    /// only produced when Claude says so, never assumed from its absence.
    /// </summary>
    ClaudeGitBashMissing,

    /// <summary>WSL is not installed or not usable on this machine.</summary>
    ClaudeWslUnavailable,

    /// <summary>WSL works, but no distribution has a usable Claude Code.</summary>
    ClaudeWslDistributionUnavailable,

    OutputTooLarge,

    /// <summary>The refresh was stopped by the application, not by a failure.</summary>
    Cancelled
}

/// <summary>
/// A provider failure: a fixed diagnostic code plus an optional human-readable
/// detail used only in the UI. The detail never reaches diagnostics output — see
/// <see cref="Diagnostics.DiagnosticsReportBuilder"/>.
/// </summary>
public sealed record ProviderIssue(ProviderIssueCode Code, string? Detail = null)
{
    public static ProviderIssue Refreshing { get; } = new(ProviderIssueCode.Refreshing);
    public static ProviderIssue NoData { get; } = new(ProviderIssueCode.NoData);
    public static ProviderIssue CodexUsageUnavailable { get; } = new(ProviderIssueCode.CodexUsageUnavailable);
    public static ProviderIssue CodexLimitMissing { get; } = new(ProviderIssueCode.CodexLimitMissing);
    public static ProviderIssue CodexNotFound { get; } = new(ProviderIssueCode.CodexNotFound);
    public static ProviderIssue CodexUntrustedExecutable { get; } = new(ProviderIssueCode.CodexUntrustedExecutable);
    public static ProviderIssue CodexUnsupportedInstallation { get; } = new(ProviderIssueCode.CodexUnsupportedInstallation);
    public static ProviderIssue CodexTimedOut { get; } = new(ProviderIssueCode.CodexTimedOut);
    public static ProviderIssue CodexEmptyResponse { get; } = new(ProviderIssueCode.CodexEmptyResponse);
    public static ProviderIssue CodexIncompatible { get; } = new(ProviderIssueCode.CodexIncompatible);
    public static ProviderIssue CodexCommandFailed { get; } = new(ProviderIssueCode.CodexCommandFailed);
    public static ProviderIssue ClaudeNotFound { get; } = new(ProviderIssueCode.ClaudeNotFound);
    public static ProviderIssue ClaudeUntrustedExecutable { get; } = new(ProviderIssueCode.ClaudeUntrustedExecutable);
    public static ProviderIssue ClaudeUnsupportedInstallation { get; } = new(ProviderIssueCode.ClaudeUnsupportedInstallation);
    public static ProviderIssue ClaudeNotLoggedIn { get; } = new(ProviderIssueCode.ClaudeNotLoggedIn);
    public static ProviderIssue ClaudeUsageUnreadable { get; } = new(ProviderIssueCode.ClaudeUsageUnreadable);
    public static ProviderIssue ClaudeUsageTimedOut { get; } = new(ProviderIssueCode.ClaudeUsageTimedOut);
    public static ProviderIssue ClaudeCommandFailed { get; } = new(ProviderIssueCode.ClaudeCommandFailed);
    public static ProviderIssue ClaudeGitBashMissing { get; } = new(ProviderIssueCode.ClaudeGitBashMissing);
    public static ProviderIssue ClaudeWslUnavailable { get; } = new(ProviderIssueCode.ClaudeWslUnavailable);
    public static ProviderIssue ClaudeWslDistributionUnavailable { get; } =
        new(ProviderIssueCode.ClaudeWslDistributionUnavailable);
    public static ProviderIssue Cancelled { get; } = new(ProviderIssueCode.Cancelled);

    public static ProviderIssue CodexLaunchFailed(string? reason) =>
        new(ProviderIssueCode.CodexLaunchFailed, reason);

    public static ProviderIssue ClaudeLaunchFailed(string? reason) =>
        new(ProviderIssueCode.ClaudeLaunchFailed, reason);

    public static ProviderIssue OutputTooLarge(string providerName) =>
        new(ProviderIssueCode.OutputTooLarge, providerName);

    /// <summary>The privacy-safe code. Never contains user data.</summary>
    public string DiagnosticCode => Code switch
    {
        ProviderIssueCode.Refreshing => "refreshing",
        ProviderIssueCode.NoData => "no_data",
        ProviderIssueCode.CodexUsageUnavailable => "codex_usage_unavailable",
        ProviderIssueCode.CodexLimitMissing => "codex_limit_missing",
        ProviderIssueCode.CodexNotFound => "codex_not_found",
        ProviderIssueCode.CodexUntrustedExecutable => "codex_untrusted_executable",
        ProviderIssueCode.CodexUnsupportedInstallation => "codex_unsupported_installation",
        ProviderIssueCode.CodexTimedOut => "codex_timed_out",
        ProviderIssueCode.CodexEmptyResponse => "codex_empty_response",
        ProviderIssueCode.CodexIncompatible => "codex_incompatible",
        ProviderIssueCode.CodexCommandFailed => "codex_command_failed",
        ProviderIssueCode.CodexLaunchFailed => "codex_launch_failed",
        ProviderIssueCode.ClaudeNotFound => "claude_not_found",
        ProviderIssueCode.ClaudeUntrustedExecutable => "claude_untrusted_executable",
        ProviderIssueCode.ClaudeUnsupportedInstallation => "claude_unsupported_installation",
        ProviderIssueCode.ClaudeNotLoggedIn => "claude_not_logged_in",
        ProviderIssueCode.ClaudeUsageUnreadable => "claude_usage_unreadable",
        ProviderIssueCode.ClaudeUsageTimedOut => "claude_usage_timed_out",
        ProviderIssueCode.ClaudeLaunchFailed => "claude_launch_failed",
        ProviderIssueCode.ClaudeCommandFailed => "claude_command_failed",
        ProviderIssueCode.ClaudeGitBashMissing => "claude_git_bash_missing",
        ProviderIssueCode.ClaudeWslUnavailable => "claude_wsl_unavailable",
        ProviderIssueCode.ClaudeWslDistributionUnavailable => "claude_wsl_distribution_unavailable",
        ProviderIssueCode.OutputTooLarge => "output_too_large",
        ProviderIssueCode.Cancelled => "cancelled",
        _ => "unknown"
    };

    /// <summary>
    /// Informational states shown in a neutral color rather than as an error.
    /// </summary>
    public bool IsInformational =>
        Code is ProviderIssueCode.Refreshing or ProviderIssueCode.NoData or ProviderIssueCode.Cancelled;

    /// <summary>All codes a diagnostics report is allowed to emit.</summary>
    public static IReadOnlySet<string> KnownDiagnosticCodes { get; } =
        Enum.GetValues<ProviderIssueCode>()
            .Select(code => new ProviderIssue(code).DiagnosticCode)
            .ToHashSet(StringComparer.Ordinal);
}
