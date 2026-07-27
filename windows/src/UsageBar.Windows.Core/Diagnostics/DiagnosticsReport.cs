using System.Globalization;
using System.Text;
using UsageBar.Windows.Core.Providers;

namespace UsageBar.Windows.Core.Diagnostics;

/// <summary>
/// How a provider is being executed. Only the shape of the installation is
/// exposed — never the path it was found at.
/// </summary>
public enum ProviderAdapterKind
{
    None,

    /// <summary>A real .exe started directly.</summary>
    NativeExecutable,

    /// <summary>A legacy local installation under the user's Claude folder.</summary>
    NativeLocal,

    /// <summary>A JavaScript entry point started through a validated node.exe.</summary>
    NodeLauncher,

    GitForWindows,

    /// <summary>Started inside a WSL distribution through wsl.exe.</summary>
    Wsl
}

public enum ProviderExecutableState
{
    Missing,
    Untrusted,
    UnsupportedInstallation,
    Trusted
}

/// <summary>Whether a known folder resolved to anything at all.</summary>
public enum FolderResolutionState
{
    Available,
    Empty
}

/// <summary>
/// Whether a provider's documented candidate path could even be built, and
/// whether the file is there. "NotConstructed" is the case physical testing
/// pointed at: no root resolved, so the candidate never existed to be checked
/// and the provider looked absent.
/// </summary>
public enum CandidateState
{
    Exists,
    Missing,
    NotConstructed
}

/// <summary>What kind of process started UsageBar. Never a name or a path.</summary>
public enum ProcessParentKind
{
    Unknown,
    Setup,
    Shell,
    Other
}

public enum ProviderDataState
{
    NoData,
    Fresh,
    Stale,
    Error
}

/// <summary>One provider's safe diagnostic facts.</summary>
public sealed record ProviderDiagnostics(
    string ProviderName,
    bool Connected,
    ProviderExecutableState ExecutableState,
    ProviderAdapterKind AdapterKind,
    ProviderDataState DataState,
    IReadOnlyList<string> WindowKinds,
    string IssueCode);

/// <summary>Everything the copied diagnostic summary is allowed to contain.</summary>
public sealed record DiagnosticsInput(
    string AppVersion,
    /// <summary>Short commit SHA of the build, so a physical test can be tied to a source revision.</summary>
    string BuildId,
    string WindowsVersion,
    string OsArchitecture,
    string AppArchitecture,
    string Language,
    DateTimeOffset? LastSuccessfulRefresh,
    bool HistoryEnabled,
    int HistorySeriesCount,
    int HistorySampleCount,
    int? TrayGuidanceVersionShown,
    bool AutoStartEnabled,
    IReadOnlyList<ProviderDiagnostics> Providers,
    /// <summary>Whether Local AppData resolved. Never the path itself.</summary>
    FolderResolutionState LocalAppDataState = FolderResolutionState.Available,
    FolderResolutionState UserProfileState = FolderResolutionState.Available,
    CandidateState OfficialCodexCandidateState = CandidateState.NotConstructed,
    ProcessParentKind ProcessParentKind = ProcessParentKind.Unknown);

/// <summary>
/// Builds the privacy-safe diagnostic summary.
///
/// Nothing reaches the output without passing through
/// <see cref="DiagnosticsSanitizer"/>: raw provider output, tokens, executable
/// paths, user profile paths, WSL home paths, project paths, environment values
/// and command lines can never appear, even if a caller mistakenly supplies one.
/// </summary>
public static class DiagnosticsReportBuilder
{
    public static string Build(DiagnosticsInput input)
    {
        ArgumentNullException.ThrowIfNull(input);

        var builder = new StringBuilder();
        builder.Append("UsageBar ").AppendLine(DiagnosticsSanitizer.SafeToken(input.AppVersion));
        builder.Append("build=").AppendLine(DiagnosticsSanitizer.SafeToken(input.BuildId));
        builder.Append("windows=").AppendLine(DiagnosticsSanitizer.SafeToken(input.WindowsVersion));
        builder.Append("os_arch=").AppendLine(DiagnosticsSanitizer.SafeToken(input.OsArchitecture));
        builder.Append("app_arch=").AppendLine(DiagnosticsSanitizer.SafeToken(input.AppArchitecture));
        builder.Append("language=").AppendLine(DiagnosticsSanitizer.SafeToken(input.Language));
        builder.Append("last_refresh=").AppendLine(
            input.LastSuccessfulRefresh is DateTimeOffset refreshedAt
                ? refreshedAt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture)
                : "never");
        builder.Append("history_enabled=").AppendLine(Boolean(input.HistoryEnabled));
        builder.Append("history_series=").AppendLine(Count(input.HistorySeriesCount));
        builder.Append("history_samples=").AppendLine(Count(input.HistorySampleCount));
        builder.Append("tray_guidance_version=").AppendLine(
            input.TrayGuidanceVersionShown is int version ? Count(version) : "none");
        builder.Append("autostart=").AppendLine(Boolean(input.AutoStartEnabled));

