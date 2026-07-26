using System.Runtime.Versioning;
using System.Threading;

namespace UsageBar.Windows.App;

/// <summary>
/// Entry point. The project is built as WinExe, so no console window is ever
/// created, and a single-instance mutex keeps a second launch from adding a
/// duplicate tray icon.
/// </summary>
[SupportedOSPlatform("windows")]
internal static class Program
{
    private const string SingleInstanceName = @"Local\UsageBar.Windows.SingleInstance";

    [STAThread]
    internal static int Main()
    {
        using var singleInstance = new Mutex(initiallyOwned: true, SingleInstanceName, out var isFirstInstance);
        if (!isFirstInstance)
        {
            // Already running: the existing tray icon is the one to use.
            return 0;
        }

        try
        {
            var application = new TrayApplication();
            return application.Run();
        }
        finally
        {
            singleInstance.ReleaseMutex();
        }
    }
}
