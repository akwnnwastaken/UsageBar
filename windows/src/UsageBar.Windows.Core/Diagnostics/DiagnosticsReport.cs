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
    NativeExecutable,
    NodeLauncher,
    GitForWindows,
    Wsl
}

public enum ProviderExecutableState
{
    Missing,
    Untrusted,
    UnsupportedInstallation,
    Trusted
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
    IReadOnlyList<ProviderDiagnostics> Providers);

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