        // Launch-context facts. These exist because provider discovery was seen
        // to depend on how UsageBar was started; they are states, never paths.
        builder.Append("local_app_data_state=").AppendLine(FolderState(input.LocalAppDataState));
        builder.Append("user_profile_state=").AppendLine(FolderState(input.UserProfileState));
        builder.Append("official_codex_candidate_state=").AppendLine(
            Candidate(input.OfficialCodexCandidateState));
        builder.Append("process_parent_kind=").AppendLine(ParentKind(input.ProcessParentKind));

        foreach (var provider in input.Providers)
        {
            builder
                .Append(DiagnosticsSanitizer.SafeToken(ProviderNames.Key(provider.ProviderName)))
                .Append("=connected:").Append(Boolean(provider.Connected))
                .Append(",executable:").Append(ExecutableState(provider.ExecutableState))
                .Append(",adapter:").Append(AdapterKind(provider.AdapterKind))
                .Append(",state:").Append(DataState(provider.DataState))
                .Append(",windows:").Append(WindowKinds(provider.WindowKinds))
                .Append(",issue:").AppendLine(IssueCode(provider.IssueCode));
        }

        return builder.ToString().TrimEnd('\r', '\n');
    }

    private static string Boolean(bool value) => value ? "true" : "false";

    private static string FolderState(FolderResolutionState state) =>
        state == FolderResolutionState.Available ? "available" : "empty";

    private static string Candidate(CandidateState state) => state switch
    {
        CandidateState.Exists => "exists",
        CandidateState.Missing => "missing",
        _ => "not_constructed"
    };

    private static string ParentKind(ProcessParentKind kind) => kind switch
    {
        ProcessParentKind.Setup => "setup",
        ProcessParentKind.Shell => "shell",
        ProcessParentKind.Other => "other",
        _ => "unknown"
    };

    private static string Count(int value) => Math.Max(0, value).ToString(CultureInfo.InvariantCulture);

    private static string ExecutableState(ProviderExecutableState state) => state switch
    {
        ProviderExecutableState.Trusted => "trusted",
        ProviderExecutableState.Untrusted => "untrusted",
        ProviderExecutableState.UnsupportedInstallation => "unsupported_installation",
        _ => "missing"
    };

    private static string AdapterKind(ProviderAdapterKind kind) => kind switch
    {
        ProviderAdapterKind.NativeExecutable => "native_exe",
        ProviderAdapterKind.NativeLocal => "native_local",
        ProviderAdapterKind.NodeLauncher => "node_launcher",
        ProviderAdapterKind.GitForWindows => "git_for_windows",
        ProviderAdapterKind.Wsl => "wsl",
        _ => "none"
    };

    private static string DataState(ProviderDataState state) => state switch
    {
        ProviderDataState.Fresh => "fresh",
        ProviderDataState.Stale => "stale",
        ProviderDataState.Error => "error",
        _ => "no_data"
    };

    private static string WindowKinds(IReadOnlyList<string> kinds)
    {
        if (kinds.Count == 0)
        {
            return "none";
        }

        return string.Join("+", kinds.Select(DiagnosticsSanitizer.SafeToken));
    }

    /// <summary>
    /// Issue codes come from a closed set (plus the "no issue" sentinel).
    /// Anything else is reported as redacted rather than echoed, so a caller can
    /// never leak text through this field.
    /// </summary>
    private static string IssueCode(string? code)
    {
        if (string.IsNullOrWhiteSpace(code) || code == DiagnosticsSanitizer.None)
        {
            return DiagnosticsSanitizer.None;
        }

        return ProviderIssue.KnownDiagnosticCodes.Contains(code) ? code : DiagnosticsSanitizer.Redacted;
    }
}
