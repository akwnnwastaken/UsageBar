using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;
using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Discovery;

/// <summary>
/// What one direct Win32 call returned: whether it succeeded, and if not, the
/// error captured at the call site.
/// </summary>
internal readonly record struct NativeCallOutcome(bool Succeeded, int ErrorCode)
{
    public static NativeCallOutcome Ok { get; } = new(true, 0);

    public static NativeCallOutcome Failed(int errorCode) => new(false, errorCode);
}

/// <summary>
/// A direct Win32 metadata probe of a documented candidate.
///
/// The managed probe reported <c>io_error</c> for the official Codex candidate in
/// a Setup-launched session and <c>exists</c> from the Start Menu, on the same
/// file a minute apart. That is as far as the framework can take it: .NET folds
/// sharing violations, lock violations, reparse faults and cloud-provider faults
/// into one <c>IOException</c>, and <c>File.Exists</c> — which is what
/// <c>ExecutableTrust</c> reaches first — folds that into <c>false</c>. Discovery
/// then reports the provider missing without ever validating anything.
///
/// So the Win32 error is taken directly, at the call site, before anything else
/// can overwrite it.
///
/// The probe does not execute the file, read its contents, or modify it, and it
/// grants no trust: <c>ExecutableTrust</c> remains the only thing that may accept
/// an executable. Nothing but a fixed classification and a numeric error code
/// leaves this type — no path, no identity, no formatted message.
/// </summary>
[SupportedOSPlatform("windows")]
internal static class NativeCandidateProbe
{
    // Win32 errors this maps by name. Anything else is reported as other_error
    // with its number intact, which is the value that actually decides things.
    private const int ErrorFileNotFound = 2;
    private const int ErrorPathNotFound = 3;
    private const int ErrorAccessDenied = 5;
    private const int ErrorInvalidDrive = 15;
    private const int ErrorNotReady = 21;
    private const int ErrorCrc = 23;
    private const int ErrorGeneralFailure = 31;
    private const int ErrorSharingViolation = 32;
    private const int ErrorLockViolation = 33;
    private const int ErrorReparse = 741;
    private const int ErrorIoDevice = 1117;
    private const int ErrorCantAccessFile = 1920;
    private const int ErrorCantResolveFilename = 1921;

    /// <summary>Reparse-point faults: 4390 through 4394 in winerror.h.</summary>
    private const int ReparseBlockFirst = 4390;
    private const int ReparseBlockLast = 4394;

    /// <summary>
    /// The cloud-files blocks in winerror.h. A placeholder that a sync provider
    /// cannot currently materialise fails in here, which looks identical to a
    /// missing file through the framework.
    /// </summary>
    private const int CloudBlockFirstLow = 362;
    private const int CloudBlockLastLow = 367;
    private const int CloudBlockFirstHigh = 395;
    private const int CloudBlockLastHigh = 417;

    // CreateFileW arguments. Deliberately the smallest thing that can answer the
    // question: attributes only, sharing with everyone, never creating.
    internal const uint FileReadAttributes = 0x0080;
    internal const uint FileShareRead = 0x00000001;
    internal const uint FileShareWrite = 0x00000002;
    internal const uint FileShareDelete = 0x00000004;
    internal const uint FileShareAll = FileShareRead | FileShareWrite | FileShareDelete;
    internal const uint OpenExisting = 3;

    private const int GetFileExInfoStandard = 0;

    /// <summary>
    /// Probes the candidate with <c>GetFileAttributesExW</c> and, separately,
    /// with a metadata-only <c>CreateFileW</c>.
    /// </summary>
    internal static NativeProbeOutcome Probe(string? path) =>
        Probe(path, QueryAttributes, OpenForAttributes);

