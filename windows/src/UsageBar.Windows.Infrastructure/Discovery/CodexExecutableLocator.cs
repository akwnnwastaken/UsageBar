using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Discovery;

/// <summary>
/// One lookup's result together with the privacy-safe account of how it got
/// there. The two are produced by the same operation and travel together, so a
/// diagnostic summary can never describe a different resolution than the one
/// that produced the reported executable state.
/// </summary>
public readonly record struct CodexDiscovery(ExecutableLookup Lookup, CodexDiscoveryTrace Trace);

/// <summary>
/// Finds a trusted Codex installation.
///
/// Only documented candidate locations are searched, each pinned to the
/// installation root it must live under. The user's PATH is never used to pick a
/// winner and the current working directory is never consulted, so a project
/// that ships its own <c>codex.exe</c> cannot hijack a quota check.
///
/// Supported installation formats:
/// <list type="bullet">
/// <item>native per-user install (<c>%LOCALAPPDATA%\Programs\codex</c>)</item>
/// <item>native machine install (<c>%ProgramFiles%\codex</c>)</item>
/// <item>ChatGPT desktop's bundled Codex</item>
/// <item>WinGet link, Scoop shim and Cargo bin, when they are real executables</item>
/// <item>npm global install, started through a validated <c>node.exe</c></item>
/// <item>an explicit user-selected executable</item>
/// </list>
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class CodexExecutableLocator
{
    private readonly IKnownFolderResolver _folders;

    public CodexExecutableLocator()
        : this(new WindowsKnownFolderResolver())
    {
    }

    /// <summary>
    /// Candidate roots come from the resolver, which asks the shell before the
    /// framework. A context where one of those sources returns nothing no longer
    /// silently removes the official Codex candidate.
    /// </summary>
    public CodexExecutableLocator(IKnownFolderResolver folders) => _folders = folders;

    internal CodexExecutableLocator(
        Func<Environment.SpecialFolder, string> specialFolder,
        Func<string, string?> environmentVariable)
        : this(LegacyResolver.From(specialFolder, environmentVariable))
    {
    }

    /// <summary>
    /// The documented native Codex path, and whether it could even be built.
    /// Reported in diagnostics so a machine where Local AppData does not resolve
    /// is distinguishable from one where Codex is genuinely not installed.
    ///
    /// Callers that already hold a <see cref="CodexDiscovery"/> should read
    /// <see cref="CodexDiscoveryTrace.OfficialCodexCandidateState"/> from it
    /// instead: this method resolves afresh, which is right for a caller that
    /// has no lookup to describe and wrong for one that does.
    /// </summary>
    public CandidateState OfficialCandidateState() =>
        BuildTrace(TakeSnapshot(), CodexLookupStage.Missing).OfficialCodexCandidateState;

    public ExecutableLookup Locate(string? userSelectedPath = null) =>
        LocateWithTrace(userSelectedPath).Lookup;

    /// <summary>
    /// The lookup, plus the account of the folders it was built from and where
    /// it ended. Folders are resolved exactly once here and every candidate is
    /// built from that one snapshot, so the trace and the result cannot disagree.
    /// </summary>
    public CodexDiscovery LocateWithTrace(string? userSelectedPath = null)
    {
        var folders = TakeSnapshot();
        var (lookup, stage) = Search(folders, userSelectedPath);

        return new CodexDiscovery(lookup, BuildTrace(folders, stage));
    }

    private (ExecutableLookup Lookup, CodexLookupStage Stage) Search(
        FolderSnapshot folders,
        string? userSelectedPath)
    {
        var rejected = false;

        // An explicit user choice is honored first, but validated identically.
        if (!string.IsNullOrWhiteSpace(userSelectedPath))
        {
            var directory = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(userSelectedPath));
            if (directory is not null)
            {
                var result = ExecutableTrust.Validate(userSelectedPath, directory);
                if (result is not null)
                {
                    return (result, StageFor(result, CodexLookupStage.OtherNative));
                }
            }
        }

        foreach (var candidate in NativeCandidates(folders))
        {
            var result = ExecutableTrust.Validate(candidate.Path, candidate.Root);
            if (result is null)
            {
                continue;
            }

            if (result.Status == ExecutableLookupStatus.Found)
            {
                return (result, candidate.IsOfficialNative
                    ? CodexLookupStage.OfficialNative
                    : CodexLookupStage.OtherNative);
            }

            rejected = true;
        }

        var nodeLauncher = LocateNodeLauncher(folders);
        if (nodeLauncher is not null)
        {
            if (nodeLauncher.Status == ExecutableLookupStatus.Found)
            {
                return (nodeLauncher, CodexLookupStage.Node);
            }

            // The reported status is unchanged: a rejected npm installation has
            // always come out of Locate as untrusted. The stage still records
            // what actually happened at that step, which is the point of it.
            return (ExecutableLookup.Untrusted, StageFor(nodeLauncher, CodexLookupStage.Node));
        }

        return rejected
            ? (ExecutableLookup.Untrusted, CodexLookupStage.Untrusted)
            : (ExecutableLookup.Missing, CodexLookupStage.Missing);
    }

    private static CodexLookupStage StageFor(ExecutableLookup lookup, CodexLookupStage whenFound) =>
        lookup.Status switch
        {
            ExecutableLookupStatus.Found => whenFound,
            ExecutableLookupStatus.Untrusted => CodexLookupStage.Untrusted,
            ExecutableLookupStatus.UnsupportedInstallation => CodexLookupStage.Unsupported,
            _ => CodexLookupStage.Missing
        };

    // MARK: - Folder snapshot

    /// <summary>
    /// Every folder a lookup builds candidates from, resolved once. Resolving
    /// per candidate list would let two steps of the same lookup see different
    /// roots, and would let the trace describe roots the search never used.
    /// </summary>
    internal sealed record FolderSnapshot(
        KnownFolderSources LocalAppData,
        KnownFolderSources UserProfile,
        KnownFolderSources ProgramFiles,
        KnownFolderSources RoamingAppData);

    internal FolderSnapshot TakeSnapshot() => new(
        _folders.ResolveSources(WindowsKnownFolder.LocalApplicationData),
        _folders.ResolveSources(WindowsKnownFolder.UserProfile),
        _folders.ResolveSources(WindowsKnownFolder.ProgramFiles),
        _folders.ResolveSources(WindowsKnownFolder.RoamingApplicationData));

    // MARK: - Candidates

    internal readonly record struct Candidate(string Path, string Root, bool IsOfficialNative = false);

    internal IEnumerable<Candidate> NativeCandidates() => NativeCandidates(TakeSnapshot());

    internal static IEnumerable<Candidate> NativeCandidates(FolderSnapshot folders)
    {
        // Every resolved root is tried, so one source returning nothing cannot
        // remove a candidate the other source can still build.
        foreach (var localAppData in folders.LocalAppData.Roots)
        {
            var programs = System.IO.Path.Combine(localAppData, "Programs");

            // The official native Windows installer, found during physical
            // testing against codex-cli 0.145.0. It nests the executable under
            // a vendor folder and a `bin` directory, so neither the path nor
            // the trusted root matches the flatter layouts below.
            yield return new Candidate(
                OfficialCandidateIn(localAppData),
                System.IO.Path.Combine(programs, "OpenAI", "Codex"),
                IsOfficialNative: true);

            yield return new Candidate(
                System.IO.Path.Combine(programs, "codex", "codex.exe"),
                System.IO.Path.Combine(programs, "codex"));

            // The Windows equivalent of the macOS ChatGPT.app bundled Codex.
            yield return new Candidate(
                System.IO.Path.Combine(programs, "ChatGPT", "resources", "codex.exe"),
                System.IO.Path.Combine(programs, "ChatGPT"));

            var winGetLinks = System.IO.Path.Combine(localAppData, "Microsoft", "WinGet", "Links");
            yield return new Candidate(
                System.IO.Path.Combine(winGetLinks, "codex.exe"),
                System.IO.Path.Combine(localAppData, "Microsoft", "WinGet"));
        }

        foreach (var programFiles in folders.ProgramFiles.Roots)
        {
            yield return new Candidate(
                System.IO.Path.Combine(programFiles, "codex", "codex.exe"),
                System.IO.Path.Combine(programFiles, "codex"));
        }

        foreach (var userProfile in folders.UserProfile.Roots)
        {
            yield return new Candidate(
                System.IO.Path.Combine(userProfile, ".cargo", "bin", "codex.exe"),
                System.IO.Path.Combine(userProfile, ".cargo"));
            yield return new Candidate(
                System.IO.Path.Combine(userProfile, "scoop", "shims", "codex.exe"),
                System.IO.Path.Combine(userProfile, "scoop"));
        }
    }

    /// <summary>The documented native installer layout, under a Local AppData root.</summary>
    private static string OfficialCandidateIn(string localAppData) => System.IO.Path.Combine(
        localAppData, "Programs", "OpenAI", "Codex", "bin", "codex.exe");

    /// <summary>
    /// npm installs Codex as a JavaScript entry point plus a <c>.cmd</c> shim.
    /// The shim is never run — that would mean invoking cmd.exe. Instead the
    /// script and a real <c>node.exe</c> are validated separately and Node is
    /// started directly with the script as its first argument.
    /// </summary>
    internal ExecutableLookup? LocateNodeLauncher() => LocateNodeLauncher(TakeSnapshot());

    internal static ExecutableLookup? LocateNodeLauncher(FolderSnapshot folders)
    {
        string? npmRoot = null;
        string? script = null;

        // Every resolved root is tried, as with the native candidates: one
        // source returning nothing must not remove an installation the other
        // source can still reach.
        foreach (var appData in folders.RoamingAppData.Roots)
        {
            var root = System.IO.Path.Combine(appData, "npm");
            var candidate = System.IO.Path.Combine(
                root, "node_modules", "@openai", "codex", "bin", "codex.js");

            if (File.Exists(candidate))
            {
                npmRoot = root;
                script = candidate;
                break;
            }
        }

        if (script is null || npmRoot is null)
        {
            return null;
        }

        if (!ExecutableTrust.IsTrustedScript(script, npmRoot))
        {
            return ExecutableLookup.Untrusted;
        }

        var node = LocateNode(folders);
        if (node is null)
        {
            // The installation exists but cannot be started without a shell.
            return ExecutableLookup.UnsupportedInstallation;
        }

        if (node.Status != ExecutableLookupStatus.Found || node.Executable is null)
        {
            return node;
        }

        return ExecutableLookup.Found(new ResolvedExecutable(
            node.Executable.Path,
            new[] { System.IO.Path.GetFullPath(script) },
            ProviderAdapterKind.NodeLauncher));
    }

    internal ExecutableLookup? LocateNode() => LocateNode(TakeSnapshot());

    internal static ExecutableLookup? LocateNode(FolderSnapshot folders)
    {
        var candidates = new List<Candidate>();
        foreach (var programFiles in folders.ProgramFiles.Roots)
        {
            candidates.Add(new Candidate(
                System.IO.Path.Combine(programFiles, "nodejs", "node.exe"),
                System.IO.Path.Combine(programFiles, "nodejs")));
        }

        foreach (var localAppData in folders.LocalAppData.Roots)
        {
            candidates.Add(new Candidate(
                System.IO.Path.Combine(localAppData, "Programs", "nodejs", "node.exe"),
                System.IO.Path.Combine(localAppData, "Programs", "nodejs")));
        }

        ExecutableLookup? rejected = null;
        foreach (var candidate in candidates)
        {
            var result = ExecutableTrust.Validate(
                candidate.Path,
                candidate.Root,
                ProviderAdapterKind.NodeLauncher);
            if (result is null)
            {
                continue;
            }

            if (result.Status == ExecutableLookupStatus.Found)
            {
                return result;
            }

            rejected = result;
        }

        return rejected;
    }

    // MARK: - The trace

    /// <summary>
    /// Describes the snapshot the search just ran against. Every value is a
    /// fixed classification; no root, path or user name is retained.
    /// </summary>
    private static CodexDiscoveryTrace BuildTrace(FolderSnapshot folders, CodexLookupStage stage)
    {
        var localAppData = folders.LocalAppData;

        var shellProbe = ProbeOfficial(localAppData.Shell);
        var frameworkProbe = localAppData.Relation == FolderSourceRelation.Agree
            // One folder, one probe. The result is reported on the shell field,
            // which is the source asked first.
            ? CandidateProbeState.SameAsShell
            : ProbeOfficial(localAppData.Framework);

        return new CodexDiscoveryTrace(
            localAppData.State,
            folders.UserProfile.State,
            localAppData.Relation,
            localAppData.Count,
            ProfileRelation(localAppData.Roots, folders.UserProfile.Roots),
            shellProbe,
            frameworkProbe,
            ProbeProfileDerived(folders.UserProfile.Roots),
            stage);
    }

    private static CandidateProbeState ProbeOfficial(KnownFolderSourceResult source)
    {
        if (!source.Answered)
        {
            return CandidateProbeState.NotConstructed;
        }

        return source.Root is { } root
            ? CandidateProbe.Probe(OfficialCandidateIn(root))
            : CandidateProbeState.InvalidRoot;
    }

    /// <summary>
    /// The same documented layout, reached through the user profile instead of
    /// through Local AppData.
    ///
    /// This is the field that separates the two surviving explanations. If Local
    /// AppData resolves to a wrong-but-existing directory, this probe still finds
    /// Codex; if the folder resolves correctly and the file is genuinely not
    /// visible, this probe misses it too. Both folders resolving consistently
    /// into the same wrong profile is likewise visible, because then neither
    /// finds anything.
    ///
    /// It is diagnostic only and is never offered as a discovery candidate.
    /// </summary>
    private static CandidateProbeState ProbeProfileDerived(IReadOnlyList<string> profileRoots)
    {
        if (profileRoots.Count == 0)
        {
            return CandidateProbeState.NotConstructed;
        }

        var state = CandidateProbeState.NotFound;
        foreach (var profile in profileRoots)
        {
            state = CandidateProbe.Merge(
                state,
                CandidateProbe.Probe(OfficialCandidateIn(
                    System.IO.Path.Combine(profile, "AppData", "Local"))));
        }

        return state;
    }

    private static FolderProfileRelation ProfileRelation(
        IReadOnlyList<string> roots,
        IReadOnlyList<string> profiles)
    {
        if (roots.Count == 0 || profiles.Count == 0)
        {
            return FolderProfileRelation.NotComparable;
        }

        var under = roots.Count(root => profiles.Any(profile => IsUnder(root, profile)));

        if (under == roots.Count)
        {
            return FolderProfileRelation.AllUnderProfile;
        }

        return under == 0
            ? FolderProfileRelation.NoneUnderProfile
            : FolderProfileRelation.SomeOutsideProfile;
    }

    private static bool IsUnder(string path, string root)
    {
        var trimmed = root.TrimEnd(
            System.IO.Path.DirectorySeparatorChar,
            System.IO.Path.AltDirectorySeparatorChar);

        return path.Equals(trimmed, StringComparison.OrdinalIgnoreCase) ||
               path.StartsWith(
                   trimmed + System.IO.Path.DirectorySeparatorChar,
                   StringComparison.OrdinalIgnoreCase);
    }
}
