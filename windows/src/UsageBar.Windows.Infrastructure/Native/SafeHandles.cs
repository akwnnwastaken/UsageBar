using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;

namespace UsageBar.Windows.Infrastructure.Native;

/// <summary>
/// Job Object handle. Closing the last handle to a job configured with
/// kill-on-job-close terminates every process still inside it, so disposal is
/// the tear-down mechanism — not a best-effort cleanup.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class SafeJobObjectHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    public SafeJobObjectHandle()
        : base(ownsHandle: true)
    {
    }

    internal SafeJobObjectHandle(IntPtr existingHandle, bool ownsHandle)
        : base(ownsHandle)
    {
        SetHandle(existingHandle);
    }

    protected override bool ReleaseHandle() => NativeMethods.CloseHandle(handle);
}

/// <summary>Process handle returned by CreateProcessW.</summary>
[SupportedOSPlatform("windows")]
internal sealed class SafeProcessHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    public SafeProcessHandle()
        : base(ownsHandle: true)
    {
    }

    internal SafeProcessHandle(IntPtr existingHandle, bool ownsHandle)
        : base(ownsHandle)
    {
        SetHandle(existingHandle);
    }

    protected override bool ReleaseHandle() => NativeMethods.CloseHandle(handle);
}

/// <summary>Primary thread handle, kept only long enough to resume the process.</summary>
[SupportedOSPlatform("windows")]
internal sealed class SafeThreadHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    public SafeThreadHandle()
        : base(ownsHandle: true)
    {
    }

    internal SafeThreadHandle(IntPtr existingHandle, bool ownsHandle)
        : base(ownsHandle)
    {
        SetHandle(existingHandle);
    }

    protected override bool ReleaseHandle() => NativeMethods.CloseHandle(handle);
}

/// <summary>
/// Owns the unmanaged buffer backing a PROC_THREAD_ATTRIBUTE_LIST. The list must
/// be deleted before its memory is freed, which is exactly what this guarantees
/// even if process creation throws.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class SafeProcThreadAttributeList : SafeHandleZeroOrMinusOneIsInvalid
{
    private SafeProcThreadAttributeList(IntPtr buffer)
        : base(ownsHandle: true)
    {
        SetHandle(buffer);
    }

    /// <summary>
    /// Builds an attribute list that restricts handle inheritance to exactly the
    /// supplied handles, so a provider process can never inherit an unrelated
    /// handle UsageBar happens to hold.
    /// </summary>
    public static SafeProcThreadAttributeList CreateHandleList(IReadOnlyList<IntPtr> handles)
    {
        ArgumentNullException.ThrowIfNull(handles);

        var size = IntPtr.Zero;
        NativeMethods.InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
        if (size == IntPtr.Zero)
        {
            throw new InvalidOperationException("Could not size the process attribute list.");
        }

        var buffer = Marshal.AllocHGlobal(size);
        var list = new SafeProcThreadAttributeList(buffer);
        try
        {
            if (!NativeMethods.InitializeProcThreadAttributeList(buffer, 1, 0, ref size))
            {
                throw new InvalidOperationException(
                    $"InitializeProcThreadAttributeList failed ({Marshal.GetLastWin32Error()}).");
            }

            list._initialized = true;

            var handleArray = handles.ToArray();
            list._handleBuffer = Marshal.AllocHGlobal(IntPtr.Size * handleArray.Length);
            Marshal.Copy(handleArray, 0, list._handleBuffer, handleArray.Length);

            if (!NativeMethods.UpdateProcThreadAttribute(
                    buffer,
                    0,
                    NativeMethods.PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                    list._handleBuffer,
                    IntPtr.Size * handleArray.Length,
                    IntPtr.Zero,
                    IntPtr.Zero))
            {
                throw new InvalidOperationException(
                    $"UpdateProcThreadAttribute failed ({Marshal.GetLastWin32Error()}).");
            }

            return list;
        }
        catch
        {
            list.Dispose();
            throw;
        }
    }

    private bool _initialized;
    private IntPtr _handleBuffer;

    protected override bool ReleaseHandle()
    {
        if (_initialized)
        {
            NativeMethods.DeleteProcThreadAttributeList(handle);
        }

        if (_handleBuffer != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(_handleBuffer);
            _handleBuffer = IntPtr.Zero;
        }

        Marshal.FreeHGlobal(handle);
        return true;
    }
}
