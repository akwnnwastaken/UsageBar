using System.Runtime.Versioning;
using System.Text;
using System.Text.Json;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Core.Parsing;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Infrastructure.Discovery;
using UsageBar.Windows.Infrastructure.Process;

namespace UsageBar.Windows.Infrastructure.Providers;

/// <summary>
/// Reads Codex quota over the app-server's stdio JSON-RPC interface — the same
/// structured request the macOS build uses, not a screen scrape.
///
/// The process is contained in a Job Object, runs from UsageBar's own temporary
/// directory with a restricted environment, produces at most 2 MiB of output and
/// is torn down (whole tree) on completion, timeout or cancellation.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class CodexUsageReader
{
    /// <summary>
    /// UsageBar only needs the account quota RPC. Disabling unrelated app and
    /// plugin features avoids background catalog scans and their file/network
    /// access. A CLI that rejects these flags is reported as incompatible rather
    /// than retried without them.
    /// </summary>
    internal static readonly string[] AppServerArguments =
    {
        "app-server", "--stdio",
        "--disable", "apps",
        "--disable", "plugins",
        "--disable", "remote_plugin",
        "--disable", "plugin_sharing"
    };

    private readonly CodexExecutableLocator _locator;
    private readonly string _clientVersion;

    public CodexUsageReader(CodexExecutableLocator? locator = null, string? clientVersion = null)
    {
        _locator = locator ?? new CodexExecutableLocator();
        _clientVersion = clientVersion ?? "1.9.0";
    }

    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(15);

    /// <summary>The adapter kind of the last successful lookup, for diagnostics.</summary>
    public ProviderAdapterKind LastAdapterKind { get; private set; } = ProviderAdapterKind.None;

    public ProviderExecutableState LastExecutableState { get; private set; } = ProviderExecutableState.Missing;

    public async Task<ProviderUsage> ReadAsync(
        string? userSelectedPath = null,
        CancellationToken cancellationToken = default)
    {
        var lookup = _locator.Locate(userSelectedPath);
        LastAdapterKind = lookup.AdapterKind;
        LastExecutableState = lookup.DiagnosticState;

        switch (lookup.Status)
        {
            case ExecutableLookupStatus.Missing:
                return ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexNotFound);
            case ExecutableLookupStatus.Untrusted:
                return ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexUntrustedExecutable);
            case ExecutableLookupStatus.UnsupportedInstallation:
                return ProviderUsage.Unavailable(
                    ProviderNames.Codex,
                    ProviderIssue.CodexUnsupportedInstallation);
        }

        var executable = lookup.Executable!;
        var request = new ProviderProcessRequest
        {
            ExecutablePath = executable.Path,
            Arguments = executable.BuildArguments(AppServerArguments),
            StandardInput = Encoding.UTF8.GetBytes(HandshakeMessages(_clientVersion)),
            // The app server keeps reading requests, so stdin stays open until
            // the run ends; closing it early can make it shut down mid-answer.
            CloseStandardInputAfterWrite = false,
            Timeout = Timeout,
            IsComplete = static output => CodexResponseParser.ParseStream(output.Span) is not null
        };

        var result = await ProviderProcessLauncher.RunAsync(request, cancellationToken).ConfigureAwait(false);
        return Interpret(result);
    }

    /// <summary>
    /// The JSON-RPC handshake plus the quota request, newline-delimited. Request
    /// id 2 is the one the parser accepts as the usage answer.
    /// </summary>
    internal static string HandshakeMessages(string clientVersion)
    {
        var version = JsonEncodedText.Encode(clientVersion).ToString();
        var initialize =
            "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":" +
            "{\"name\":\"usage_bar\",\"title\":\"UsageBar\",\"version\":\"" + version + "\"}}}";

        return string.Join('\n', initialize,
            "{\"method\":\"initialized\"}",
            "{\"method\":\"account/rateLimits/read\",\"id\":2}") + "\n";
    }

    internal static ProviderUsage Interpret(ProviderProcessResult result)
    {
        ArgumentNullException.ThrowIfNull(result);

        if (!result.Launched)
        {
            return ProviderUsage.Unavailable(
                ProviderNames.Codex,
                ProviderIssue.CodexLaunchFailed(result.LaunchFailure));
        }

        var usage = CodexResponseParser.ParseStream(result.StandardOutput);
        var hasUsage = usage is { Error: null, Windows.Count: > 0 };

        var outcome = CodexFetchOutcomeClassifier.Classify(
            hasUsage,
            result.OutputExceeded || result.ErrorExceeded,
            IsIncompatible(result.StandardError),
            result.TimedOut,
            result.ExitCode);

        return outcome switch
        {
            CodexFetchOutcome.Usage =>
                usage ?? ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexEmptyResponse),
            CodexFetchOutcome.OutputTooLarge =>
                ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.OutputTooLarge(ProviderNames.Codex)),
            CodexFetchOutcome.Incompatible =>
                ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexIncompatible),
            CodexFetchOutcome.TimedOut =>
                ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexTimedOut),
            CodexFetchOutcome.CommandFailed =>
                ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexCommandFailed),
            _ =>
                // A parsed response that carried an explicit error keeps that
                // error rather than being flattened into "empty".
                usage ?? ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexEmptyResponse)
        };
    }

    /// <summary>
    /// A CLI that does not understand the safe-disable flags fails closed: it is
    /// reported as incompatible instead of being retried without the flags.
    /// </summary>
    internal static bool IsIncompatible(ReadOnlySpan<byte> standardError)
    {
        if (standardError.IsEmpty)
        {
            return false;
        }

        var message = Encoding.UTF8.GetString(standardError).ToLowerInvariant();
        var mentionsDisableFlag = message.Contains("--disable", StringComparison.Ordinal);
        var signalsUnknownOption =
            message.Contains("unexpected argument", StringComparison.Ordinal) ||
            message.Contains("unknown option", StringComparison.Ordinal) ||
            message.Contains("unrecognized option", StringComparison.Ordinal);

        return mentionsDisableFlag && signalsUnknownOption;
    }
}
