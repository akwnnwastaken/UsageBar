using System.Runtime.Versioning;

namespace UsageBar.Windows.Infrastructure.Startup;

/// <summary>
/// Ensures only one UsageBar runs per signed-in user.
///
/// A second launch must not add a second tray icon, and an installer replacing
/// the application must be able to tell whether it is running. Both are answered
/// by one named mutex in the <c>Local\</c> namespace, which is per-session: two
/// users signed in at once each get their own UsageBar, as they should.
///
/// The name is also what the installer waits on (Inno Setup's <c>AppMutex</c>),
/// so a running instance is asked to close rather than found by process name —
/// killing by name could hit an unrelated process that happens to share it.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class SingleInstanceGuard : IDisposable
{
    /// <summary>
    /// The mutex the installer also checks. Changing it would silently break
    /// the installer's "please close UsageBar" prompt, so it is a contract.
    /// </summary>
    public const string DefaultName = @"Local\UsageBar.Windows.SingleInstance";

    private Mutex? _mutex;
    private bool _disposed;

    private SingleInstanceGuard(Mutex? mutex, bool isOnlyInstance)
    {
        _mutex = mutex;
        IsOnlyInstance = isOnlyInstance;
    }

    /// <summary>True when this process is the one that should run.</summary>
    public bool IsOnlyInstance { get; }

    /// <summary>
    /// Tries to become the single instance. A guard that did not win still
    /// needs disposing; it simply owns nothing.
    /// </summary>
    public static SingleInstanceGuard Acquire(string? name = null)
    {
        var mutexName = name ?? DefaultName;

        try
        {
            var mutex = new Mutex(initiallyOwned: true, mutexName, out var createdNew);
            if (createdNew)
            {
                return new SingleInstanceGuard(mutex, isOnlyInstance: true);
            }

            // Someone else holds it: release our handle and stand down.
            mutex.Dispose();
            return new SingleInstanceGuard(mutex: null, isOnlyInstance: false);
        }
        catch (Exception exception) when (
            exception is UnauthorizedAccessException or IOException or WaitHandleCannotBeOpenedException)
        {
            // The mutex exists but this process cannot open it — another
            // session or a policy. Treat that as "not the only instance"
            // rather than starting a second tray icon.
            return new SingleInstanceGuard(mutex: null, isOnlyInstance: false);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        var mutex = Interlocked.Exchange(ref _mutex, null);
        if (mutex is null)
        {
            return;
        }

        try
        {
            if (IsOnlyInstance)
            {
                mutex.ReleaseMutex();
            }
        }
        catch (Exception exception) when (
            exception is ApplicationException or ObjectDisposedException)
        {
            // Already released, or the process is tearing down.
        }
        finally
        {
            mutex.Dispose();
        }
    }
}
