using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Discovery;

/// <summary>
/// A bounded, non-executing metadata probe used only to explain a discovery
/// result.
///
/// <see cref="File.Exists(string)"/> is deliberately not used: it answers false
/// for a file that is there but unreadable, which is exactly the ambiguity the
/// physical investigation is stuck on. Reading the attributes instead separates
/// "not there" from "there but refused" from "the volume failed".
///
/// The probe reads one set of file attributes. It never opens the file, never
/// reads its contents, never starts it, does not follow links and does not
/// consult ACLs — <see cref="ExecutableTrust"/> remains the only thing that may
/// accept an executable, and nothing here can make a candidate trusted.
///
/// Failures collapse to a fixed classification, so no path, Win32 message,
/// exception text or user name can escape through the result.
/// </summary>
[SupportedOSPlatform("windows")]
internal static class CandidateProbe
{
    internal static CandidateProbeState Probe(string? path) => Probe(path, File.GetAttributes);

    internal static CandidateProbeState Probe(string? path, Func<string, FileAttributes> readAttributes)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return CandidateProbeState.InvalidRoot;
        }

        try
        {
            // A directory sitting where the executable should be is not the file
            // being looked for, and reports as absent rather than as a fault.
            return readAttributes(path).HasFlag(FileAttributes.Directory)
                ? CandidateProbeState.NotFound
                : CandidateProbeState.Exists;
        }
        catch (Exception exception) when (
            exception is FileNotFoundException or DirectoryNotFoundException)
        {
            return CandidateProbeState.NotFound;
        }
        catch (Exception exception) when (
            exception is UnauthorizedAccessException or System.Security.SecurityException)
        {
            return CandidateProbeState.AccessDenied;
        }
        catch (Exception exception) when (
            exception is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return CandidateProbeState.InvalidRoot;
        }
        catch (IOException)
        {
            return CandidateProbeState.IoError;
        }
    }

    /// <summary>
    /// Combines probes of several roots into one reported state. A real fault
    /// outranks a plain absence, so one root that is simply not there cannot
    /// hide another that refused access.
    /// </summary>
    internal static CandidateProbeState Merge(CandidateProbeState current, CandidateProbeState next) =>
        Rank(next) > Rank(current) ? next : current;

    private static int Rank(CandidateProbeState state) => state switch
    {
        CandidateProbeState.Exists => 4,
        CandidateProbeState.AccessDenied => 3,
        CandidateProbeState.IoError => 2,
        CandidateProbeState.InvalidRoot => 1,
        _ => 0
    };
}
