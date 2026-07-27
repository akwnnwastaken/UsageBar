using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;
using Microsoft.Win32.SafeHandles;
using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Diagnostics;

/// <summary>
/// The raw token facts, before they are reduced to classifications. Nothing in
/// here reaches a report; it exists so the classification is a pure function that
/// can be tested against every value it has to tell apart.
/// </summary>
internal readonly record struct RawProcessToken(
    string? ProfileDirectory,
    uint? IntegrityRid,
    uint? ElevationType,
    bool? Restricted,
    bool? AppContainer,
    uint? SessionId,
    uint? ActiveConsoleSessionId)
{
    public static RawProcessToken Unavailable { get; } = new(null, null, null, null, null, null, null);
}

/// <summary>
/// Classifies the current process's security context.
///
/// A Setup-created process can carry a different token than a shell-created one —
/// a different profile, a lower integrity level, a restricting SID, an app
/// container — and any of those can change what the filesystem answers for the
/// same file. The Setup-launched session failed the official Codex candidate with
/// a live I/O error while the Start Menu session found it, so what the token is
/// stopped being a background detail.
///
/// Only classifications leave this type. SIDs, account names, session ids, token
/// handles and the profile path all stay inside it.
/// </summary>
[SupportedOSPlatform("windows")]
internal static class ProcessTokenInspector
{
    // SECURITY_MANDATORY_*_RID
    private const uint IntegrityLow = 0x1000;
    private const uint IntegrityMedium = 0x2000;
    private const uint IntegrityHigh = 0x3000;
    private const uint IntegritySystem = 0x4000;

    // TOKEN_ELEVATION_TYPE
    private const uint ElevationTypeDefault = 1;
    private const uint ElevationTypeFull = 2;
    private const uint ElevationTypeLimited = 3;

    // TOKEN_INFORMATION_CLASS
    private const int TokenSessionId = 12;
    private const int TokenElevationType = 18;
    private const int TokenIntegrityLevel = 25;
    private const int TokenIsAppContainer = 29;

    private const uint TokenQuery = 0x0008;
    private const int ErrorInsufficientBuffer = 122;

    /// <summary>
    /// Read once. Integrity, elevation, restriction, app container and session
    /// cannot change for the lifetime of a process, so re-reading them would
    /// answer the same thing at a cost.
    /// </summary>
    private static readonly Lazy<RawProcessToken> Cached = new(Read, isThreadSafe: true);

    internal static RawProcessToken Current() => Cached.Value;

    /// <summary>
    /// Reduces raw token facts to the reported states. The profile relation is
    /// computed against the roots the lookup actually resolved, so it answers
    /// "is this process's own profile the one discovery is searching" rather than
    /// anything about a particular machine.
    /// </summary>
    internal static ProcessTokenSnapshot Classify(
        RawProcessToken token,
        IReadOnlyList<string> resolvedProfiles) => new(
        ProfileRelationFrom(token.ProfileDirectory, resolvedProfiles),
        IntegrityFrom(token.IntegrityRid),
        ElevationFrom(token.ElevationType),
        FlagFrom(token.Restricted),
        FlagFrom(token.AppContainer),
        SessionFrom(token.SessionId, token.ActiveConsoleSessionId));

    internal static TokenProfileRelation ProfileRelationFrom(
        string? tokenProfile,
        IReadOnlyList<string> resolvedProfiles)
    {
        if (string.IsNullOrWhiteSpace(tokenProfile) || resolvedProfiles.Count == 0)
        {
            return TokenProfileRelation.Unknown;
        }

        string normalized;
        try
        {
            normalized = Path.GetFullPath(tokenProfile.Trim())
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }
        catch (Exception exception) when (
            exception is ArgumentException or NotSupportedException or PathTooLongException or IOException)
        {
            return TokenProfileRelation.Unknown;
        }

        return resolvedProfiles.Any(profile => string.Equals(
            profile.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            normalized,
            StringComparison.OrdinalIgnoreCase))
            ? TokenProfileRelation.MatchesResolvedProfile
            : TokenProfileRelation.DiffersFromResolvedProfile;
    }

    internal static TokenIntegrity IntegrityFrom(uint? rid) => rid switch
    {
        null => TokenIntegrity.Unknown,
        >= IntegritySystem => TokenIntegrity.System,
        >= IntegrityHigh => TokenIntegrity.High,
        >= IntegrityMedium => TokenIntegrity.Medium,
        _ => TokenIntegrity.Low
    };

    internal static TokenElevation ElevationFrom(uint? elevationType) => elevationType switch
    {
        ElevationTypeDefault => TokenElevation.Default,
        ElevationTypeFull => TokenElevation.Full,
        ElevationTypeLimited => TokenElevation.Limited,
        _ => TokenElevation.Unknown
    };

    internal static TokenFlagState FlagFrom(bool? value) => value switch
    {
        true => TokenFlagState.Yes,
        false => TokenFlagState.No,
        _ => TokenFlagState.Unknown
    };

    internal static SessionRelation SessionFrom(uint? sessionId, uint? activeConsoleSessionId)
    {
        if (sessionId is not { } session || activeConsoleSessionId is not { } console)
        {
            return SessionRelation.Unknown;
        }

        // 0xFFFFFFFF is what WTSGetActiveConsoleSessionId returns when there is
        // no console session to compare against.
        return console == uint.MaxValue
            ? SessionRelation.Unknown
            : session == console
                ? SessionRelation.ActiveConsole
                : SessionRelation.Other;
    }

