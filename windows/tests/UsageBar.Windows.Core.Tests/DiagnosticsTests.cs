using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Core.Providers;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

public sealed class DiagnosticsTests
{
    /// <summary>Strings that must never reach a diagnostics summary.</summary>
    public static TheoryData<string> SensitiveValues() => new()
    {
        @"C:\Users\ahmed\AppData\Local\Programs\codex\codex.exe",
        @"\\fileserver\share\codex.exe",
        "/home/ahmed/.local/bin/claude",
        "%LOCALAPPDATA%\\UsageBar",
        "sk-ant-api03-Xy1234567890abcdefghijklmnop",
        "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
        "password=hunter2",
        "https://api.anthropic.com/v1/messages",
        "codex app-server --stdio --disable apps",
        "C:\\Projects\\secret-client\\src",
        "ANTHROPIC_API_KEY=abcdef"
    };

    private static DiagnosticsInput Input(
        string? issueCode = null,
        string? appVersion = null,
        string? windowsVersion = null,
        IReadOnlyList<string>? windowKinds = null,
        string? buildId = null,
        FolderResolutionState localAppData = FolderResolutionState.Available,
        FolderResolutionState userProfile = FolderResolutionState.Available,
        CandidateState codexCandidate = CandidateState.Exists,
        ProcessParentKind parentKind = ProcessParentKind.Shell,
        CodexDiscoveryTrace? trace = null) =>
        new(
            AppVersion: appVersion ?? "1.9.0",
            BuildId: buildId ?? "0a48c1e",
            WindowsVersion: windowsVersion ?? "10.0.22631",
            OsArchitecture: "X64",
            AppArchitecture: "X64",
            Language: "turkish",
            LastSuccessfulRefresh: DateTimeOffset.FromUnixTimeSeconds(1_800_000_000),
            HistoryEnabled: true,
            HistorySeriesCount: 3,
            HistorySampleCount: 120,
            TrayGuidanceVersionShown: 1,
            AutoStartEnabled: false,
            Providers: new[]
            {
                new ProviderDiagnostics(
                    ProviderNames.Codex,
                    Connected: true,
                    ProviderExecutableState.Trusted,
                    ProviderAdapterKind.NativeExecutable,
                    ProviderDataState.Fresh,
                    windowKinds ?? new[] { "five-hour", "weekly" },
                    issueCode ?? "none"),
                new ProviderDiagnostics(
                    ProviderNames.ClaudeCode,
                    Connected: true,
                    ProviderExecutableState.UnsupportedInstallation,
                    ProviderAdapterKind.Wsl,
                    ProviderDataState.Stale,
                    Array.Empty<string>(),
                    "claude_usage_timed_out")
            },
            LocalAppDataState: localAppData,
            UserProfileState: userProfile,
            OfficialCodexCandidateState: codexCandidate,
            ProcessParentKind: parentKind,
            DiscoveryTrace: trace);

    /// <summary>A trace with every field set to something distinguishable.</summary>
    private static CodexDiscoveryTrace Trace(
        FolderSourceRelation sourceRelation = FolderSourceRelation.Agree,
        FolderRootCount rootCount = FolderRootCount.One,
        FolderProfileRelation profileRelation = FolderProfileRelation.AllUnderProfile,
        CandidateProbeState shellProbe = CandidateProbeState.Exists,
        CandidateProbeState frameworkProbe = CandidateProbeState.SameAsShell,
        CandidateProbeState profileDerivedProbe = CandidateProbeState.Exists,
        CodexLookupStage stage = CodexLookupStage.OfficialNative,
        FolderResolutionState localAppData = FolderResolutionState.Available,
        NativeProbeOutcome? native = null,
        ProcessTokenSnapshot? token = null) =>
        new(
            localAppData,
            FolderResolutionState.Available,
            sourceRelation,
            rootCount,
            profileRelation,
            shellProbe,
            frameworkProbe,
            profileDerivedProbe,
            stage,
            native ?? new NativeProbeOutcome(NativeProbeState.Exists, null, HandleProbeState.Opened),
            token ?? new ProcessTokenSnapshot(
                TokenProfileRelation.MatchesResolvedProfile,
                TokenIntegrity.Medium,
                TokenElevation.Default,
                TokenFlagState.No,
                TokenFlagState.No,
                SessionRelation.ActiveConsole));

