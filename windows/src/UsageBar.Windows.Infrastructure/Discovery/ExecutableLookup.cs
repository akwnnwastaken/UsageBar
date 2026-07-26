using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Discovery;

public enum ExecutableLookupStatus
{
    /// <summary>Nothing was found in any documented candidate location.</summary>
    Missing,

    /// <summary>Something was found but failed validation.</summary>
    Untrusted,

    /// <summary>
    /// Found, but only reachable through a shell (a bare <c>.cmd</c>/<c>.bat</c>
    /// shim with no resolvable interpreter). UsageBar refuses to run providers
    /// through a shell, so this is reported instead of silently doing it.
    /// </summary>
    UnsupportedInstallation,

    Found
}

/// <summary>
/// A validated way to start a provider: the executable to run plus any leading
/// arguments (for example the script path when the installation is a Node
/// launcher). Everything is explicit — there is no command string to interpret.
/// </summary>
public sealed record ResolvedExecutable(
    string Path,
    IReadOnlyList<string> LeadingArguments,
    ProviderAdapterKind AdapterKind)
{
    public IReadOnlyList<string> BuildArguments(IReadOnlyList<string> providerArguments) =>
        LeadingArguments.Count == 0
            ? providerArguments
            : LeadingArguments.Concat(providerArguments).ToList();
}

public sealed record ExecutableLookup(ExecutableLookupStatus Status, ResolvedExecutable? Executable)
{
    public static ExecutableLookup Missing { get; } = new(ExecutableLookupStatus.Missing, null);

    public static ExecutableLookup Untrusted { get; } = new(ExecutableLookupStatus.Untrusted, null);

    public static ExecutableLookup UnsupportedInstallation { get; } =
        new(ExecutableLookupStatus.UnsupportedInstallation, null);

    public static ExecutableLookup Found(ResolvedExecutable executable) =>
        new(ExecutableLookupStatus.Found, executable);

    public ProviderExecutableState DiagnosticState => Status switch
    {
        ExecutableLookupStatus.Found => ProviderExecutableState.Trusted,
        ExecutableLookupStatus.Untrusted => ProviderExecutableState.Untrusted,
        ExecutableLookupStatus.UnsupportedInstallation => ProviderExecutableState.UnsupportedInstallation,
        _ => ProviderExecutableState.Missing
    };

    public ProviderAdapterKind AdapterKind => Executable?.AdapterKind ?? ProviderAdapterKind.None;
}
