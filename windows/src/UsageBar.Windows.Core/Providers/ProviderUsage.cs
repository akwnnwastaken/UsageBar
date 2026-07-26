namespace UsageBar.Windows.Core.Providers;

/// <summary>
/// One provider's quota state: every window it returned (lossless), an optional
/// structured error, and the timestamp of the last successful read used for the
/// stale presentation.
/// </summary>
public sealed record ProviderUsage
{
    public ProviderUsage(
        string name,
        IReadOnlyList<UsageWindow> windows,
        ProviderIssue? error,
        DateTimeOffset? lastSuccessfulAt = null)
    {
        Name = name;
        Windows = windows;
        Error = error;
        LastSuccessfulAt = lastSuccessfulAt;
    }

    public string Name { get; }

    public IReadOnlyList<UsageWindow> Windows { get; }

    public ProviderIssue? Error { get; }

    public DateTimeOffset? LastSuccessfulAt { get; }

    public UsageWindow? Session =>
        Windows.FirstOrDefault(window => window.Kind == UsageWindowKind.FiveHour);

    public UsageWindow? Weekly =>
        Windows.FirstOrDefault(window => window.Kind == UsageWindowKind.Weekly);

    /// <summary>
    /// A failed refresh that still has a previous good reading. The panel keeps
    /// showing the value with a stale warning instead of blanking out.
    /// </summary>
    public bool IsStale => Error is not null && Windows.Count > 0 && LastSuccessfulAt is not null;

    public static ProviderUsage Unavailable(string name, ProviderIssue issue) =>
        new(name, Array.Empty<UsageWindow>(), issue);

    public ProviderUsage ReplacingWindows(IReadOnlyList<UsageWindow> replacements) =>
        new(Name, replacements, Error, LastSuccessfulAt);

    public ProviderUsage MarkedSuccessful(DateTimeOffset at) =>
        new(Name, Windows, error: null, lastSuccessfulAt: at);

    public static ProviderUsage Stale(ProviderUsage previous, ProviderIssue issue) =>
        new(previous.Name, previous.Windows, issue, previous.LastSuccessfulAt);
}

/// <summary>
/// The pure state transition applied to a freshly fetched provider reading. A
/// failure never discards a previous good value: it becomes stale data instead.
/// </summary>
public static class ProviderUsageTransition
{
    public static ProviderUsage Accept(ProviderUsage? previous, ProviderUsage fetched, DateTimeOffset at)
    {
        ArgumentNullException.ThrowIfNull(fetched);

        if (fetched.Error is null && fetched.Windows.Count > 0)
        {
            return fetched.MarkedSuccessful(at);
        }

        if (fetched.Error is { } issue &&
            previous is { Windows.Count: > 0, LastSuccessfulAt: not null })
        {
            return ProviderUsage.Stale(previous, issue);
        }

        return fetched;
    }
}