    [Fact]
    public void ReportContainsOnlySafeFacts()
    {
        var report = DiagnosticsReportBuilder.Build(Input());

        Assert.Contains("UsageBar 1.9.0", report, StringComparison.Ordinal);
        Assert.Contains("build=0a48c1e", report, StringComparison.Ordinal);
        Assert.Contains("windows=10.0.22631", report, StringComparison.Ordinal);
        Assert.Contains("os_arch=X64", report, StringComparison.Ordinal);
        Assert.Contains("language=turkish", report, StringComparison.Ordinal);
        Assert.Contains("last_refresh=2027-01-15T08:00:00Z", report, StringComparison.Ordinal);
        Assert.Contains("history_enabled=true", report, StringComparison.Ordinal);
        Assert.Contains("tray_guidance_version=1", report, StringComparison.Ordinal);
        Assert.Contains("autostart=false", report, StringComparison.Ordinal);
        Assert.Contains(
            "codex=connected:true,executable:trusted,adapter:native_exe,state:fresh,windows:five-hour+weekly,issue:none",
            report,
            StringComparison.Ordinal);
        Assert.Contains(
            "claude=connected:true,executable:unsupported_installation,adapter:wsl,state:stale,windows:none,issue:claude_usage_timed_out",
            report,
            StringComparison.Ordinal);
    }

    /// <summary>
    /// The launch-context facts, which exist because provider discovery was seen
    /// to depend on how UsageBar was started. Each is a state, never a path.
    /// </summary>
    [Fact]
    public void TheReportStatesTheLaunchContext()
    {
        var shellLaunch = DiagnosticsReportBuilder.Build(Input());

        Assert.Contains("local_app_data_state=available", shellLaunch, StringComparison.Ordinal);
        Assert.Contains("user_profile_state=available", shellLaunch, StringComparison.Ordinal);
        Assert.Contains("official_codex_candidate_state=exists", shellLaunch, StringComparison.Ordinal);
        Assert.Contains("process_parent_kind=shell", shellLaunch, StringComparison.Ordinal);

        // The context the physical test hit: Setup started UsageBar, Local
        // AppData resolved to nothing, so the Codex candidate was never built.
        var setupLaunch = DiagnosticsReportBuilder.Build(Input(
            localAppData: FolderResolutionState.Empty,
            codexCandidate: CandidateState.NotConstructed,
            parentKind: ProcessParentKind.Setup));

        Assert.Contains("local_app_data_state=empty", setupLaunch, StringComparison.Ordinal);
        Assert.Contains("official_codex_candidate_state=not_constructed", setupLaunch, StringComparison.Ordinal);
        Assert.Contains("process_parent_kind=setup", setupLaunch, StringComparison.Ordinal);

        // Each is a bare word, so a drive letter, separator, user name or
        // environment value could not survive in one even by accident.
        foreach (var report in new[] { shellLaunch, setupLaunch })
        {
            foreach (var prefix in LaunchContextPrefixes)
            {
                Assert.Matches("^[a-z_]+=[a-z_]+$", Line(report, prefix));
            }
        }
    }

    private static readonly string[] LaunchContextPrefixes =
    {
        "local_app_data_state=",
        "user_profile_state=",
        "official_codex_candidate_state=",
        "process_parent_kind=",
        "local_app_data_source_relation=",
        "local_app_data_root_count=",
        "local_app_data_profile_relation=",
        "official_codex_shell_probe=",
        "official_codex_framework_probe=",
        "official_codex_profile_derived_probe=",
        "codex_lookup_terminal_stage=",
        "official_codex_native_probe=",
        "official_codex_handle_probe=",
        "process_token_profile_relation=",
        "process_token_integrity=",
        "process_token_elevation=",
        "process_token_restricted=",
        "process_token_appcontainer=",
        "process_session_relation="
    };

