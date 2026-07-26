using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using UsageBar.Windows.Infrastructure.Native;

namespace UsageBar.Windows.Infrastructure.Process;

/// <summary>
/// A Job Object with kill-on-job-close semantics.
///
/// This is how UsageBar guarantees that a provider refresh leaves nothing
/// behind. A provider CLI may spawn Node, a shell or a WSL relay of its own;
/// terminating only the process UsageBar started would orphan those children.
/// Every process the provider creates inherits the job, so closing the job
/// handle — on timeout, on cancellation, or when UsageBar exits — terminates the
/// complete tree in one operation.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class JobObject : IDisposable
{
    private readonly SafeJobObjectHandle _handle;
    private bool _disposed;

    private JobObject(SafeJobObjectHandle handle) => _handle = handle;

    public static JobObject CreateKillOnClose()
    {
        var handle = NativeMethods.CreateJobObject(IntPtr.Zero, null);
        if (handle.IsInvalid)
        {
            throw new InvalidOperationException(
                $"CreateJobObject failed ({Marshal.GetLastWin32Error()}).");
        }

        var job = new JobObject(handle);
        try
        {
            job.ConfigureKillOnClose();
            return job;
        }
        catch
        {
            job.Dispose();
            throw;
        }
    }

    private void ConfigureKillOnClose()
    {
        var information = new NativeMethods.JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            BasicLimitInformation = new NativeMethods.JOBOBJECT_BASIC_LIMIT_INFORMATION
            {
                // Kill on close is the containment guarantee. Die-on-unhandled-
                // exception additionally suppresses the Windows Error Reporting
                // dialog a crashing provider would otherwise pop up.
                LimitFlags = NativeMethods.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE |
                             NativeMethods.JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION
            }
        };

        var size = Marshal.SizeOf<NativeMethods.JOBOBJECT_EXTENDED_LIMIT_INFORMATION>();
        var buffer = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(information, buffer, fDeleteOld: false);
            if (!NativeMethods.SetInformationJobObject(
                    _handle,
                    NativeMethods.JobObjectExtendedLimitInformation,
                    buffer,
                    (uint)size))
            {
                throw new InvalidOperationException(
                    $"SetInformationJobObject failed ({Marshal.GetLastWin32Error()}).");
            }
        }
        finally
        {
            Marshal.DestroyStructure<NativeMethods.JOBOBJECT_EXTENDED_LIMIT_INFORMATION>(buffer);
            Marshal.FreeHGlobal(buffer);
        }
    }

    /// <summary>
    /// Assigns a process to the job. The caller must only resume the process
    /// after this succeeds — a process that ran before assignment could have
    /// spawned children outside the job.
    /// </summary>
    public void Assign(IntPtr processHandle)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        if (!NativeMethods.AssignProcessToJobObject(_handle, processHandle))
        {
            throw new InvalidOperationException(
                $"AssignProcessToJobObject failed ({Marshal.GetLastWin32Error()}).");
        }
    }

    /// <summary>Terminates every process in the job immediately.</summary>
    public void Terminate()
    {
        if (_disposed || _handle.IsInvalid || _handle.IsClosed)
        {
            return;
        }

        NativeMethods.TerminateJobObject(_handle, 1);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        // Closing the handle is what kills the tree; terminate first so the
        // outcome does not depend on other handles the provider may have leaked.
        Terminate();
        _handle.Dispose();
    }
}
