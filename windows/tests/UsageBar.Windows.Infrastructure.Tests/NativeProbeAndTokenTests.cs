using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Infrastructure.Diagnostics;
using UsageBar.Windows.Infrastructure.Discovery;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// The direct Win32 probe and the process-token classification.
///
/// The managed probe took the investigation as far as it goes: the Setup-launched
/// session reported <c>io_error</c> for the official Codex candidate and the Start
/// Menu session reported <c>exists</c>, on the same file a minute apart. .NET
/// folds sharing violations, lock violations, reparse faults and cloud-provider
/// faults into a single <c>IOException</c>, and <c>File.Exists</c> — which is what
/// <c>ExecutableTrust</c> reaches first — folds that into <c>false</c>. A live I/O
/// failure therefore arrives in a report as "Codex is not installed".
///
/// These tests pin the two things that can tell those apart: the exact Win32 error
/// taken at the call site, and the security context the call was made in.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class NativeProbeAndTokenTests : IDisposable
{
    private readonly string _root = Path.Combine(
        Path.GetTempPath(),
        "usagebar-native-" + Guid.NewGuid().ToString("N"));

    public NativeProbeAndTokenTests() => Directory.CreateDirectory(_root);

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

    // MARK: - Error classification

    /// <summary>
    /// Every error the framework would have collapsed into one <c>IOException</c>,
    /// kept apart. The buckets are a convenience; the number beside them is what
    /// actually decides the next step, which is why it is reported too.
    /// </summary>
    [WindowsTheory]
    [InlineData(2, NativeProbeState.FileNotFound)]
    [InlineData(3, NativeProbeState.PathNotFound)]
    [InlineData(5, NativeProbeState.AccessDenied)]
    [InlineData(32, NativeProbeState.SharingViolation)]
    [InlineData(33, NativeProbeState.LockViolation)]
    [InlineData(1920, NativeProbeState.CantAccessFile)]
    [InlineData(741, NativeProbeState.ReparseError)]
    [InlineData(1921, NativeProbeState.ReparseError)]
    [InlineData(4390, NativeProbeState.ReparseError)]
    [InlineData(4392, NativeProbeState.ReparseError)]
    [InlineData(4394, NativeProbeState.ReparseError)]
    [InlineData(362, NativeProbeState.CloudUnavailable)]
    [InlineData(367, NativeProbeState.CloudUnavailable)]
    [InlineData(395, NativeProbeState.CloudUnavailable)]
    [InlineData(417, NativeProbeState.CloudUnavailable)]
    [InlineData(15, NativeProbeState.DeviceError)]
    [InlineData(21, NativeProbeState.DeviceError)]
    [InlineData(23, NativeProbeState.DeviceError)]
    [InlineData(31, NativeProbeState.DeviceError)]
    [InlineData(1117, NativeProbeState.DeviceError)]
    [InlineData(87, NativeProbeState.OtherError)]
    [InlineData(1450, NativeProbeState.OtherError)]
    public void EveryNativeErrorIsClassified(int errorCode, NativeProbeState expected)
    {
        Assert.Equal(expected, NativeCandidateProbe.ClassifyAttributes(NativeCallOutcome.Failed(errorCode)));
    }

    [WindowsFact]
    public void ASuccessfulAttributeQueryIsTheOnlyWayToReportExists()
    {
        Assert.Equal(NativeProbeState.Exists, NativeCandidateProbe.ClassifyAttributes(NativeCallOutcome.Ok));

        // No error code, however benign, may be read as the file being there.
        foreach (var code in new[] { 0, 2, 5, 32, 1920, 4392, 99999 })
        {
            Assert.NotEqual(
                NativeProbeState.Exists,
                NativeCandidateProbe.ClassifyAttributes(NativeCallOutcome.Failed(code)));
        }
    }

    [WindowsTheory]
    [InlineData(2, HandleProbeState.NotFound)]
    [InlineData(3, HandleProbeState.NotFound)]
    [InlineData(5, HandleProbeState.AccessDenied)]
    [InlineData(32, HandleProbeState.SharingViolation)]
    [InlineData(33, HandleProbeState.SharingViolation)]
    [InlineData(741, HandleProbeState.ReparseError)]
    [InlineData(4391, HandleProbeState.ReparseError)]
    [InlineData(1450, HandleProbeState.OtherError)]
    public void EveryHandleFailureIsClassified(int errorCode, HandleProbeState expected)
    {
        Assert.Equal(expected, NativeCandidateProbe.ClassifyHandle(NativeCallOutcome.Failed(errorCode)));
    }

    [WindowsFact]
    public void OnlyAnOpenedHandleIsReportedAsOpened()
    {
        Assert.Equal(HandleProbeState.Opened, NativeCandidateProbe.ClassifyHandle(NativeCallOutcome.Ok));
    }

    // MARK: - The error belongs to the call that produced it

    /// <summary>
    /// The Win32 error is taken on the statement after the call and kept in an
    /// immutable result. Anything that runs later — in this test, something that
    /// deliberately sets a different one — cannot rewrite it.
    /// </summary>
    [WindowsFact]
    public void TheWin32ErrorIsCapturedAtTheCallSiteNotReadBackLater()
    {
        var outcome = NativeCandidateProbe.Probe(
            @"C:\candidate.exe",
            _ =>
            {
                var captured = NativeCallOutcome.Failed(32);

                // Whatever the rest of the probe does afterwards, this is what
                // the call itself returned.
                Marshal.SetLastPInvokeError(5);
                return captured;
            },
            (_, _, _, _) => NativeCallOutcome.Ok);

        Assert.Equal(NativeProbeState.SharingViolation, outcome.State);
        Assert.Equal(32, outcome.Win32ErrorCode);
    }

    /// <summary>The same, through the real Win32 call rather than a seam.</summary>
    [WindowsFact]
    public void ARealFailingProbeKeepsItsOwnError()
    {
        var missingFile = NativeCandidateProbe.Probe(Path.Combine(_root, "codex.exe"));
        var missingDirectory = NativeCandidateProbe.Probe(
            Path.Combine(_root, "no-such-folder", "codex.exe"));

        // Everything since has had a chance to set a different last error.
        Marshal.SetLastPInvokeError(0);
        _ = File.Exists(Path.Combine(_root, "unrelated"));

        Assert.Equal(NativeProbeState.FileNotFound, missingFile.State);
        Assert.Equal(2, missingFile.Win32ErrorCode);
        Assert.Equal(HandleProbeState.NotFound, missingFile.HandleState);

        Assert.Equal(NativeProbeState.PathNotFound, missingDirectory.State);
        Assert.Equal(3, missingDirectory.Win32ErrorCode);
    }

    [WindowsFact]
    public void ASucceedingProbeCarriesNoErrorCode()
    {
        var path = Path.Combine(_root, "codex.exe");
        File.WriteAllText(path, "stub");

        var outcome = NativeCandidateProbe.Probe(path);

        Assert.Equal(NativeProbeState.Exists, outcome.State);
        Assert.Null(outcome.Win32ErrorCode);
        Assert.Equal(HandleProbeState.Opened, outcome.HandleState);
    }

    [WindowsFact]
    public void NoCandidatePathMeansNoProbeAtAll()
    {
        foreach (var empty in new string?[] { null, "", "   " })
        {
            var outcome = NativeCandidateProbe.Probe(empty);

            Assert.Equal(NativeProbeState.NotConstructed, outcome.State);
            Assert.Null(outcome.Win32ErrorCode);
            Assert.Equal(HandleProbeState.NotAttempted, outcome.HandleState);
        }
    }

    // MARK: - What the probe is allowed to ask for

    /// <summary>
    /// The handle probe asks for the least that can answer the question:
    /// attributes only, shared with every reader, writer and deleter, and never
    /// creating anything. It cannot read a byte and cannot start the file.
    /// </summary>
    [WindowsFact]
    public void TheHandleProbeAsksForAttributesOnlyAndSharesWithEveryone()
    {
        uint access = 0;
        uint share = 0;
        uint disposition = 0;

        NativeCandidateProbe.Probe(
            @"C:\candidate.exe",
            _ => NativeCallOutcome.Ok,
            (_, desiredAccess, shareMode, creationDisposition) =>
            {
                access = desiredAccess;
                share = shareMode;
                disposition = creationDisposition;
                return NativeCallOutcome.Ok;
            });

        Assert.Equal(NativeCandidateProbe.FileReadAttributes, access);
        Assert.Equal(NativeCandidateProbe.FileShareAll, share);
        Assert.Equal(
            NativeCandidateProbe.FileShareRead |
            NativeCandidateProbe.FileShareWrite |
            NativeCandidateProbe.FileShareDelete,
            share);
        Assert.Equal(NativeCandidateProbe.OpenExisting, disposition);

        // Nothing that could read, write or run the file is requested.
        const uint genericRead = 0x80000000;
        const uint genericWrite = 0x40000000;
        const uint genericExecute = 0x20000000;
        const uint fileReadData = 0x0001;
        const uint fileWriteData = 0x0002;
        const uint fileExecute = 0x0020;

        foreach (var forbidden in new[]
                 {
                     genericRead, genericWrite, genericExecute, fileReadData, fileWriteData, fileExecute
                 })
        {
            Assert.Equal(0u, access & forbidden);
        }
    }

    /// <summary>
    /// Probing leaves the candidate exactly as it was, and learns nothing from
    /// inside it.
    /// </summary>
    [WindowsFact]
    public void TheProbesNeitherRunNorReadNorChangeTheCandidate()
    {
        const string sentinel = "usagebar-sentinel-do-not-read";
        var path = Path.Combine(_root, "codex.exe");
        File.WriteAllText(path, sentinel);

        var before = File.GetLastWriteTimeUtc(path);
        var bytes = File.ReadAllBytes(path);

        var outcome = NativeCandidateProbe.Probe(path);
        var managed = CandidateProbe.Probe(path);

        Assert.Equal(NativeProbeState.Exists, outcome.State);
        Assert.Equal(CandidateProbeState.Exists, managed);

        Assert.Equal(bytes, File.ReadAllBytes(path));
        Assert.Equal(before, File.GetLastWriteTimeUtc(path));

        // Nothing derived from the contents can be in the result, because the
        // result is a fixed classification and a number.
        Assert.DoesNotContain(sentinel, outcome.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(path, outcome.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    // MARK: - Token classification

    [WindowsFact]
    public void TheTokenProfileIsComparedWithoutEitherPathLeaving()
    {
        var profile = Path.Combine(_root, "Profile");
        var other = Path.Combine(_root, "Other");
        Directory.CreateDirectory(profile);
        Directory.CreateDirectory(other);

        Assert.Equal(
            TokenProfileRelation.MatchesResolvedProfile,
            ProcessTokenInspector.ProfileRelationFrom(profile, new[] { profile }));

        // A trailing separator and a different case are the same folder.
        Assert.Equal(
            TokenProfileRelation.MatchesResolvedProfile,
            ProcessTokenInspector.ProfileRelationFrom(
                profile.ToUpperInvariant() + Path.DirectorySeparatorChar,
                new[] { profile }));

        // The case that would explain everything: the process's own profile is
        // not the one discovery is searching.
        Assert.Equal(
            TokenProfileRelation.DiffersFromResolvedProfile,
            ProcessTokenInspector.ProfileRelationFrom(other, new[] { profile }));

        Assert.Equal(
            TokenProfileRelation.Unknown,
            ProcessTokenInspector.ProfileRelationFrom(null, new[] { profile }));
        Assert.Equal(
            TokenProfileRelation.Unknown,
            ProcessTokenInspector.ProfileRelationFrom("   ", new[] { profile }));
        Assert.Equal(
            TokenProfileRelation.Unknown,
            ProcessTokenInspector.ProfileRelationFrom(profile, Array.Empty<string>()));
    }

    [WindowsTheory]
    [InlineData(0x0000u, TokenIntegrity.Low)]
    [InlineData(0x1000u, TokenIntegrity.Low)]
    [InlineData(0x1FFFu, TokenIntegrity.Low)]
    [InlineData(0x2000u, TokenIntegrity.Medium)]
    [InlineData(0x2100u, TokenIntegrity.Medium)]
    [InlineData(0x3000u, TokenIntegrity.High)]
    [InlineData(0x4000u, TokenIntegrity.System)]
    [InlineData(0x5000u, TokenIntegrity.System)]
    public void EveryIntegrityLevelIsClassified(uint rid, TokenIntegrity expected)
    {
        Assert.Equal(expected, ProcessTokenInspector.IntegrityFrom(rid));
    }

    [WindowsFact]
    public void AnUnreadableIntegrityLevelIsUnknownRatherThanGuessed()
    {
        Assert.Equal(TokenIntegrity.Unknown, ProcessTokenInspector.IntegrityFrom(null));
    }

    [WindowsTheory]
    [InlineData(1u, TokenElevation.Default)]
    [InlineData(2u, TokenElevation.Full)]
    [InlineData(3u, TokenElevation.Limited)]
    [InlineData(0u, TokenElevation.Unknown)]
    [InlineData(99u, TokenElevation.Unknown)]
    public void EveryElevationTypeIsClassified(uint elevationType, TokenElevation expected)
    {
        Assert.Equal(expected, ProcessTokenInspector.ElevationFrom(elevationType));
    }

    [WindowsFact]
    public void AnUnreadableElevationTypeIsUnknownRatherThanGuessed()
    {
        Assert.Equal(TokenElevation.Unknown, ProcessTokenInspector.ElevationFrom(null));
    }

    /// <summary>
    /// Restriction and app-container membership are the two token properties that
    /// can silently change what the filesystem answers.
    /// </summary>
    [WindowsFact]
    public void RestrictedAndAppContainerAreThreeStatedNotTwo()
    {
        Assert.Equal(TokenFlagState.Yes, ProcessTokenInspector.FlagFrom(true));
        Assert.Equal(TokenFlagState.No, ProcessTokenInspector.FlagFrom(false));

        // Failing to read a flag must never read as "no".
        Assert.Equal(TokenFlagState.Unknown, ProcessTokenInspector.FlagFrom(null));
    }

    [WindowsFact]
    public void TheSessionIsComparedWithTheActiveConsoleWithoutEmittingEither()
    {
        Assert.Equal(SessionRelation.ActiveConsole, ProcessTokenInspector.SessionFrom(1, 1));
        Assert.Equal(SessionRelation.Other, ProcessTokenInspector.SessionFrom(2, 1));
        Assert.Equal(SessionRelation.Unknown, ProcessTokenInspector.SessionFrom(null, 1));
        Assert.Equal(SessionRelation.Unknown, ProcessTokenInspector.SessionFrom(1, null));

        // No console session to compare against.
        Assert.Equal(SessionRelation.Unknown, ProcessTokenInspector.SessionFrom(1, uint.MaxValue));
    }

    /// <summary>
    /// Reading the real token must produce a usable classification and must not
    /// throw, whatever this machine happens to be.
    /// </summary>
    [WindowsFact]
    public void TheRealTokenClassifiesWithoutThrowing()
    {
        var snapshot = ProcessTokenInspector.Classify(
            ProcessTokenInspector.Current(),
            Array.Empty<string>());

        Assert.Contains(snapshot.Integrity, Enum.GetValues<TokenIntegrity>());
        Assert.Contains(snapshot.Elevation, Enum.GetValues<TokenElevation>());
        Assert.Contains(snapshot.Restricted, Enum.GetValues<TokenFlagState>());
        Assert.Contains(snapshot.AppContainer, Enum.GetValues<TokenFlagState>());
        Assert.Contains(snapshot.SessionRelation, Enum.GetValues<SessionRelation>());

        // With no resolved profile to compare against there is no relation.
        Assert.Equal(TokenProfileRelation.Unknown, snapshot.ProfileRelation);

        // A CI runner is a real logged-on account, so this much should hold.
        Assert.NotEqual(TokenIntegrity.Unknown, snapshot.Integrity);
        Assert.NotEqual(TokenElevation.Unknown, snapshot.Elevation);
    }

    /// <summary>
    /// Nothing identifying survives classification — not a SID, not the account
    /// name, not the profile path.
    /// </summary>
    [WindowsFact]
    public void ClassifyingTheTokenKeepsEveryIdentifyingValueInside()
    {
        var raw = ProcessTokenInspector.Current();
        var snapshot = ProcessTokenInspector.Classify(raw, Array.Empty<string>());
        var reported = snapshot.ToString();

        Assert.DoesNotContain("S-1-", reported, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(":\\", reported, StringComparison.Ordinal);
        Assert.DoesNotContain(Environment.UserName, reported, StringComparison.OrdinalIgnoreCase);

        if (raw.ProfileDirectory is { Length: > 0 } profile)
        {
            Assert.DoesNotContain(profile, reported, StringComparison.OrdinalIgnoreCase);
        }
    }
}