    /// <summary>
    /// The native probe carries a number as well as a word. Everything else in a
    /// report is a closed-set word, so this one line has its own shape and its
    /// own bound: a decimal Win32 code, or nothing.
    /// </summary>
    [Fact]
    public void TheWin32ErrorCodeIsANumberAndNothingElse()
    {
        Assert.Contains(
            "official_codex_native_error_code=win32_32",
            DiagnosticsReportBuilder.Build(Input(trace: Trace(
                native: new NativeProbeOutcome(
                    NativeProbeState.SharingViolation, 32, HandleProbeState.SharingViolation)))),
            StringComparison.Ordinal);

        // Success carries no code, and neither does an absent one.
        foreach (var absent in new int?[] { null, 0 })
        {
            Assert.Contains(
                "official_codex_native_error_code=none",
                DiagnosticsReportBuilder.Build(Input(trace: Trace(
                    native: new NativeProbeOutcome(NativeProbeState.Exists, absent, HandleProbeState.Opened)))),
                StringComparison.Ordinal);
        }

        // A value that could not be a Win32 error is refused rather than echoed,
        // so the field cannot become a channel for something else.
        foreach (var absurd in new[] { -1, int.MinValue, 70000, int.MaxValue })
        {
            var line = Line(
                DiagnosticsReportBuilder.Build(Input(trace: Trace(
                    native: new NativeProbeOutcome(
                        NativeProbeState.OtherError, absurd, HandleProbeState.OtherError)))),
                "official_codex_native_error_code=");

            Assert.Equal("official_codex_native_error_code=" + DiagnosticsSanitizer.Redacted, line);
            Assert.DoesNotContain(absurd.ToString(), line, StringComparison.Ordinal);
        }

        foreach (var code in new[] { 2, 3, 5, 32, 33, 1920, 4390, 65535 })
        {
            var line = Line(
                DiagnosticsReportBuilder.Build(Input(trace: Trace(
                    native: new NativeProbeOutcome(NativeProbeState.OtherError, code, HandleProbeState.OtherError)))),
                "official_codex_native_error_code=");

            Assert.Matches("^official_codex_native_error_code=win32_[0-9]+$", line);
        }
    }

    /// <summary>
    /// The native and token fields, which exist because the managed probe could
    /// only say "something below me failed".
    /// </summary>
    [Fact]
    public void TheReportStatesTheNativeFailureAndTheSecurityContext()
    {
        var report = DiagnosticsReportBuilder.Build(Input(trace: Trace(
            native: new NativeProbeOutcome(
                NativeProbeState.SharingViolation, 32, HandleProbeState.Opened),
            token: new ProcessTokenSnapshot(
                TokenProfileRelation.DiffersFromResolvedProfile,
                TokenIntegrity.Low,
                TokenElevation.Limited,
                TokenFlagState.Yes,
                TokenFlagState.Yes,
                SessionRelation.Other))));

        Assert.Contains("official_codex_native_probe=sharing_violation", report, StringComparison.Ordinal);
        Assert.Contains("official_codex_native_error_code=win32_32", report, StringComparison.Ordinal);

        // The pair that matters: the attribute query failed and a metadata handle
        // still opened, which is a filter-stack answer rather than a missing file.
        Assert.Contains("official_codex_handle_probe=opened", report, StringComparison.Ordinal);

        Assert.Contains(
            "process_token_profile_relation=differs_from_resolved_profile",
            report,
            StringComparison.Ordinal);
        Assert.Contains("process_token_integrity=low", report, StringComparison.Ordinal);
        Assert.Contains("process_token_elevation=limited", report, StringComparison.Ordinal);
        Assert.Contains("process_token_restricted=yes", report, StringComparison.Ordinal);
        Assert.Contains("process_token_appcontainer=yes", report, StringComparison.Ordinal);
        Assert.Contains("process_session_relation=other", report, StringComparison.Ordinal);
    }