    internal static NativeProbeOutcome Probe(
        string? path,
        Func<string, NativeCallOutcome> queryAttributes,
        Func<string, uint, uint, uint, NativeCallOutcome> openForAttributes)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return NativeProbeOutcome.NotConstructed;
        }

        var attributes = queryAttributes(path);

        // The attribute query and the open take different routes through the
        // filter stack, so both are asked even when the first one answered.
        var handle = openForAttributes(path, FileReadAttributes, FileShareAll, OpenExisting);

        return new NativeProbeOutcome(
            ClassifyAttributes(attributes),
            attributes.Succeeded ? null : attributes.ErrorCode,
            ClassifyHandle(handle));
    }

    internal static NativeProbeState ClassifyAttributes(NativeCallOutcome outcome)
    {
        if (outcome.Succeeded)
        {
            return NativeProbeState.Exists;
        }

        return outcome.ErrorCode switch
        {
            ErrorFileNotFound => NativeProbeState.FileNotFound,
            ErrorPathNotFound => NativeProbeState.PathNotFound,
            ErrorAccessDenied => NativeProbeState.AccessDenied,
            ErrorSharingViolation => NativeProbeState.SharingViolation,
            ErrorLockViolation => NativeProbeState.LockViolation,
            ErrorCantAccessFile => NativeProbeState.CantAccessFile,
            ErrorReparse or ErrorCantResolveFilename => NativeProbeState.ReparseError,
            >= ReparseBlockFirst and <= ReparseBlockLast => NativeProbeState.ReparseError,
            >= CloudBlockFirstLow and <= CloudBlockLastLow => NativeProbeState.CloudUnavailable,
            >= CloudBlockFirstHigh and <= CloudBlockLastHigh => NativeProbeState.CloudUnavailable,
            ErrorInvalidDrive or ErrorNotReady or ErrorCrc or ErrorGeneralFailure or ErrorIoDevice =>
                NativeProbeState.DeviceError,
            _ => NativeProbeState.OtherError
        };
    }

    internal static HandleProbeState ClassifyHandle(NativeCallOutcome outcome)
    {
        if (outcome.Succeeded)
        {
            return HandleProbeState.Opened;
        }

        return outcome.ErrorCode switch
        {
            ErrorFileNotFound or ErrorPathNotFound => HandleProbeState.NotFound,
            ErrorAccessDenied => HandleProbeState.AccessDenied,
            ErrorSharingViolation or ErrorLockViolation => HandleProbeState.SharingViolation,
            ErrorReparse or ErrorCantResolveFilename => HandleProbeState.ReparseError,
            >= ReparseBlockFirst and <= ReparseBlockLast => HandleProbeState.ReparseError,
            _ => HandleProbeState.OtherError
        };
    }

    /// <summary>
    /// <c>GetFileAttributesExW</c>, with the error read on the next statement.
    /// Nothing runs in between that could replace it.
    /// </summary>
    private static NativeCallOutcome QueryAttributes(string path)
    {
        try
        {
            var succeeded = GetFileAttributesExW(path, GetFileExInfoStandard, out _);
            var error = Marshal.GetLastPInvokeError();

            return succeeded ? NativeCallOutcome.Ok : NativeCallOutcome.Failed(error);
        }
        catch (Exception exception) when (
            exception is DllNotFoundException or EntryPointNotFoundException)
        {
            return NativeCallOutcome.Failed(0);
        }
    }

    /// <summary>
    /// A metadata-only open: attributes only, shared with every writer and
    /// deleter, never creating anything. It cannot read a byte of the file and
    /// cannot start it, and the handle is closed immediately.
    /// </summary>
    private static NativeCallOutcome OpenForAttributes(
        string path,
        uint desiredAccess,
        uint shareMode,
        uint creationDisposition)
    {
        SafeFileHandle? handle = null;
        try
        {
            handle = CreateFileW(
                path,
                desiredAccess,
                shareMode,
                IntPtr.Zero,
                creationDisposition,
                0,
                IntPtr.Zero);
            var error = Marshal.GetLastPInvokeError();

            return handle.IsInvalid ? NativeCallOutcome.Failed(error) : NativeCallOutcome.Ok;
        }
        catch (Exception exception) when (
            exception is DllNotFoundException or EntryPointNotFoundException)
        {
            return NativeCallOutcome.Failed(0);
        }
        finally
        {
            handle?.Dispose();
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Win32FileAttributeData
    {
        public uint FileAttributes;
        public uint CreationTimeLow;
        public uint CreationTimeHigh;
        public uint LastAccessTimeLow;
        public uint LastAccessTimeHigh;
        public uint LastWriteTimeLow;
        public uint LastWriteTimeHigh;
        public uint FileSizeHigh;
        public uint FileSizeLow;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileAttributesExW(
        string fileName,
        int infoLevelId,
        out Win32FileAttributeData fileInformation);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);
}
