using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Infrastructure.Discovery;
using UsageBar.Windows.Infrastructure.Process;

namespace UsageBar.Windows.Infrastructure.Providers;

/// <summary>
/// Runs the quota query against a native Windows Claude Code installation.
///
/// The executable is started directly through the same Job Object launcher
/// Codex uses: no cmd.exe, no PowerShell, no Git Bash, no shell of any kind, and
/// no <c>Process.Start</c> fallback. A <c>.cmd</c>-only installation is reported
/// as unsupported rather than run through an interpreter.
///
/// Git for Windows is not required. Claude Code documents it as optional — it
/// enables Claude's own Bash tool — and this query disables tools outright. When
/// a trusted <c>bash.exe</c> does exist its path is passed through in
/// <c>CLAUDE_CODE_GIT_BASH_PATH</c>, the variable Claude documents, so a build
/// that looks for it at startup finds it. UsageBar never launches it.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class ClaudeNativeWindowsAdapter : IClaudeAdapter
{
    private readonly ClaudeExecutableLocator _locator;
    private readonly GitBashLocator _gitBash;
    private readonly string? _userSelectedPath;
    private readonly object _gate = new();

    private ExecutableLookup? _cachedLookup;
    private string? _cachedGitBashPath;

    public ClaudeNativeWindowsAdapter(
        ClaudeExecutableLocator? locator = null,
        GitBashLocator? gitBash = null,
        string? userSelectedPath = null)
    {
        _locator = locator ?? new ClaudeExecutableLocator();
        _gitBash = gitBash ?? new GitBashLocator();
        _userSelectedPath = userSelectedPath;
    }

    public ProviderAdapterKind Kind => Lookup().AdapterKind;

    /// <summary>The discovery verdict, for diagnostics.</summary>
    public ProviderExecutableState ExecutableState => Lookup().DiagnosticState;

    /// <summary>Whether a trusted Git for Windows bash.exe was found. Never a path.</summary>
    public bool HasGitBash => GitBashPath() is not null;

    public Task<bool> IsAvailableAsync(CancellationToken cancellationToken) =>
        Task.FromResult(Lookup().Status == ExecutableLookupStatus.Found);

    /// <summary>The discovery result, so the reader can report why it failed.</summary>
    public ExecutableLookup Lookup()
    {
        lock (_gate)
        {
            // Only a successful lookup is remembered. Caching "missing" would
            // make a provider that appears later — or a folder that resolved to
            // nothing once — stay invisible until UsageBar restarts.
            if (_cachedLookup is { Status: ExecutableLookupStatus.Found })
            {
                return _cachedLookup;
            }

            var lookup = _locator.Locate(_userSelectedPath);
            if (lookup.Status == ExecutableLookupStatus.Found)
            {
                _cachedLookup = lookup;
            }

            return lookup;
        }
    }

    public async Task<ClaudeAdapterResult> RunUsageQueryAsync(CancellationToken cancellationToken)
    {
        var lookup = Lookup();
        if (lookup is not { Status: ExecutableLookupStatus.Found, Executable: not null })
        {
            return new ClaudeAdapterResult
            {
                StandardOutput = Array.Empty<byte>(),
                StandardError = Array.Empty<byte>(),
                LaunchFailure = $"claude unavailable ({lookup.Status})",
                AdapterKind = lookup.AdapterKind
            };
        }

        var executable = lookup.Executable;
        var environment = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (GitBashPath() is { } bash)
        {
            environment[GitBashLocator.EnvironmentVariableName] = bash;
        }

        var request = new ProviderProcessRequest
        {
            ExecutablePath = executable.Path,
            Arguments = executable.BuildArguments(ClaudeQuery.Arguments),
            // Print mode emits its whole answer and exits; stdin is closed so a
            // signed-out run can never sit waiting for input.
            StandardInput = null,
            CloseStandardInputAfterWrite = true,
            Timeout = ClaudeQuery.DefaultTimeout,
            AdditionalEnvironment = environment.Count > 0 ? environment : null
        };

        var result = await ProviderProcessLauncher.RunAsync(request, cancellationToken).ConfigureAwait(false);

        return new ClaudeAdapterResult
        {
            StandardOutput = result.StandardOutput,
            StandardError = result.StandardError,
            OutputExceeded = result.OutputExceeded || result.ErrorExceeded,
            TimedOut = result.TimedOut,
            Cancelled = result.Canceled,
            ExitCode = result.ExitCode,
            LaunchFailure = result.LaunchFailure,
            AdapterKind = executable.AdapterKind
        };
    }

    public void InvalidateCache()
    {
        lock (_gate)
        {
            _cachedLookup = null;
            _cachedGitBashPath = null;
            _gitBashResolved = false;
        }
    }

    private bool _gitBashResolved;

    private string? GitBashPath()
    {
        lock (_gate)
        {
            if (!_gitBashResolved)
            {
                _cachedGitBashPath = _gitBash.Locate();
                _gitBashResolved = true;
            }

            return _cachedGitBashPath;
        }
    }
}
