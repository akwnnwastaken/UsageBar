using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Infrastructure.Discovery;
using UsageBar.Windows.Infrastructure.Providers;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// The exact-operation trace behind the Codex diagnostics.
///
/// The first physical comparison ruled out the hypothesis it was built for: in a
/// Setup-launched session Local AppData resolved, the documented candidate was
/// constructed, and the file was still not found — while the same machine found
/// it a minute later from the Start Menu. Two explanations survive, and one
/// combined relation cannot separate them, because both folders can resolve
/// consistently into the same wrong profile and still read as healthy.
///
/// These tests pin what the trace has to be able to say for that distinction to
/// survive: which source produced each root, whether the sources agree, what
/// each documented candidate actually probed as, and where the lookup ended.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class CodexDiscoveryTraceTests : IDisposable
{
    private readonly string _root = Path.Combine(
        Path.GetTempPath(),
        "usagebar-trace-" + Guid.NewGuid().ToString("N"));

    public CodexDiscoveryTraceTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        try
        {
            Directory.Delete(_root, recursive: true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
        }
    }

    private string MakeDirectory(params string[] segments)
    {
        var path = Path.Combine(_root, Path.Combine(segments));
        Directory.CreateDirectory(path);
        return path;
    }

    private string MakeExecutable(params string[] segments)
    {
        var path = Path.Combine(_root, Path.Combine(segments));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "stub");
        return path;
    }

    /// <summary>The documented native installer layout, under a Local AppData root.</summary>
    private static string[] OfficialLayout(params string[] localAppData) =>
        localAppData.Concat(new[] { "Programs", "OpenAI", "Codex", "bin", "codex.exe" }).ToArray();

    /// <summary>
    /// A resolver with each source controlled per folder, so a context where one
    /// source is silent, wrong, or disagrees can be reproduced exactly.
    /// </summary>
    private static WindowsKnownFolderResolver Resolver(
        string? localShell = null,
        string? localFramework = null,
        string? profileShell = null,
        string? profileFramework = null) =>
        new(
            folder => folder switch
            {
                WindowsKnownFolder.LocalApplicationData => localShell,
                WindowsKnownFolder.UserProfile => profileShell,
                _ => null
            },
            folder => folder switch
            {
                WindowsKnownFolder.LocalApplicationData => localFramework,
                WindowsKnownFolder.UserProfile => profileFramework,
                _ => null
            });

    private static CodexDiscoveryTrace TraceOf(IKnownFolderResolver resolver) =>
        new CodexExecutableLocator(resolver).LocateWithTrace().Trace;

    // MARK: - Source identity

    /// <summary>Both sources naming one folder is probed once and said once.</summary>
    [WindowsFact]
    public void SourcesThatAgreeAreProbedOnceAndReportedOnce()
    {
        var local = MakeDirectory("Local");
        MakeExecutable(OfficialLayout("Local"));

        var trace = TraceOf(Resolver(localShell: local, localFramework: local));

        Assert.Equal(FolderSourceRelation.Agree, trace.LocalAppDataSourceRelation);
        Assert.Equal(FolderRootCount.One, trace.LocalAppDataRootCount);
        Assert.Equal(CandidateProbeState.Exists, trace.OfficialCodexShellProbe);
        Assert.Equal(CandidateProbeState.SameAsShell, trace.OfficialCodexFrameworkProbe);
        Assert.Equal(CodexLookupStage.OfficialNative, trace.TerminalStage);
    }

    /// <summary>
    /// Two sources naming different folders is the case the combined answer used
    /// to hide. Each is probed and reported separately.
    /// </summary>
    [WindowsFact]
    public void SourcesThatDifferAreReportedSeparately()
    {
        var wrong = MakeDirectory("Wrong");
        var right = MakeDirectory("Right");
        MakeExecutable(OfficialLayout("Right"));

        var trace = TraceOf(Resolver(localShell: wrong, localFramework: right));

        Assert.Equal(FolderSourceRelation.Differ, trace.LocalAppDataSourceRelation);
        Assert.Equal(FolderRootCount.Multiple, trace.LocalAppDataRootCount);
        Assert.Equal(CandidateProbeState.NotFound, trace.OfficialCodexShellProbe);
        Assert.Equal(CandidateProbeState.Exists, trace.OfficialCodexFrameworkProbe);

        // One wrong source still does not shadow the source that is right.
        Assert.Equal(CandidateState.Exists, trace.OfficialCodexCandidateState);
        Assert.Equal(CodexLookupStage.OfficialNative, trace.TerminalStage);
    }

    [WindowsFact]
    public void OnlyTheShellAnsweringIsSaidPlainly()
    {
        var local = MakeDirectory("Local");
        MakeExecutable(OfficialLayout("Local"));

        var trace = TraceOf(Resolver(localShell: local, localFramework: string.Empty));

        Assert.Equal(FolderSourceRelation.ShellOnly, trace.LocalAppDataSourceRelation);
        Assert.Equal(FolderRootCount.One, trace.LocalAppDataRootCount);
        Assert.Equal(CandidateProbeState.Exists, trace.OfficialCodexShellProbe);
        Assert.Equal(CandidateProbeState.NotConstructed, trace.OfficialCodexFrameworkProbe);
    }

    [WindowsFact]
    public void OnlyTheFrameworkAnsweringIsSaidPlainly()
    {
        var local = MakeDirectory("Local");
        MakeExecutable(OfficialLayout("Local"));

        var trace = TraceOf(Resolver(localShell: null, localFramework: local));

        Assert.Equal(FolderSourceRelation.FrameworkOnly, trace.LocalAppDataSourceRelation);
        Assert.Equal(CandidateProbeState.NotConstructed, trace.OfficialCodexShellProbe);
        Assert.Equal(CandidateProbeState.Exists, trace.OfficialCodexFrameworkProbe);
    }

    [WindowsFact]
    public void NeitherSourceAnsweringIsDistinctFromBothBeingWrong()
    {
        var silent = TraceOf(Resolver(localShell: null, localFramework: string.Empty));

        Assert.Equal(FolderSourceRelation.None, silent.LocalAppDataSourceRelation);
        Assert.Equal(FolderRootCount.None, silent.LocalAppDataRootCount);
        Assert.Equal(FolderResolutionState.Empty, silent.LocalAppDataState);
        Assert.Equal(FolderProfileRelation.NotComparable, silent.LocalAppDataProfileRelation);
        Assert.Equal(CandidateProbeState.NotConstructed, silent.OfficialCodexShellProbe);
        Assert.Equal(CandidateProbeState.NotConstructed, silent.OfficialCodexFrameworkProbe);
        Assert.Equal(CandidateState.NotConstructed, silent.OfficialCodexCandidateState);

        // A source that names a folder which is not there had an opinion and was
        // wrong. That is a different fault from having no opinion, and the two
        // must not both read as "the folder did not resolve".
        var wrong = TraceOf(Resolver(
            localShell: Path.Combine(_root, "does-not-exist"),
            localFramework: Path.Combine(_root, "also-missing")));

        Assert.Equal(FolderSourceRelation.None, wrong.LocalAppDataSourceRelation);
        Assert.Equal(CandidateProbeState.InvalidRoot, wrong.OfficialCodexShellProbe);
        Assert.Equal(CandidateProbeState.InvalidRoot, wrong.OfficialCodexFrameworkProbe);
    }

    // MARK: - The distinction the single relation could not make

    /// <summary>
    /// The case that made a lone profile relation insufficient: Local AppData and
    /// the user profile resolve consistently, to the same wrong profile. The
    /// relation reads as healthy and is worthless on its own; the probes are what
    /// expose it.
    /// </summary>
    [WindowsFact]
    public void OneWrongProfileResolvedConsistentlyStillReadsAsUnderTheProfile()
    {
        // The real installation lives in a profile this context never resolves.
        MakeExecutable(OfficialLayout("Right", "AppData", "Local"));

        var wrongProfile = MakeDirectory("Wrong");
        var wrongLocal = MakeDirectory("Wrong", "AppData", "Local");

        var trace = TraceOf(Resolver(
            localShell: wrongLocal,
            localFramework: wrongLocal,
            profileShell: wrongProfile,
            profileFramework: wrongProfile));

        // Everything structural looks right, and all of it is wrong.
        Assert.Equal(FolderResolutionState.Available, trace.LocalAppDataState);
        Assert.Equal(FolderResolutionState.Available, trace.UserProfileState);
        Assert.Equal(FolderProfileRelation.AllUnderProfile, trace.LocalAppDataProfileRelation);
        Assert.Equal(FolderSourceRelation.Agree, trace.LocalAppDataSourceRelation);

        // The probes are the part that cannot be fooled by consistency.
        Assert.Equal(CandidateProbeState.NotFound, trace.OfficialCodexShellProbe);
        Assert.Equal(CandidateProbeState.NotFound, trace.OfficialCodexProfileDerivedProbe);
        Assert.Equal(CandidateState.Missing, trace.OfficialCodexCandidateState);
        Assert.Equal(CodexLookupStage.Missing, trace.TerminalStage);
    }

    /// <summary>
    /// One root wrong and one right: reported per source, and the right one still
    /// wins the lookup.
    /// </summary>
    [WindowsFact]
    public void AWrongRootBesideACorrectOneIsVisibleAsBoth()
    {
        var profile = MakeDirectory("Profile");
        var correct = MakeDirectory("Profile", "AppData", "Local");
        var outside = MakeDirectory("Outside");
        var executable = MakeExecutable(OfficialLayout("Profile", "AppData", "Local"));

        var trace = TraceOf(Resolver(
            localShell: outside,
            localFramework: correct,
            profileShell: profile));

        Assert.Equal(FolderSourceRelation.Differ, trace.LocalAppDataSourceRelation);
        Assert.Equal(FolderRootCount.Multiple, trace.LocalAppDataRootCount);
        Assert.Equal(FolderProfileRelation.SomeOutsideProfile, trace.LocalAppDataProfileRelation);
        Assert.Equal(CandidateProbeState.NotFound, trace.OfficialCodexShellProbe);
        Assert.Equal(CandidateProbeState.Exists, trace.OfficialCodexFrameworkProbe);

        var lookup = new CodexExecutableLocator(Resolver(
            localShell: outside,
            localFramework: correct,
            profileShell: profile)).Locate();

        Assert.Equal(ExecutableLookupStatus.Found, lookup.Status);
        Assert.Equal(executable, lookup.Executable?.Path);
    }

    /// <summary>
    /// The field that separates the two surviving explanations. Local AppData
    /// resolves somewhere that exists and is wrong; the same documented layout
    /// reached through the user profile is there the whole time.
    /// </summary>
    [WindowsFact]
    public void TheProfileDerivedProbeSeesWhatAWrongLocalAppDataRootHides()
    {
        var profile = MakeDirectory("Profile");
        MakeExecutable(OfficialLayout("Profile", "AppData", "Local"));
        var elsewhere = MakeDirectory("Elsewhere");

        var trace = TraceOf(Resolver(
            localShell: elsewhere,
            localFramework: elsewhere,
            profileShell: profile,
            profileFramework: profile));

        Assert.Equal(FolderProfileRelation.NoneUnderProfile, trace.LocalAppDataProfileRelation);
        Assert.Equal(CandidateProbeState.NotFound, trace.OfficialCodexShellProbe);
        Assert.Equal(CandidateProbeState.Exists, trace.OfficialCodexProfileDerivedProbe);

        // Which is the reading that matters: the candidate is "missing" because
        // the root is wrong, not because Codex is not installed.
        Assert.Equal(CandidateState.Missing, trace.OfficialCodexCandidateState);
    }

    /// <summary>
    /// The profile-derived candidate explains a result. It never produces one:
    /// it is not a discovery candidate, so <c>ExecutableTrust</c> is never even
    /// asked about it and no lookup can end there.
    /// </summary>
    [WindowsFact]
    public void TheProfileDerivedCandidateIsDiagnosticOnly()
    {
        var profile = MakeDirectory("Profile");
        var planted = MakeExecutable(OfficialLayout("Profile", "AppData", "Local"));

        var resolver = Resolver(profileShell: profile, profileFramework: profile);
        var discovery = new CodexExecutableLocator(resolver).LocateWithTrace();

        Assert.Equal(CandidateProbeState.Exists, discovery.Trace.OfficialCodexProfileDerivedProbe);

        // Seen, and still not run.
        Assert.Equal(ExecutableLookupStatus.Missing, discovery.Lookup.Status);
        Assert.Equal(CodexLookupStage.Missing, discovery.Trace.TerminalStage);
        Assert.DoesNotContain(
            new CodexExecutableLocator(resolver).NativeCandidates(),
            candidate => string.Equals(candidate.Path, planted, StringComparison.OrdinalIgnoreCase));
    }

    // MARK: - The probe

    /// <summary>
    /// <c>File.Exists</c> answers false for a file that is there but unreadable,
    /// which is the exact ambiguity this investigation is stuck on. The probe
    /// keeps absence, refusal and failure apart.
    /// </summary>
    [WindowsFact]
    public void TheProbeSeparatesAbsenceFromRefusalFromFailure()
    {
        var present = MakeExecutable(OfficialLayout("Local"));

        Assert.Equal(CandidateProbeState.Exists, CandidateProbe.Probe(present));
        Assert.Equal(CandidateProbeState.NotFound, CandidateProbe.Probe(Path.Combine(_root, "absent.exe")));

        // A directory where the executable should be is not the file.
        Assert.Equal(CandidateProbeState.NotFound, CandidateProbe.Probe(_root));

        Assert.Equal(CandidateProbeState.InvalidRoot, CandidateProbe.Probe("   "));
        Assert.Equal(CandidateProbeState.InvalidRoot, CandidateProbe.Probe(null));

        // The outcomes a temp directory cannot be made to produce on demand.
        Assert.Equal(CandidateProbeState.NotFound, Failing(new FileNotFoundException()));
        Assert.Equal(CandidateProbeState.NotFound, Failing(new DirectoryNotFoundException()));
        Assert.Equal(CandidateProbeState.AccessDenied, Failing(new UnauthorizedAccessException()));
        Assert.Equal(CandidateProbeState.AccessDenied, Failing(new System.Security.SecurityException()));
        Assert.Equal(CandidateProbeState.IoError, Failing(new IOException()));
        Assert.Equal(CandidateProbeState.InvalidRoot, Failing(new PathTooLongException()));
        Assert.Equal(CandidateProbeState.InvalidRoot, Failing(new ArgumentException()));
        Assert.Equal(CandidateProbeState.InvalidRoot, Failing(new NotSupportedException()));
    }

    /// <summary>
    /// Whatever the failure was, only the classification survives it. A Win32
    /// message carries the path it failed on, and none of that may reach a
    /// summary the user copies.
    /// </summary>
    [WindowsFact]
    public void AFailedProbeCarriesNothingFromTheFailure()
    {
        var secret = Path.Combine(_root, "Users", Environment.UserName, "codex.exe");
        var state = CandidateProbe.Probe(
            secret,
            path => throw new UnauthorizedAccessException("Access to the path '" + path + "' is denied."));

        Assert.Equal(CandidateProbeState.AccessDenied, state);
        Assert.DoesNotContain(secret, state.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    private static CandidateProbeState Failing(Exception failure) =>
        CandidateProbe.Probe(@"C:\candidate.exe", _ => throw failure);

    /// <summary>
    /// Each probe field only carries the values that belong to it, whatever the
    /// context: the collapse marker names the other source, never its own.
    /// </summary>
    [WindowsFact]
    public void EachProbeFieldOnlyReportsValuesThatBelongToIt()
    {
        var local = MakeDirectory("Local");
        var other = MakeDirectory("Other");
        var profile = MakeDirectory("Profile");

        var shapes = new[]
        {
            Resolver(localShell: local, localFramework: local, profileShell: profile),
            Resolver(localShell: local, localFramework: other, profileShell: profile),
            Resolver(localShell: local, localFramework: null),
            Resolver(localShell: null, localFramework: local),
            Resolver(),
            Resolver(localShell: Path.Combine(_root, "missing"))
        };

        foreach (var trace in shapes.Select(TraceOf))
        {
            Assert.NotEqual(CandidateProbeState.SameAsShell, trace.OfficialCodexShellProbe);
            Assert.NotEqual(CandidateProbeState.SameAsFramework, trace.OfficialCodexFrameworkProbe);
            Assert.NotEqual(CandidateProbeState.SameAsShell, trace.OfficialCodexProfileDerivedProbe);
            Assert.NotEqual(CandidateProbeState.SameAsFramework, trace.OfficialCodexProfileDerivedProbe);
        }
    }

    // MARK: - The trace belongs to one operation

    /// <summary>
    /// The reader keeps the trace the lookup produced. It is a record of an
    /// operation, not a cache and not a fresh measurement: a summary copied later
    /// has to describe the resolution that produced the reported result.
    /// </summary>
    [WindowsFact]
    public async Task TheReaderKeepsTheTraceFromTheLookupItActuallyRan()
    {
        var local = MakeDirectory("Local");
        var resolver = Resolver(localShell: local, localFramework: local);
        var reader = new CodexUsageReader(new CodexExecutableLocator(resolver));

        Assert.Equal(CodexDiscoveryTrace.NotRun, reader.LastDiscoveryTrace);

        // Nothing is installed, so this resolves to missing without starting
        // anything.
        await reader.ReadAsync();

        var captured = reader.LastDiscoveryTrace;
        Assert.Equal(ProviderExecutableState.Missing, reader.LastExecutableState);
        Assert.Equal(CandidateProbeState.NotFound, captured.OfficialCodexShellProbe);
        Assert.Equal(CodexLookupStage.Missing, captured.TerminalStage);

        // Install Codex now, and do not run another lookup. The retained trace
        // still describes the lookup that produced LastExecutableState.
        MakeExecutable(OfficialLayout("Local"));

        Assert.Same(captured, reader.LastDiscoveryTrace);
        Assert.Equal(CandidateProbeState.NotFound, reader.LastDiscoveryTrace.OfficialCodexShellProbe);

        // A new lookup does see it, so nothing has been pinned permanently.
        Assert.Equal(CandidateProbeState.Exists, TraceOf(resolver).OfficialCodexShellProbe);
    }

    /// <summary>
    /// Building the summary resolves nothing and touches no disk. A second pass
    /// would describe the moment the summary was copied, and the open question is
    /// precisely whether that moment resolves the same way as discovery did.
    /// </summary>
    [WindowsFact]
    public void BuildingTheSummaryDoesNotResolveOrProbeASecondTime()
    {
        var local = MakeDirectory("Local");
        MakeExecutable(OfficialLayout("Local"));

        var counting = new CountingResolver(Resolver(localShell: local, localFramework: local));
        var discovery = new CodexExecutableLocator(counting).LocateWithTrace();

        var duringLookup = counting.Calls;
        Assert.True(duringLookup > 0);
        Assert.Equal(CandidateProbeState.Exists, discovery.Trace.OfficialCodexShellProbe);

        // Remove the installation the lookup just found. Anything that re-probed
        // while building the summary would now report it absent.
        Directory.Delete(Path.Combine(local, "Programs"), recursive: true);

        var report = DiagnosticsReportBuilder.Build(Summary(discovery.Trace));

        Assert.Equal(duringLookup, counting.Calls);
        Assert.Contains("official_codex_shell_probe=exists", report, StringComparison.Ordinal);
        Assert.Contains("official_codex_candidate_state=exists", report, StringComparison.Ordinal);
        Assert.Contains("codex_lookup_terminal_stage=official_native", report, StringComparison.Ordinal);
    }

    // MARK: - Nothing private escapes

    /// <summary>
    /// The trace is built from real paths on a real disk and reduces every one of
    /// them to a bare word.
    /// </summary>
    [WindowsFact]
    public void TheSummaryCarriesNoPathUserNameOrRoot()
    {
        var local = MakeDirectory("Local");
        var other = MakeDirectory("Other");
        var profile = MakeDirectory("Profile");
        MakeExecutable(OfficialLayout("Local"));
        MakeExecutable(OfficialLayout("Profile", "AppData", "Local"));

        var trace = TraceOf(Resolver(
            localShell: local,
            localFramework: other,
            profileShell: profile,
            profileFramework: profile));

        var report = DiagnosticsReportBuilder.Build(Summary(trace));

        foreach (var secret in new[] { _root, local, other, profile, "Programs", "OpenAI", "AppData" })
        {
            Assert.DoesNotContain(secret, report, StringComparison.OrdinalIgnoreCase);
        }

        if (Environment.UserName.Length > 3)
        {
            Assert.DoesNotContain(Environment.UserName, report, StringComparison.OrdinalIgnoreCase);
        }

        // No drive letter, no separator, and every trace line a bare word.
        Assert.DoesNotContain(":\\", report, StringComparison.Ordinal);
        foreach (var prefix in TracePrefixes)
        {
            var line = report
                .Split('\n')
                .Select(candidate => candidate.Trim('\r'))
                .Single(candidate => candidate.StartsWith(prefix, StringComparison.Ordinal));

            Assert.Matches("^[a-z_]+=[a-z_]+$", line);
        }
    }

    private static readonly string[] TracePrefixes =
    {
        "local_app_data_source_relation=",
        "local_app_data_root_count=",
        "local_app_data_profile_relation=",
        "official_codex_shell_probe=",
        "official_codex_framework_probe=",
        "official_codex_profile_derived_probe=",
        "codex_lookup_terminal_stage="
    };

    /// <summary>A summary shaped like the one the tray menu copies.</summary>
    private static DiagnosticsInput Summary(CodexDiscoveryTrace trace) => new(
        AppVersion: "1.9.0",
        BuildId: "60dd90a",
        WindowsVersion: "10.0.26200.0",
        OsArchitecture: "x64",
        AppArchitecture: "x64",
        Language: "english",
        LastSuccessfulRefresh: DateTimeOffset.FromUnixTimeSeconds(1_800_000_000),
        HistoryEnabled: true,
        HistorySeriesCount: 2,
        HistorySampleCount: 2,
        TrayGuidanceVersionShown: 2,
        AutoStartEnabled: false,
        Providers: new[]
        {
            new ProviderDiagnostics(
                ProviderNames.Codex,
                Connected: true,
                ProviderExecutableState.Missing,
                ProviderAdapterKind.None,
                ProviderDataState.Error,
                Array.Empty<string>(),
                "codex_not_found")
        },
        LocalAppDataState: trace.LocalAppDataState,
        UserProfileState: trace.UserProfileState,
        OfficialCodexCandidateState: trace.OfficialCodexCandidateState,
        ProcessParentKind: ProcessParentKind.Setup,
        DiscoveryTrace: trace);

    /// <summary>Counts how often discovery asks for a folder.</summary>
    private sealed class CountingResolver : IKnownFolderResolver
    {
        private readonly IKnownFolderResolver _inner;

        public CountingResolver(IKnownFolderResolver inner) => _inner = inner;

        public int Calls { get; private set; }

        public IReadOnlyList<string> Resolve(WindowsKnownFolder folder)
        {
            Calls++;
            return _inner.Resolve(folder);
        }

        public KnownFolderSources ResolveSources(WindowsKnownFolder folder)
        {
            Calls++;
            return _inner.ResolveSources(folder);
        }
    }
}
