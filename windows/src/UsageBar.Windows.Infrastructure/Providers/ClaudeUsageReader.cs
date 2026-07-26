using System.Runtime.Versioning;
using System.Text;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Core.Parsing;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Infrastructure.Discovery;
using UsageBar.Windows.Infrastructure.Wsl;

namespace UsageBar.Windows.Infrastructure.Providers;

public interface IClaudeUsageReader
{
    Task<ProviderUsage> ReadAsync(CancellationToken cancellationToken);

    ProviderAdapterKind LastAdapterKind { get; }

    ProviderExecutableState LastExecutableState { get; }

    /// <summary>The WSL distribution in use, if any. A name only.</summary>
    string? LastWslDistribution { get; }
}

/// <summary>
/// Reads Claude Code quota through whichever adapter this machine supports.
///
/// The reader owns the ordering and the interpretation; the adapters own only
/// discovery and invocation. Output is parsed with the same
/// <see cref="ClaudeUsageParser"/> the macOS build uses, after the process has
/// finished, so a partially written final line can never drop the weekly
/// window.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class ClaudeUsageReader : IClaudeUsageReader
{
    /// <summary>
    /// Phrases Claude uses when it cannot find Git Bash. Only consulted when no
    /// usage parsed, so a healthy read is never reinterpreted.
    /// </summary>
    private static readonly string[] GitBashSignals =
    {
        "git bash", "gitbash", "claude_code_git_bash_path", "bash.exe"
    };

    private readonly ClaudeNativeWindowsAdapter? _native;
    private readonly ClaudeWslAdapter? _wsl;
    private readonly ClaudeAdapterMode _mode;

    public ClaudeUsageReader(
        ClaudeAdapterMode mode = ClaudeAdapterMode.Automatic,
        string? userSelectedPath = null,
        string? wslDistribution = null)
        : this(
            mode.AllowsNativeWindows()
                ? new ClaudeNativeWindowsAdapter(userSelectedPath: userSelectedPath)
                : null,
            mode.AllowsWsl() ? new ClaudeWslAdapter(configuredDistribution: wslDistribution) : null,
            mode)
    {
    }

    internal ClaudeUsageReader(
        ClaudeNativeWindowsAdapter? native,
        ClaudeWslAdapter? wsl,
        ClaudeAdapterMode mode)
    {
        _native = native;
        _wsl = wsl;
        _mode = mode;
    }

    public ProviderAdapterKind LastAdapterKind { get; private set; } = ProviderAdapterKind.None;

    public ProviderExecutableState LastExecutableState { get; private set; } = ProviderExecutableState.Missing;

    public string? LastWslDistribution { get; private set; }

    public async Task<ProviderUsage> ReadAsync(CancellationToken cancellationToken)
    {
        // Native first: it is the documented, recommended Windows installation
        // and needs no distribution to be running.
        if (_native is not null && await _native.IsAvailableAsync(cancellationToken).ConfigureAwait(false))
        {
            LastAdapterKind = _native.Kind;
            LastExecutableState = _native.ExecutableState;
            LastWslDistribution = null;

            var result = await _native.RunUsageQueryAsync(cancellationToken).ConfigureAwait(false);
            return Interpret(result);
        }

        if (_wsl is not null && await _wsl.IsAvailableAsync(cancellationToken).ConfigureAwait(false))
        {
            LastAdapterKind = ProviderAdapterKind.Wsl;
            LastExecutableState = ProviderExecutableState.Trusted;
            LastWslDistribution = _wsl.ResolvedDistribution;

            var result = await _wsl.RunUsageQueryAsync(cancellationToken).ConfigureAwait(false);
            return Interpret(result);
        }

        return Unavailable(cancellationToken);
    }

    /// <summary>
    /// Why nothing could run. The native verdict is preferred when the native
    /// adapter found something it could not use, because that is more actionable
    /// than "no WSL distribution".
    /// </summary>
    private ProviderUsage Unavailable(CancellationToken cancellationToken)
    {
        if (cancellationToken.IsCancellationRequested)
        {
            return ProviderUsage.Unavailable(ProviderNames.ClaudeCode, ProviderIssue.Cancelled);
        }

        var nativeLookup = _native?.Lookup();
        LastAdapterKind = ProviderAdapterKind.None;
        LastExecutableState = nativeLookup?.DiagnosticState ?? ProviderExecutableState.Missing;
        LastWslDistribution = null;

        if (nativeLookup is { Status: ExecutableLookupStatus.Untrusted })
        {
            return ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                ProviderIssue.ClaudeUntrustedExecutable);
        }

        if (nativeLookup is { Status: ExecutableLookupStatus.UnsupportedInstallation })
        {
            return ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                ProviderIssue.ClaudeUnsupportedInstallation);
        }

        if (_wsl is not null)
        {
            switch (_wsl.Availability)
            {
                case WslAvailability.WslUnavailable when _mode == ClaudeAdapterMode.Wsl:
                    return ProviderUsage.Unavailable(
                        ProviderNames.ClaudeCode,
                        ProviderIssue.ClaudeWslUnavailable);
                case WslAvailability.NoDistributions:
                case WslAvailability.ClaudeMissing:
                    return ProviderUsage.Unavailable(
                        ProviderNames.ClaudeCode,
                        ProviderIssue.ClaudeWslDistributionUnavailable);
            }
        }

        return ProviderUsage.Unavailable(ProviderNames.ClaudeCode, ProviderIssue.ClaudeNotFound);
    }

    /// <summary>
    /// Turns one adapter run into a provider reading. Pure, so every outcome is
    /// testable without an installed Claude.
    /// </summary>
    internal static ProviderUsage Interpret(ClaudeAdapterResult result, DateTimeOffset? now = null)
    {
        ArgumentNullException.ThrowIfNull(result);

        if (!result.Launched)
        {
            return ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                ProviderIssue.ClaudeLaunchFailed(result.LaunchFailure));
        }

        var text = Encoding.UTF8.GetString(result.StandardOutput);
        var parsed = ClaudeUsageParser.Parse(text, now ?? DateTimeOffset.Now);
        var hasUsage = parsed is { Error: null, Windows.Count: > 0 };
        var notLoggedIn = parsed.Error?.Code == ProviderIssueCode.ClaudeNotLoggedIn;

        var outcome = ClaudeFetchOutcomeClassifier.Classify(
            hasUsage,
            result.OutputExceeded,
            notLoggedIn,
            MentionsGitBash(result.StandardError, text),
            result.TimedOut,
            result.Cancelled,
            result.ExitCode);

        return outcome switch
        {
            ClaudeFetchOutcome.Usage => parsed,
            ClaudeFetchOutcome.OutputTooLarge => ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                ProviderIssue.OutputTooLarge(ProviderNames.ClaudeCode)),
            ClaudeFetchOutcome.NotLoggedIn => ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                ProviderIssue.ClaudeNotLoggedIn),
            ClaudeFetchOutcome.GitBashMissing => ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                ProviderIssue.ClaudeGitBashMissing),
            ClaudeFetchOutcome.TimedOut => ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                ProviderIssue.ClaudeUsageTimedOut),
            ClaudeFetchOutcome.Cancelled => ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                ProviderIssue.Cancelled),
            ClaudeFetchOutcome.CommandFailed => ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                ProviderIssue.ClaudeCommandFailed),
            _ => ProviderUsage.Unavailable(
                ProviderNames.ClaudeCode,
                ProviderIssue.ClaudeUsageUnreadable)
        };
    }

    /// <summary>
    /// True when Claude's own output complains about Git Bash. UsageBar never
    /// infers this from Git for Windows being absent — the quota query does not
    /// need it.
    /// </summary>
    internal static bool MentionsGitBash(ReadOnlySpan<byte> standardError, string standardOutput)
    {
        var combined = (Encoding.UTF8.GetString(standardError) + "\n" + standardOutput).ToLowerInvariant();
        if (!GitBashSignals.Any(signal => combined.Contains(signal, StringComparison.Ordinal)))
        {
            return false;
        }

        // The mention has to be a complaint, not an incidental reference.
        return combined.Contains("not found", StringComparison.Ordinal) ||
               combined.Contains("could not find", StringComparison.Ordinal) ||
               combined.Contains("couldn't find", StringComparison.Ordinal) ||
               combined.Contains("unable to find", StringComparison.Ordinal) ||
               combined.Contains("no such file", StringComparison.Ordinal) ||
               combined.Contains("is required", StringComparison.Ordinal);
    }
}
