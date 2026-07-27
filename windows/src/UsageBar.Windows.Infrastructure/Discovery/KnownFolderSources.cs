using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Discovery;

/// <summary>
/// What one known-folder source returned, before de-duplication.
///
/// "Answered nothing" and "answered something unusable" are different faults and
/// are kept apart: a source that returns an empty string never had an opinion,
/// while a source that names a folder which is not there is actively wrong.
/// Discovery treats both as no root; only diagnostics can tell them apart.
/// </summary>
public readonly record struct KnownFolderSourceResult(bool Answered, string? Root)
{
    /// <summary>The source returned nothing, or failed.</summary>
    public static KnownFolderSourceResult Silent { get; } = new(false, null);

    /// <summary>The source answered, but the answer was not a usable root.</summary>
    public static KnownFolderSourceResult Rejected { get; } = new(true, null);

    public static KnownFolderSourceResult Accepted(string root) => new(true, root);
}

/// <summary>
/// One folder's resolution with the source identities preserved alongside the
/// de-duplicated roots discovery actually uses.
/// </summary>
public sealed record KnownFolderSources(
    KnownFolderSourceResult Shell,
    KnownFolderSourceResult Framework,
    IReadOnlyList<string> Roots)
{
    public static KnownFolderSources Empty { get; } = new(
        KnownFolderSourceResult.Silent,
        KnownFolderSourceResult.Silent,
        Array.Empty<string>());

    /// <summary>
    /// Adapts a resolver that only knows roots. <see cref="IKnownFolderResolver"/>
    /// returns them best-source-first, so the first is attributed to the shell
    /// and a second to the framework.
    /// </summary>
    public static KnownFolderSources FromRoots(IReadOnlyList<string> roots) => new(
        roots.Count > 0 ? KnownFolderSourceResult.Accepted(roots[0]) : KnownFolderSourceResult.Silent,
        roots.Count > 1 ? KnownFolderSourceResult.Accepted(roots[1]) : KnownFolderSourceResult.Silent,
        roots);

    public FolderSourceRelation Relation
    {
        get
        {
            if (Shell.Root is not { } shell)
            {
                return Framework.Root is null
                    ? FolderSourceRelation.None
                    : FolderSourceRelation.FrameworkOnly;
            }

            if (Framework.Root is not { } framework)
            {
                return FolderSourceRelation.ShellOnly;
            }

            return string.Equals(shell, framework, StringComparison.OrdinalIgnoreCase)
                ? FolderSourceRelation.Agree
                : FolderSourceRelation.Differ;
        }
    }

    public FolderRootCount Count => Roots.Count switch
    {
        0 => FolderRootCount.None,
        1 => FolderRootCount.One,
        _ => FolderRootCount.Multiple
    };

    public FolderResolutionState State =>
        Roots.Count > 0 ? FolderResolutionState.Available : FolderResolutionState.Empty;
}
