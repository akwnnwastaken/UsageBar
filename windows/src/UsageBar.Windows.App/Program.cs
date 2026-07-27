using System.Runtime.Versioning;
using UsageBar.Windows.Infrastructure.Startup;

namespace UsageBar.Windows.App;

/// <summary>
/// Entry point. The project is built as WinExe, so no console window is ever
/// created, and a per-user single-instance guard keeps a second launch — or a
/// relaunch straight after an upgrade — from adding a duplicate tray icon.
/// </summary>
[SupportedOSPlatform("windows")]
internal static class Program
{
    [STAThread]
    internal static int Main()
    {
        using var singleInstance = SingleInstanceGuard.Acquire();
        if (!singleInstance.IsOnlyInstance)
        {
            // Already running: the existing tray icon is the one to use.
            return 0;
        }

        var application = new TrayApplication();
        return application.Run();
    }
}
