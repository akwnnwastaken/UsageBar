namespace UsageBar.Windows.Core.Diagnostics;

/// <summary>
/// Which known-folder sources answered for a folder, and whether they agreed.
///
/// Physical testing left two explanations standing for a Setup-launched session
/// that cannot see Codex: Local AppData resolves to a wrong-but-existing
/// directory, or it resolves correctly and the file is not visible. Collapsing
/// the two sources into one answer hides which of them is responsible.
/// </summary>
public enum FolderSourceRelation
{
    /// <summary>Neither the shell nor the framework produced a usable root.</summary>
    None,
    ShellOnly,
    FrameworkOnly,

    /// <summary>Both answered and named the same folder.</summary>
    Agree,

    /// <summary>Both answered and named different folders.</summary>
    Differ
}

/// <summary>How many distinct roots a folder resolved to, after de-duplication.</summary>
public enum FolderRootCount
{
    None,
    One,
    Multiple
}

/// <summary>
/// Where the resolved roots sit relative to the resolved user profile.
///
/// This alone cannot decide anything: both folders can resolve consistently into
/// the same wrong profile, which reads as <see cref="AllUnderProfile"/> while
/// still being wrong. It is reported next to the probes, never instead of them.
/// </summary>
public enum FolderProfileRelation
{
    AllUnderProfile,
    SomeOutsideProfile,
    NoneUnderProfile,

    /// <summary>One of the two folders resolved to nothing, so there is no relation.</summary>
    NotComparable
}

/// <summary>
/// The outcome of one bounded metadata probe of a documented candidate path.
///
/// A probe explains a discovery result. It never contributes to one:
/// <c>ExecutableTrust</c> remains the only thing that may accept an executable.
/// </summary>
public enum CandidateProbeState
{
    Exists,
    NotFound,
    AccessDenied,
    IoError,

    /// <summary>The source answered, but the answer was not a usable root.</summary>
    InvalidRoot,

    /// <summary>The source returned nothing, so no candidate path existed to probe.</summary>
    NotConstructed,

    /// <summary>Reported by the shell field when both sources named one folder.</summary>
    SameAsFramework,

    /// <summary>Reported by the framework field when both sources named one folder.</summary>
    SameAsShell
}

/// <summary>Where a Codex lookup ended. Never which path it ended at.</summary>
public enum CodexLookupStage
{
    /// <summary>The documented native installer location under Local AppData.</summary>
    OfficialNative,

    /// <summary>Any other documented native location, including a user-selected one.</summary>
    OtherNative,

    Node,
    Untrusted,
    Unsupported,
    Missing
}

/// <summary>
/// An immutable, privacy-safe account of one Codex lookup.
///
/// It is produced by the lookup itself and carried beside its result, so a
/// diagnostic summary describes the operation that actually ran rather than a
/// second, later one. That matters here specifically: the context under
/// investigation is a process launched by Setup, and re-resolving folders when
/// the summary is built could describe a different context than the one that
/// failed.
///
/// Every field is a fixed classification. No path, root, user name, Win32
/// message or exception text is retained at any point.
/// </summary>
public sealed record CodexDiscoveryTrace(
    FolderResolutionState LocalAppDataState,
    FolderResolutionState UserProfileState,
    FolderSourceRelation LocalAppDataSourceRelation,
    FolderRootCount LocalAppDataRootCount,
    FolderProfileRelation LocalAppDataProfileRelation,
    CandidateProbeState OfficialCodexShellProbe,
    CandidateProbeState OfficialCodexFrameworkProbe,
    CandidateProbeState OfficialCodexProfileDerivedProbe,
    CodexLookupStage TerminalStage)
{
    /// <summary>
    /// No lookup has run yet. A report carrying this also carries
    /// <c>last_refresh=never</c>, so the two are read together.
    /// </summary>
    public static CodexDiscoveryTrace NotRun { get; } = new(
        FolderResolutionState.Empty,
        FolderResolutionState.Empty,
        FolderSourceRelation.None,
        FolderRootCount.None,
        FolderProfileRelation.NotComparable,
        CandidateProbeState.NotConstructed,
        CandidateProbeState.NotConstructed,
        CandidateProbeState.NotConstructed,
        CodexLookupStage.Missing);

    /// <summary>
    /// The coarse candidate state, derived from the probes rather than measured
    /// separately, so the two can never disagree. The meaning is unchanged from
    /// the field the first physical comparison already used: "not_constructed"
    /// is no root at all, "missing" is a root with no Codex under it.
    /// </summary>
    public CandidateState OfficialCodexCandidateState
    {
        get
        {
            if (LocalAppDataState == FolderResolutionState.Empty)
            {
                return CandidateState.NotConstructed;
            }

            return OfficialCodexShellProbe == CandidateProbeState.Exists ||
                   OfficialCodexFrameworkProbe == CandidateProbeState.Exists
                ? CandidateState.Exists
                : CandidateState.Missing;
        }
    }
}