    /// <summary>
    /// Reads the token. Every failure degrades to "unknown" rather than throwing:
    /// a diagnostic that cannot be gathered must not take the application with it.
    /// </summary>
    private static RawProcessToken Read()
    {
        try
        {
            if (!OpenProcessToken(GetCurrentProcess(), TokenQuery, out var token))
            {
                return RawProcessToken.Unavailable;
            }

            using (token)
            {
                return new RawProcessToken(
                    ProfileDirectory(token),
                    IntegrityRid(token),
                    Dword(token, TokenElevationType),
                    IsRestricted(token),
                    Dword(token, TokenIsAppContainer) is { } appContainer ? appContainer != 0 : null,
                    Dword(token, TokenSessionId),
                    ActiveConsoleSession());
            }
        }
        catch (Exception exception) when (
            exception is DllNotFoundException or EntryPointNotFoundException or OutOfMemoryException)
        {
            return RawProcessToken.Unavailable;
        }
    }

    private static string? ProfileDirectory(SafeAccessTokenHandle token)
    {
        try
        {
            uint length = 0;
            if (GetUserProfileDirectoryW(token, null, ref length))
            {
                return null;
            }

            if (Marshal.GetLastPInvokeError() != ErrorInsufficientBuffer || length == 0 || length > 32768)
            {
                return null;
            }

            var buffer = new StringBuilder((int)length);
            return GetUserProfileDirectoryW(token, buffer, ref length) ? buffer.ToString() : null;
        }
        catch (Exception exception) when (
            exception is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }
    }

    /// <summary>The last sub-authority of the token's integrity SID.</summary>
    private static uint? IntegrityRid(SafeAccessTokenHandle token)
    {
        var buffer = Query(token, TokenIntegrityLevel, out var size);
        if (buffer == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            if (size < IntPtr.Size)
            {
                return null;
            }

            // TOKEN_MANDATORY_LABEL begins with SID_AND_ATTRIBUTES, whose first
            // member is the PSID.
            var sid = Marshal.ReadIntPtr(buffer);
            if (sid == IntPtr.Zero)
            {
                return null;
            }

            var countPointer = GetSidSubAuthorityCount(sid);
            if (countPointer == IntPtr.Zero)
            {
                return null;
            }

            var count = Marshal.ReadByte(countPointer);
            if (count == 0)
            {
                return null;
            }

            var last = GetSidSubAuthority(sid, (uint)(count - 1));
            return last == IntPtr.Zero ? null : unchecked((uint)Marshal.ReadInt32(last));
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static uint? Dword(SafeAccessTokenHandle token, int informationClass)
    {
        var buffer = Query(token, informationClass, out var size);
        if (buffer == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            return size < sizeof(uint) ? null : unchecked((uint)Marshal.ReadInt32(buffer));
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static bool? IsRestricted(SafeAccessTokenHandle token)
    {
        try
        {
            return IsTokenRestricted(token);
        }
        catch (Exception exception) when (
            exception is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }
    }

    private static uint? ActiveConsoleSession()
    {
        try
        {
            return WTSGetActiveConsoleSessionId();
        }
        catch (Exception exception) when (
            exception is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }
    }

    /// <summary>Allocates and fills one token information buffer, or returns zero.</summary>
    private static IntPtr Query(SafeAccessTokenHandle token, int informationClass, out int size)
    {
        size = 0;
        try
        {
            GetTokenInformation(token, informationClass, IntPtr.Zero, 0, out var needed);
            if (needed <= 0 || needed > 65536)
            {
                return IntPtr.Zero;
            }

            var buffer = Marshal.AllocHGlobal(needed);
            if (GetTokenInformation(token, informationClass, buffer, needed, out _))
            {
                size = needed;
                return buffer;
            }

            Marshal.FreeHGlobal(buffer);
            return IntPtr.Zero;
        }
        catch (Exception exception) when (
            exception is DllNotFoundException or EntryPointNotFoundException or OutOfMemoryException)
        {
            return IntPtr.Zero;
        }
    }

    [DllImport("kernel32.dll", ExactSpelling = true)]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", ExactSpelling = true)]
    private static extern uint WTSGetActiveConsoleSessionId();

    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessToken(
        IntPtr processHandle,
        uint desiredAccess,
        out SafeAccessTokenHandle tokenHandle);

    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(
        SafeAccessTokenHandle tokenHandle,
        int tokenInformationClass,
        IntPtr tokenInformation,
        int tokenInformationLength,
        out int returnLength);

    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsTokenRestricted(SafeAccessTokenHandle tokenHandle);

    [DllImport("advapi32.dll", ExactSpelling = true)]
    private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);

    [DllImport("advapi32.dll", ExactSpelling = true)]
    private static extern IntPtr GetSidSubAuthority(IntPtr sid, uint subAuthority);

    [DllImport("userenv.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetUserProfileDirectoryW(
        SafeAccessTokenHandle token,
        StringBuilder? profileDirectory,
        ref uint size);
}
