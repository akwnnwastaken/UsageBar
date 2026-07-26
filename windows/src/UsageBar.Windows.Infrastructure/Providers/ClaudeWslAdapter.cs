using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Infrastructure.Wsl;

namespace UsageBar.Windows.Infrastructure.Providers;

/// <summary>Why the WSL adapter cannot run, when it cannot.</summary>
public enum WslAvailability
{
    Unknown,

    /// <summary>A distribution with a working Claude Code was found.</summary>
    Ready,

    /// <summary>wsl.exe is absent or unusable.</summary>
    WslUnavailable,

    /// <summary>WSL works but no distribution is installed.</summary>
    NoDistributions,

    /// <summary>Distributions exist, but none has a usable Claude Code.</summary>
    ClaudeMissing
}

/// <summary>
/// Runs the quota query inside a WSL distribution.
///
/// Resolution is deliberately not repeated on every refresh: the working
/// distribution and the form that reached Claude inside it are cached, and only
/// a failure that suggests the installation moved invalidates them. A refresh
/// therefore starts one wsl.exe, not one per distribution.
///
/// Claude is addressed relative to the Linux home (<c>--cd ~</c>), so UsageBar
/// never learns or stores a Linux home path, and the run never starts in a
/// Windows project directory.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class ClaudeWslAdapter : IClaudeAdapter
{
    /// <summary>
    /// How Claude is reached inside a distribution. Both forms are non-shell:
    /// the first is the Linux native installer's location addressed relative to
    /// the home directory, the second is a package-manager install already on
    /// the distribution's default PATH.
    /// </summary>
    internal static IReadOnlyList<ClaudeInvocation> Invocations { get; } = new[]
    {
        new ClaudeInvocation(".local/bin/claude", UseHomeDirectory: true),
        new ClaudeInvocation("claude", UseHomeDirectory: false)
    };

    internal readonly record struct ClaudeInvocation(string Command, bool UseHomeDirectory);

    private readonly WslCommandRunner _runner;
    private readonly string? _configuredDistribution;
    private readonly SemaphoreSlim _resolutionGate = new(1, 1);

    private Resolution? _resolved;

    public ClaudeWslAdapter(WslCommandRunner? runner = null, string? configuredDistribution = null)
    {
        _runner = runner ?? new WslCommandRunner();
        _configuredDistribution = string.IsNullOrWhiteSpace(configuredDistribution)
            ? null
            : configuredDistribution;
    }

    public ProviderAdapterKind Kind => ProviderAdapterKind.Wsl;

    public WslAvailability Availability { get; private set; } = WslAvailability.Unknown;

    /// <summary>The distribution in use. Only a name, never a path inside it.</summary>
    public string? ResolvedDistribution => _resolved?.Distribution;

    public async Task<bool> IsAvailableAsync(CancellationToken cancellationToken) =>
        await ResolveAsync(cancellationToken).ConfigureAwait(false) is not null;

    public async Task<ClaudeAdapterResult> RunUsageQueryAsync(CancellationToken cancellationToken)
    {
        var resolution = await ResolveAsync(cancellationToken).ConfigureAwait(false);
        if (resolution is null)
        {
            return new ClaudeAdapterResult
            {
                StandardOutput = Array.Empty<byte>(),
                StandardError = Array.Empty<byte>(),
                LaunchFailure = $"wsl unavailable ({Availability})",
                AdapterKind = ProviderAdapterKind.Wsl
            };
        }

        var command = new List<string> { resolution.Invocation.Command };
        command.AddRange(ClaudeQuery.Arguments);

        var result = await _runner.RunAsync(
            resolution.Distribution,
            resolution.Invocation.UseHomeDirectory,
            command,
            ClaudeQuery.DefaultTimeout,
            cancellationToken).ConfigureAwait(false);

        // A launch failure or a non-zero exit with no output suggests the
        // installation moved or the distribution is gone; rediscover next time.
        if (!result.Launched || (result.ExitCode != 0 && result.StandardOutput.Length == 0 && !result.Cancelled))
        {
            InvalidateCache();
        }

        return new ClaudeAdapterResult
        {
            StandardOutput = result.StandardOutput,
            StandardError = result.StandardError,
            OutputExceeded = result.OutputExceeded,
            TimedOut = result.TimedOut,
            Cancelled = result.Cancelled,
            ExitCode = result.ExitCode,
            LaunchFailure = result.LaunchFailure,
            AdapterKind = ProviderAdapterKind.Wsl
        };
    }

    public void InvalidateCache() => _resolved = null;

    private sealed record Resolution(string? Distribution, ClaudeInvocation Invocation);

    /// <summary>
    /// Finds a distribution that can run Claude, once, and remembers it.
    ///
    /// The configured distribution is tried first and on its own — a user who
    /// chose one does not want every other distribution started behind their
    /// back. Only in automatic mode are the remaining distributions probed, and
    /// each probe is a bounded <c>--version</c> call rather than a session.
    /// </summary>
    private async Task<Resolution?> ResolveAsync(CancellationToken cancellationToken)
    {
        if (_resolved is { } cached)
        {
            return cached;
        }

        await _resolutionGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_resolved is { } raced)
            {
                return raced;
            }

            if (!_runner.IsInstalled)
            {
                Availability = WslAvailability.WslUnavailable;
                return null;
            }

            var distributions = await _runner.ListDistributionsAsync(cancellationToken).ConfigureAwait(false);
            if (distributions.Count == 0)
            {
                Availability = WslAvailability.NoDistributions;
                return null;
            }

            var ordered = _configuredDistribution is { } configured
                ? distributions.Where(name =>
                    string.Equals(name, configured, StringComparison.OrdinalIgnoreCase)).ToList()
                : distributions.ToList();

            if (ordered.Count == 0)
            {
                // The configured distribution is gone.
                Availability = WslAvailability.NoDistributions;
                return null;
            }

            foreach (var distribution in ordered)
            {
                foreach (var invocation in Invocations)
                {
                    cancellationToken.ThrowIfCancellationRequested();

                    var probe = await _runner.RunAsync(
                        distribution,
                        invocation.UseHomeDirectory,
                        new[] { invocation.Command, ClaudeQuery.VersionArguments[0] },
                        ClaudeQuery.ProbeTimeout,
                        cancellationToken).ConfigureAwait(false);

                    if (probe.Launched && !probe.TimedOut && !probe.Cancelled && probe.ExitCode == 0)
                    {
                        Availability = WslAvailability.Ready;
                        _resolved = new Resolution(distribution, invocation);
                        return _resolved;
                    }
                }
            }

            Availability = WslAvailability.ClaudeMissing;
            return null;
        }
        catch (OperationCanceledException)
        {
            return null;
        }
        finally
        {
            _resolutionGate.Release();
        }
    }
}
