using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using UsageBar.Windows.Infrastructure.Native;

namespace UsageBar.Windows.Infrastructure.Process;

/// <summary>
/// A running provider process together with everything that contains it: the
/// Job Object, the process handle and the three redirected pipes.
///
/// Disposal is the tear-down: closing the job terminates every process still in
/// it, so a timed-out or cancelled refresh cannot leave Codex, Claude, Node, a
/// shell or a WSL relay running.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class ProviderProcessSession : IDisposable
{
    private readonly JobObject _job;
    private readonly SafeProcessHandle _process;
    private bool _disposed;

    private ProviderProcessSession(
        JobObject job,
        SafeProcessHandle process,
        int processId,
        AnonymousPipeServerStream standardInput,
        AnonymousPipeServerStream standardOutput,
        AnonymousPipeServerStream standardError)
    {
        _job = job;
        _process = process;
        ProcessId = processId;
        StandardInput = standardInput;
        StandardOutput = standardOutput;
        StandardError = standardError;
    }

    public int ProcessId { get; }

    public AnonymousPipeServerStream StandardInput { get; }

    public AnonymousPipeServerStream StandardOutput { get; }

    public AnonymousPipeServerStream StandardError { get; }

    public bool HasExited =>
        NativeMethods.GetExitCodeProcess(_process, out var exitCode) && exitCode != NativeMethods.STILL_ACTIVE;

    public int ExitCode =>
        NativeMethods.GetExitCodeProcess(_process, out var exitCode) ? unchecked((int)exitCode) : 0;

    /// <summary>
    /// Starts the process suspended, contains it, then resumes it. The process
    /// never executes an instruction before it belongs to the job, so no child
    /// it spawns can escape containment.
    /// </summary>
    public static ProviderProcessSession Start(ProviderProcessRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        AnonymousPipeServerStream? standardInput = null;
        AnonymousPipeServerStream? standardOutput = null;
        AnonymousPipeServerStream? standardError = null;
        JobObject? job = null;

        try
        {
            standardInput = new AnonymousPipeServerStream(PipeDirection.Out, HandleInheritability.Inheritable);
            standardOutput = new AnonymousPipeServerStream(PipeDirection.In, HandleInheritability.Inheritable);
            standardError = new AnonymousPipeServerStream(PipeDirection.In, HandleInheritability.Inheritable);
            job = JobObject.CreateKillOnClose();

            var (process, processId) = CreateSuspendedProcess(
                request,
                job,
                standardInput,
                standardOutput,
                standardError);

            // The child owns its ends now; dropping our copies makes the child's
            // exit close the pipes so the readers observe end of stream.
            standardInput.DisposeLocalCopyOfClientHandle();
            standardOutput.DisposeLocalCopyOfClientHandle();
            standardError.DisposeLocalCopyOfClientHandle();

            return new ProviderProcessSession(
                job,
                process,
                processId,
                standardInput,
                standardOutput,
                standardError);
        }
        catch
        {
            job?.Dispose();
            standardInput?.Dispose();
            standardOutput?.Dispose();
            standardError?.Dispose();
            throw;
        }
    }

    /// <summary>
    /// Waits in short slices so cancellation and the deadline are honored without
    /// leaving a blocking wait behind.
    /// </summary>
    public async Task<bool> WaitForExitAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            var status = await Task.Run(
                () => NativeMethods.WaitForSingleObject(_process, 50),
                CancellationToken.None).ConfigureAwait(false);

            if (status == NativeMethods.WAIT_OBJECT_0)
            {
                return true;
            }

            if (status == NativeMethods.WAIT_FAILED)
            {
                return false;
            }
        }

        return false;
    }

    /// <summary>Terminates the whole tree without waiting for disposal.</summary>
    public void KillTree() => _job.Terminate();

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        // Closing the job is what kills the tree, so it goes first.
        _job.Dispose();
        _process.Dispose();
        StandardInput.Dispose();
        StandardOutput.Dispose();
        StandardError.Dispose();
    }

    private static (SafeProcessHandle Process, int ProcessId) CreateSuspendedProcess(
        ProviderProcessRequest request,
        JobObject job,
        AnonymousPipeServerStream standardInput,
        AnonymousPipeServerStream standardOutput,
        AnonymousPipeServerStream standardError)
    {
        var childStandardInput = standardInput.ClientSafePipeHandle.DangerousGetHandle();
        var childStandardOutput = standardOutput.ClientSafePipeHandle.DangerousGetHandle();
        var childStandardError = standardError.ClientSafePipeHandle.DangerousGetHandle();

        // Restricting inheritance to exactly these three handles means a provider
        // can never inherit an unrelated handle UsageBar happens to hold.
        using var attributes = SafeProcThreadAttributeList.CreateHandleList(new[]
        {
            childStandardInput,
            childStandardOutput,
            childStandardError
        });

        var startupInfo = new NativeMethods.STARTUPINFOEXW
        {
            StartupInfo = new NativeMethods.STARTUPINFOW
            {
                cb = Marshal.SizeOf<NativeMethods.STARTUPINFOEXW>(),
                dwFlags = NativeMethods.STARTF_USESTDHANDLES | NativeMethods.STARTF_USESHOWWINDOW,
                wShowWindow = NativeMethods.SW_HIDE,
                hStdInput = childStandardInput,
                hStdOutput = childStandardOutput,
                hStdError = childStandardError
            },
            lpAttributeList = attributes.DangerousGetHandle()
        };

        var commandLine = WindowsCommandLine.ToWritableBuffer(
            WindowsCommandLine.Build(request.ExecutablePath, request.Arguments));
        var environmentBlock = ProviderProcessEnvironment.ToEnvironmentBlock(
            ProviderProcessEnvironment.Build(request.AdditionalEnvironment));

        var environmentHandle = GCHandle.Alloc(environmentBlock, GCHandleType.Pinned);
        try
        {
            var created = NativeMethods.CreateProcess(
                request.ExecutablePath,
                commandLine,
                IntPtr.Zero,
                IntPtr.Zero,
                bInheritHandles: true,
                NativeMethods.CREATE_SUSPENDED |
                NativeMethods.CREATE_NO_WINDOW |
                NativeMethods.CREATE_UNICODE_ENVIRONMENT |
                NativeMethods.EXTENDED_STARTUPINFO_PRESENT,
                environmentHandle.AddrOfPinnedObject(),
                request.WorkingDirectory ?? ProviderProcessEnvironment.WorkingDirectory,
                ref startupInfo,
                out var information);

            if (!created)
            {
                throw new ProviderLaunchException(Marshal.GetLastWin32Error());
            }

            var process = new SafeProcessHandle(information.hProcess, ownsHandle: true);
            using var thread = new SafeThreadHandle(information.hThread, ownsHandle: true);

            try
            {
                job.Assign(information.hProcess);

                if (NativeMethods.ResumeThread(information.hThread) == unchecked((uint)-1))
                {
                    throw new ProviderLaunchException(Marshal.GetLastWin32Error());
                }

                return (process, information.dwProcessId);
            }
            catch
            {
                job.Terminate();
                process.Dispose();
                throw;
            }
        }
        finally
        {
            environmentHandle.Free();
        }
    }
}

/// <summary>A launch failure with its Win32 error code, never shown as user text.</summary>
public sealed class ProviderLaunchException : Exception
{
    public ProviderLaunchException(int errorCode)
        : base($"Win32 error {errorCode}")
        => ErrorCode = errorCode;

    public int ErrorCode { get; }
}