    /// <summary>
    /// The exact-operation trace. The coarse candidate state says only that a
    /// documented path was built and the file was not under it; these say which
    /// source built it, where that source pointed, and what the probe hit.
    /// </summary>
    [Fact]
    public void TheReportStatesHowTheCodexLookupWent()
    {
        var report = DiagnosticsReportBuilder.Build(Input(trace: Trace()));

        Assert.Contains("local_app_data_source_relation=agree", report, StringComparison.Ordinal);
        Assert.Contains("local_app_data_root_count=one", report, StringComparison.Ordinal);
        Assert.Contains("local_app_data_profile_relation=all_under_profile", report, StringComparison.Ordinal);
        Assert.Contains("official_codex_shell_probe=exists", report, StringComparison.Ordinal);
        Assert.Contains("official_codex_framework_probe=same_as_shell", report, StringComparison.Ordinal);
        Assert.Contains("official_codex_profile_derived_probe=exists", report, StringComparison.Ordinal);
        Assert.Contains("codex_lookup_terminal_stage=official_native", report, StringComparison.Ordinal);

        // The shape physical testing is trying to tell apart: Local AppData
        // resolves, the sources disagree, one of them is wrong, and the same
        // layout reached through the profile is there all along.
        var wrongRoot = DiagnosticsReportBuilder.Build(Input(trace: Trace(
            sourceRelation: FolderSourceRelation.Differ,
            rootCount: FolderRootCount.Multiple,
            profileRelation: FolderProfileRelation.SomeOutsideProfile,
            shellProbe: CandidateProbeState.NotFound,
            frameworkProbe: CandidateProbeState.AccessDenied,
            profileDerivedProbe: CandidateProbeState.Exists,
            stage: CodexLookupStage.Missing)));

        Assert.Contains("local_app_data_source_relation=differ", wrongRoot, StringComparison.Ordinal);
        Assert.Contains("local_app_data_root_count=multiple", wrongRoot, StringComparison.Ordinal);
        Assert.Contains("official_codex_shell_probe=not_found", wrongRoot, StringComparison.Ordinal);
        Assert.Contains("official_codex_framework_probe=access_denied", wrongRoot, StringComparison.Ordinal);
        Assert.Contains("official_codex_profile_derived_probe=exists", wrongRoot, StringComparison.Ordinal);
        Assert.Contains("codex_lookup_terminal_stage=missing", wrongRoot, StringComparison.Ordinal);
    }

    /// <summary>
    /// A report built without a trace still has every line, so the format does
    /// not change shape between a lookup having run and not having run.
    /// </summary>
    [Fact]
    public void AReportWithNoLookupYetStillStatesEveryField()
    {
        var report = DiagnosticsReportBuilder.Build(Input(trace: null));

        foreach (var prefix in LaunchContextPrefixes)
        {
            Assert.Matches("^[a-z_]+=[a-z_]+$", Line(report, prefix));
        }

        Assert.Contains("local_app_data_source_relation=none", report, StringComparison.Ordinal);
        Assert.Contains("official_codex_shell_probe=not_constructed", report, StringComparison.Ordinal);
        Assert.Contains("codex_lookup_terminal_stage=missing", report, StringComparison.Ordinal);
    }

    /// <summary>
    /// The coarse candidate state is derived from the probes rather than
    /// measured separately, so the two can never contradict each other.
    /// </summary>
    [Fact]
    public void TheCandidateStateFollowsTheProbesItIsDerivedFrom()
    {
        Assert.Equal(
            CandidateState.NotConstructed,
            Trace(localAppData: FolderResolutionState.Empty).OfficialCodexCandidateState);

        Assert.Equal(
            CandidateState.Exists,
            Trace(shellProbe: CandidateProbeState.Exists).OfficialCodexCandidateState);

        // Found only by the framework source still counts as found.
        Assert.Equal(
            CandidateState.Exists,
            Trace(
                shellProbe: CandidateProbeState.NotFound,
                frameworkProbe: CandidateProbeState.Exists).OfficialCodexCandidateState);

        // A root that resolved, with nothing under it, is "missing" — and an
        // unreadable file is not silently promoted to "exists".
        foreach (var probe in new[]
                 {
                     CandidateProbeState.NotFound,
                     CandidateProbeState.AccessDenied,
                     CandidateProbeState.IoError,
                     CandidateProbeState.InvalidRoot
                 })
        {
            Assert.Equal(
                CandidateState.Missing,
                Trace(shellProbe: probe, frameworkProbe: probe).OfficialCodexCandidateState);
        }
    }

