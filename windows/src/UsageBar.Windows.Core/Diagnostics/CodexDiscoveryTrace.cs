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

/// <summary>
/// What a direct Win32 metadata call made of the documented candidate.
///
/// The managed probe reported <c>io_error</c> in the Setup-launched session and
/// <c>exists</c> from the Start Menu on the same file, which says only that
/// something below the framework failed. .NET folds sharing violations, lock
/// violations, reparse faults and cloud-provider faults into one
/// <c>IOException</c>, and <c>File.Exists</c> then folds that into <c>false</c>.
/// These states keep them apart.
/// </summary>
public enum NativeProbeState
{
    Exists,
    FileNotFound,
    PathNotFound,
    AccessDenied,
    SharingViolation,
    LockViolation,
    CantAccessFile,
    ReparseError,
    CloudUnavailable,
    DeviceError,
    OtherError,
    NotConstructed
}

/// <summary>
/// Whether a metadata-only handle could be opened on the candidate.
///
/// Separates a namespace or attribute failure from a handle-access failure: the
/// attribute query and the open take different paths through the filter stack,
/// so one succeeding while the other fails is itself the answer.
/// </summary>
public enum HandleProbeState
{
    Opened,
    NotFound,
    AccessDenied,
    SharingViolation,
    ReparseError,
    OtherError,
    NotAttempted
}

/// <summary>Whether the process token's own profile is the resolved one.</summary>
public enum TokenProfileRelation
{
    MatchesResolvedProfile,
    DiffersFromResolvedProfile,
    Unknown
}

public enum TokenIntegrity
{
    Low,
    Medium,
    High,
    System,
    Unknown
}

public enum TokenElevation
{
    Default,
    Limited,
    Full,
    Unknown
}

/// <summary>A token property that is either set, not set, or unreadable.</summary>
public enum TokenFlagState
{
    Yes,
    No,
    Unknown
}

public enum SessionRelation
{
    ActiveConsole,
    Other,
    Unknown
}

/// <summary>
/// One direct Win32 look at the documented candidate.
///
/// The numeric Win32 code is carried because it is the ground truth and contains
/// no path, identity, message, command line or credential. The state beside it is
/// a convenience bucket; where the two ever disagree, the number is what counts.
/// </summary>
public sealed record NativeProbeOutcome(
    NativeProbeState State,
    int? Win32ErrorCode,
    HandleProbeState HandleState)
{
    public static NativeProbeOutcome NotConstructed { get; } =
        new(NativeProbeState.NotConstructed, null, HandleProbeState.NotAttempted);
}

/// <summary>
/// The current process's security context, as classifications only.
///
/// A token created by Setup can differ from one created by the shell in ways that
/// change what the filesystem will answer. None of the underlying values — SIDs,
/// account names, session ids, handles or the profile path — leave this type.
/// </summary>
public sealed record ProcessTokenSnapshot(
    TokenProfileRelation ProfileRelation,
    TokenIntegrity Integrity,
    TokenElevation Elevation,
    TokenFlagState Restricted,
    TokenFlagState AppContainer,
    SessionRelation SessionRelation)
{
    public static ProcessTokenSnapshot Unknown { get; } = new(
        TokenProfileRelation.Unknown,
        TokenIntegrity.Unknown,
        TokenElevation.Unknown,
        TokenFlagState.Unknown,
        TokenFlagState.Unknown,
        SessionRelation.Unknown);
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
    CodexLookupStage TerminalStage,
    NativeProbeOutcome OfficialCodexNativeProbe,
    ProcessTokenSnapshot ProcessToken)
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
        CodexLookupStage.Missing,
        NativeProbeOutcome.NotConstructed,
        ProcessTokenSnapshot.Unknown);

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
