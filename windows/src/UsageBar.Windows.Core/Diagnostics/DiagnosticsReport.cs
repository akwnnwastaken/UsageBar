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
    /// <summary>
    /// Whether UsageBar is allowed to collect for this provider. Reported
    /// separately from <see cref="Connected"/> on purpose: a deliberately
    /// paused provider must not read as a connected one that stopped producing
    /// data, which is what support would otherwise chase.
    /// </summary>
    bool Collecting,
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
    ProcessParentKind ProcessParentKind = ProcessParentKind.Unknown,
    /// <summary>
    /// The account of the Codex lookup that produced the reported executable
    /// state. Null means no lookup has run, which reads as
    /// <see cref="CodexDiscoveryTrace.NotRun"/>.
    /// </summary>
    CodexDiscoveryTrace? DiscoveryTrace = null);

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

        // The exact-operation trace. The coarse candidate state above says a
        // documented path could be built and the file was not there; these say
        // which source built it, where that source pointed, and what the probe
        // actually hit — the difference between a wrong root and an unreadable
        // file, which the coarse field cannot express.
        var trace = input.DiscoveryTrace ?? CodexDiscoveryTrace.NotRun;
        builder.Append("local_app_data_source_relation=").AppendLine(
            SourceRelation(trace.LocalAppDataSourceRelation));
        builder.Append("local_app_data_root_count=").AppendLine(
            RootCount(trace.LocalAppDataRootCount));
        builder.Append("local_app_data_profile_relation=").AppendLine(
            ProfileRelation(trace.LocalAppDataProfileRelation));
        builder.Append("official_codex_shell_probe=").AppendLine(
            Probe(trace.OfficialCodexShellProbe));
        builder.Append("official_codex_framework_probe=").AppendLine(
            Probe(trace.OfficialCodexFrameworkProbe));
        builder.Append("official_codex_profile_derived_probe=").AppendLine(
            Probe(trace.OfficialCodexProfileDerivedProbe));
        builder.Append("codex_lookup_terminal_stage=").AppendLine(
            LookupStage(trace.TerminalStage));

        // What Win32 said directly, and under what security context. The managed
        // probe folds sharing violations, reparse faults and cloud-provider
        // faults into one io_error, and File.Exists folds that into "absent" —
        // which is how a live I/O failure reaches a report as "not installed".
        var native = trace.OfficialCodexNativeProbe;
        builder.Append("official_codex_native_probe=").AppendLine(NativeProbe(native.State));
        builder.Append("official_codex_native_error_code=").AppendLine(Win32Error(native.Win32ErrorCode));
        builder.Append("official_codex_handle_probe=").AppendLine(HandleProbe(native.HandleState));

        var token = trace.ProcessToken;
        builder.Append("process_token_profile_relation=").AppendLine(
            TokenProfile(token.ProfileRelation));
        builder.Append("process_token_integrity=").AppendLine(Integrity(token.Integrity));
        builder.Append("process_token_elevation=").AppendLine(Elevation(token.Elevation));
        builder.Append("process_token_restricted=").AppendLine(Flag(token.Restricted));
        builder.Append("process_token_appcontainer=").AppendLine(Flag(token.AppContainer));
        builder.Append("process_session_relation=").AppendLine(Session(token.SessionRelation));

        foreach (var provider in input.Providers)
        {
            builder
                .Append(DiagnosticsSanitizer.SafeToken(ProviderNames.Key(provider.ProviderName)))
                .Append("=connected:").Append(Boolean(provider.Connected))
                .Append(",collecting:").Append(Boolean(provider.Collecting))
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

    private static string SourceRelation(FolderSourceRelation relation) => relation switch
    {
        FolderSourceRelation.ShellOnly => "shell_only",
        FolderSourceRelation.FrameworkOnly => "framework_only",
        FolderSourceRelation.Agree => "agree",
        FolderSourceRelation.Differ => "differ",
        _ => "none"
    };

    private static string RootCount(FolderRootCount count) => count switch
    {
        FolderRootCount.One => "one",
        FolderRootCount.Multiple => "multiple",
        _ => "none"
    };

    private static string ProfileRelation(FolderProfileRelation relation) => relation switch
    {
        FolderProfileRelation.AllUnderProfile => "all_under_profile",
        FolderProfileRelation.SomeOutsideProfile => "some_outside_profile",
        FolderProfileRelation.NoneUnderProfile => "none_under_profile",
        _ => "not_comparable"
    };

    private static string Probe(CandidateProbeState state) => state switch
    {
        CandidateProbeState.Exists => "exists",
        CandidateProbeState.NotFound => "not_found",
        CandidateProbeState.AccessDenied => "access_denied",
        CandidateProbeState.IoError => "io_error",
        CandidateProbeState.InvalidRoot => "invalid_root",
        CandidateProbeState.SameAsFramework => "same_as_framework",
        CandidateProbeState.SameAsShell => "same_as_shell",
        _ => "not_constructed"
    };

    private static string LookupStage(CodexLookupStage stage) => stage switch
    {
        CodexLookupStage.OfficialNative => "official_native",
        CodexLookupStage.OtherNative => "other_native",
        CodexLookupStage.Node => "node",
        CodexLookupStage.Untrusted => "untrusted",
        CodexLookupStage.Unsupported => "unsupported",
        _ => "missing"
    };

    private static string NativeProbe(NativeProbeState state) => state switch
    {
        NativeProbeState.Exists => "exists",
        NativeProbeState.FileNotFound => "file_not_found",
        NativeProbeState.PathNotFound => "path_not_found",
        NativeProbeState.AccessDenied => "access_denied",
        NativeProbeState.SharingViolation => "sharing_violation",
        NativeProbeState.LockViolation => "lock_violation",
        NativeProbeState.CantAccessFile => "cant_access_file",
        NativeProbeState.ReparseError => "reparse_error",
        NativeProbeState.CloudUnavailable => "cloud_unavailable",
        NativeProbeState.DeviceError => "device_error",
        NativeProbeState.OtherError => "other_error",
        _ => "not_constructed"
    };

    /// <summary>
    /// The Win32 code as a decimal number. It is the one value here that is not a
    /// closed-set word, and it is safe for the same reason the words are: a
    /// number carries no path, identity, message, command line or credential.
    /// Negative or absurd values are refused rather than echoed.
    /// </summary>
    private static string Win32Error(int? code)
    {
        if (code is not { } value || value == 0)
        {
            return DiagnosticsSanitizer.None;
        }

        return value is > 0 and <= 65535
            ? "win32_" + value.ToString(CultureInfo.InvariantCulture)
            : DiagnosticsSanitizer.Redacted;
    }

    private static string HandleProbe(HandleProbeState state) => state switch
    {
        HandleProbeState.Opened => "opened",
        HandleProbeState.NotFound => "not_found",
        HandleProbeState.AccessDenied => "access_denied",
        HandleProbeState.SharingViolation => "sharing_violation",
        HandleProbeState.ReparseError => "reparse_error",
        HandleProbeState.OtherError => "other_error",
        _ => "not_attempted"
    };

    private static string TokenProfile(TokenProfileRelation relation) => relation switch
    {
        TokenProfileRelation.MatchesResolvedProfile => "matches_resolved_profile",
        TokenProfileRelation.DiffersFromResolvedProfile => "differs_from_resolved_profile",
        _ => "unknown"
    };

    private static string Integrity(TokenIntegrity integrity) => integrity switch
    {
        TokenIntegrity.Low => "low",
        TokenIntegrity.Medium => "medium",
        TokenIntegrity.High => "high",
        TokenIntegrity.System => "system",
        _ => "unknown"
    };

    private static string Elevation(TokenElevation elevation) => elevation switch
    {
        TokenElevation.Default => "default",
        TokenElevation.Limited => "limited",
        TokenElevation.Full => "full",
        _ => "unknown"
    };

    private static string Flag(TokenFlagState flag) => flag switch
    {
        TokenFlagState.Yes => "yes",
        TokenFlagState.No => "no",
        _ => "unknown"
    };

    private static string Session(SessionRelation relation) => relation switch
    {
        SessionRelation.ActiveConsole => "active_console",
        SessionRelation.Other => "other",
        _ => "unknown"
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