    /// <summary>
    /// Every state of every launch-context field has to be tellable apart in a
    /// report, or the field cannot answer the question it was added for.
    /// </summary>
    [Fact]
    public void EveryLaunchContextStateIsDistinguishable()
    {
        AssertDistinctLines(
            Enum.GetValues<FolderResolutionState>().Select(state =>
                Line(DiagnosticsReportBuilder.Build(Input(localAppData: state)), "local_app_data_state=")));

        AssertDistinctLines(
            Enum.GetValues<FolderResolutionState>().Select(state =>
                Line(DiagnosticsReportBuilder.Build(Input(userProfile: state)), "user_profile_state=")));

        AssertDistinctLines(
            Enum.GetValues<CandidateState>().Select(state =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(codexCandidate: state)),
                    "official_codex_candidate_state=")));

        AssertDistinctLines(
            Enum.GetValues<ProcessParentKind>().Select(kind =>
                Line(DiagnosticsReportBuilder.Build(Input(parentKind: kind)), "process_parent_kind=")));

        AssertDistinctLines(
            Enum.GetValues<FolderSourceRelation>().Select(relation =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(trace: Trace(sourceRelation: relation))),
                    "local_app_data_source_relation=")));

        AssertDistinctLines(
            Enum.GetValues<FolderRootCount>().Select(count =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(trace: Trace(rootCount: count))),
                    "local_app_data_root_count=")));

        AssertDistinctLines(
            Enum.GetValues<FolderProfileRelation>().Select(relation =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(trace: Trace(profileRelation: relation))),
                    "local_app_data_profile_relation=")));

        // Every probe outcome has to be tellable apart on every probe field, or
        // the fields cannot separate a wrong root from an unreadable file.
        foreach (var (prefix, build) in new (string, Func<CandidateProbeState, CodexDiscoveryTrace>)[]
                 {
                     ("official_codex_shell_probe=", state => Trace(shellProbe: state)),
                     ("official_codex_framework_probe=", state => Trace(frameworkProbe: state)),
                     ("official_codex_profile_derived_probe=", state => Trace(profileDerivedProbe: state))
                 })
        {
            AssertDistinctLines(
                Enum.GetValues<CandidateProbeState>().Select(state =>
                    Line(DiagnosticsReportBuilder.Build(Input(trace: build(state))), prefix)));
        }

        AssertDistinctLines(
            Enum.GetValues<CodexLookupStage>().Select(stage =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(trace: Trace(stage: stage))),
                    "codex_lookup_terminal_stage=")));

        AssertDistinctLines(
            Enum.GetValues<NativeProbeState>().Select(state =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(trace: Trace(
                        native: new NativeProbeOutcome(state, null, HandleProbeState.Opened)))),
                    "official_codex_native_probe=")));

        AssertDistinctLines(
            Enum.GetValues<HandleProbeState>().Select(state =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(trace: Trace(
                        native: new NativeProbeOutcome(NativeProbeState.Exists, null, state)))),
                    "official_codex_handle_probe=")));

        AssertDistinctLines(
            Enum.GetValues<TokenProfileRelation>().Select(relation =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(trace: Trace(token: Token(profile: relation)))),
                    "process_token_profile_relation=")));

        AssertDistinctLines(
            Enum.GetValues<TokenIntegrity>().Select(integrity =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(trace: Trace(token: Token(integrity: integrity)))),
                    "process_token_integrity=")));

        AssertDistinctLines(
            Enum.GetValues<TokenElevation>().Select(elevation =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(trace: Trace(token: Token(elevation: elevation)))),
                    "process_token_elevation=")));

        foreach (var (prefix, build) in new (string, Func<TokenFlagState, ProcessTokenSnapshot>)[]
                 {
                     ("process_token_restricted=", flag => Token(restricted: flag)),
                     ("process_token_appcontainer=", flag => Token(appContainer: flag))
                 })
        {
            AssertDistinctLines(
                Enum.GetValues<TokenFlagState>().Select(flag =>
                    Line(DiagnosticsReportBuilder.Build(Input(trace: Trace(token: build(flag)))), prefix)));
        }

        AssertDistinctLines(
            Enum.GetValues<SessionRelation>().Select(session =>
                Line(
                    DiagnosticsReportBuilder.Build(Input(trace: Trace(token: Token(session: session)))),
                    "process_session_relation=")));
    }

    private static ProcessTokenSnapshot Token(
        TokenProfileRelation profile = TokenProfileRelation.MatchesResolvedProfile,
        TokenIntegrity integrity = TokenIntegrity.Medium,
        TokenElevation elevation = TokenElevation.Default,
        TokenFlagState restricted = TokenFlagState.No,
        TokenFlagState appContainer = TokenFlagState.No,
        SessionRelation session = SessionRelation.ActiveConsole) =>
        new(profile, integrity, elevation, restricted, appContainer, session);

    private static string Line(string report, string prefix)
    {
        var line = report
            .Split('\n')
            .Select(candidate => candidate.Trim('\r'))
            .SingleOrDefault(candidate => candidate.StartsWith(prefix, StringComparison.Ordinal));

        Assert.NotNull(line);
        return line;
    }

    private static void AssertDistinctLines(IEnumerable<string> lines)
    {
        var reported = lines.ToArray();

        Assert.All(reported, line => Assert.Matches("^[a-z_]+=[a-z_]+$", line));
        Assert.Equal(reported.Length, reported.Distinct(StringComparer.Ordinal).Count());
    }

    [Theory]
    [MemberData(nameof(SensitiveValues))]
    public void SensitiveValuesNeverAppearInTheReport(string sensitive)
    {
        var report = DiagnosticsReportBuilder.Build(Input(
            issueCode: sensitive,
            appVersion: sensitive,
            windowsVersion: sensitive,
            windowKinds: new[] { sensitive },
            buildId: sensitive));

        Assert.DoesNotContain(sensitive, report, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(DiagnosticsSanitizer.Redacted, report, StringComparison.Ordinal);
    }

    [Fact]
    public void UnknownIssueCodesAreRedactedRatherThanEchoed()
    {
        var report = DiagnosticsReportBuilder.Build(Input(issueCode: "totally_made_up"));

        Assert.DoesNotContain("totally_made_up", report, StringComparison.Ordinal);
        Assert.Contains("issue:redacted", report, StringComparison.Ordinal);
    }

    [Fact]
    public void EveryKnownIssueCodeSurvivesTheReport()
    {
        foreach (var code in ProviderIssue.KnownDiagnosticCodes)
        {
            var report = DiagnosticsReportBuilder.Build(Input(issueCode: code));
            Assert.Contains($"issue:{code}", report, StringComparison.Ordinal);
        }
    }

    [Theory]
    [InlineData(null, DiagnosticsSanitizer.None)]
    [InlineData("", DiagnosticsSanitizer.None)]
    [InlineData("   ", DiagnosticsSanitizer.None)]
    [InlineData("native_exe", "native_exe")]
    [InlineData("1.9.0", "1.9.0")]
    [InlineData("five-hour", "five-hour")]
    [InlineData(@"C:\Windows", DiagnosticsSanitizer.Redacted)]
    [InlineData("has space", DiagnosticsSanitizer.Redacted)]
    [InlineData("key=value", DiagnosticsSanitizer.Redacted)]
    [InlineData("a,b", DiagnosticsSanitizer.Redacted)]
    public void SanitizerClassifiesTokens(string? value, string expected)
    {
        Assert.Equal(expected, DiagnosticsSanitizer.SafeToken(value));
    }

    [Fact]
    public void OverlongTokensAreRedacted()
    {
        var overlong = new string('a', DiagnosticsSanitizer.MaximumTokenLength + 1);
        Assert.Equal(DiagnosticsSanitizer.Redacted, DiagnosticsSanitizer.SafeToken(overlong));
    }
}
