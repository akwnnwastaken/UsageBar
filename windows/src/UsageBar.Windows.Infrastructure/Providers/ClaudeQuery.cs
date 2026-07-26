using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Providers;

/// <summary>
/// The Claude Code quota query, shared by every adapter.
///
/// This is the same non-interactive print-mode query the macOS build uses:
/// <c>/usage</c> is a local slash command, so it costs no model quota, and
/// <c>--no-session-persistence</c> means the run registers no session and
/// leaves no transcript. The isolation flags keep project settings, hooks,
/// Chrome, MCP servers and tools out of a quota check while leaving the user's
/// existing local login available.
/// </summary>
public static class ClaudeQuery
{
    public static IReadOnlyList<string> Arguments { get; } = new[]
    {
        "-p", "/usage",
        "--no-session-persistence",
        "--setting-sources", "",
        "--no-chrome",
        "--strict-mcp-config",
        "--tools", ""
    };

    /// <summary>A cheap, bounded liveness check used when probing an installation.</summary>
    public static IReadOnlyList<string> VersionArguments { get; } = new[] { "--version" };

    public static TimeSpan DefaultTimeout { get; } = TimeSpan.FromSeconds(20);

    /// <summary>Probing must be quick: several distributions may be tried.</summary>
    public static TimeSpan ProbeTimeout { get; } = TimeSpan.FromSeconds(15);
}

/// <summary>What an adapter produced when asked to run the query.</summary>
public sealed record ClaudeAdapterResult
{
    public required byte[] StandardOutput { get; init; }

    public required byte[] StandardError { get; init; }

    public bool OutputExceeded { get; init; }

    public bool TimedOut { get; init; }

    public bool Cancelled { get; init; }

    public int ExitCode { get; init; }

    public string? LaunchFailure { get; init; }

    public required ProviderAdapterKind AdapterKind { get; init; }

    public bool Launched => LaunchFailure is null;
}

/// <summary>
/// One way of reaching Claude Code on this machine. Implementations own only
/// discovery and invocation; interpreting the output is the reader's job.
/// </summary>
public interface IClaudeAdapter
{
    ProviderAdapterKind Kind { get; }

    /// <summary>
    /// Whether this adapter can run right now. Implementations cache what is
    /// expensive to determine rather than probing on every refresh.
    /// </summary>
    Task<bool> IsAvailableAsync(CancellationToken cancellationToken);

    Task<ClaudeAdapterResult> RunUsageQueryAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Called after a run that failed in a way that suggests the cached
    /// resolution is stale, so the next attempt rediscovers.
    /// </summary>
    void InvalidateCache();
}
