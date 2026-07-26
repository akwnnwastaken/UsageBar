using System.Runtime.Versioning;
using System.Windows;
using System.Windows.Threading;
using UsageBar.Windows.App.Tray;
using UsageBar.Windows.App.Views;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Infrastructure.Providers;
using UsageBar.Windows.Infrastructure.Startup;
using UsageBar.Windows.Infrastructure.Storage;

namespace UsageBar.Windows.App;

/// <summary>
/// The tray-only application lifecycle.
///
/// There is no main window and no startup URI. Shutdown is explicit, so closing
/// the panel — or every window — never ends the process; only the Exit action
/// does. The refresh timer runs on the selected interval and the rotation timer
/// switches the displayed provider every 30 seconds without querying anything.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class TrayApplication : Application
{
    private UsageBarController? _controller;
    private TrayIconController? _tray;
    private UsagePanelWindow? _panel;
    private SettingsWindow? _settings;
    private DispatcherTimer? _refreshTimer;
    private DispatcherTimer? _rotationTimer;
    private bool _shuttingDown;

    public TrayApplication() => ShutdownMode = ShutdownMode.OnExplicitShutdown;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var storage = new UsageBarStorage();
        _controller = new UsageBarController(
            storage,
            new CodexUsageReader(),
            new RegistryAutoStartService(),
            PostToUiThread);

        _panel = new UsagePanelWindow(_controller);
        _panel.IsChildWindowActive = () => _settings?.IsVisible == true;
        _panel.SettingsRequested += (_, _) => ShowSettings();
        _panel.DiagnosticsRequested += (_, _) => CopyDiagnostics();
        _panel.ExitRequested += (_, _) => ExitApplication();

        _tray = new TrayIconController(_controller);
        _tray.ToggleRequested += (_, _) => TogglePanel();
        _tray.ShowRequested += (_, _) => ShowPanel();
        _tray.SettingsRequested += (_, _) => ShowSettings();
        _tray.ExitRequested += (_, _) => ExitApplication();

        _controller.Changed += OnControllerChanged;

        _tray.Show();
        _controller.Start();
        ConfigureTimers();

        // Only after the icon actually exists in the notification area, and
        // never as a modal dialog that would block startup.
        if (_tray.IsVisible)
        {
            _tray.ShowTrayGuidanceIfNeeded();
        }
    }

    /// <summary>
    /// Marshals a controller callback onto the UI thread. A refresh that is
    /// still in flight when the user quits must not throw on a dispatcher that
    /// has already begun shutting down.
    /// </summary>
    private void PostToUiThread(Action action)
    {
        if (_shuttingDown || Dispatcher.HasShutdownStarted || Dispatcher.HasShutdownFinished)
        {
            return;
        }

        try
        {
            Dispatcher.Invoke(action);
        }
        catch (TaskCanceledException)
        {
            // The dispatcher shut down between the check and the invoke.
        }
    }

    private void OnControllerChanged(object? sender, EventArgs e)
    {
        if (_shuttingDown)
        {
            return;
        }

        _tray?.Update();
        ConfigureTimers();

        if (_panel?.IsVisible == true)
        {
            _panel.Rebuild();
        }

        if (_settings?.IsVisible == true)
        {
            _settings.Rebuild();
        }
    }

    private void ConfigureTimers()
    {
        if (_controller is null)
        {
            return;
        }

        var interval = _controller.RefreshInterval.Duration();
        if (_refreshTimer is null)
        {
            _refreshTimer = new DispatcherTimer(DispatcherPriority.Background) { Interval = interval };
            _refreshTimer.Tick += (_, _) => _ = _controller.RefreshAsync();
            _refreshTimer.Start();
        }
        else if (_refreshTimer.Interval != interval)
        {
            _refreshTimer.Interval = interval;
        }

        // Rotation only makes sense with more than one connected provider.
        var shouldRotate = _controller.Settings.AutoRotateProviders &&
                           _controller.ConnectedProviderNames.Count > 1;

        if (shouldRotate && _rotationTimer is null)
        {
            _rotationTimer = new DispatcherTimer(DispatcherPriority.Background)
            {
                Interval = ProviderRotation.Interval
            };
            _rotationTimer.Tick += (_, _) => _controller.RotateProvider();
            _rotationTimer.Start();
        }
        else if (!shouldRotate && _rotationTimer is not null)
        {
            _rotationTimer.Stop();
            _rotationTimer = null;
        }
    }

    private void TogglePanel()
    {
        if (_panel is null)
        {
            return;
        }

        if (_panel.IsVisible)
        {
            _panel.Hide();
            return;
        }

        ShowPanel();
    }

    private void ShowPanel()
    {
        // Opening the panel refreshes only when what is on screen is older than
        // the 30-second staleness threshold.
        _controller?.RefreshIfStale();
        _panel?.ShowNearTray();
    }

    private void ShowSettings()
    {
        if (_controller is null || _panel is null)
        {
            return;
        }

        if (_settings is null)
        {
            _settings = new SettingsWindow(_controller, _panel);
            _settings.TrayGuidanceRequested += (_, _) => _tray?.ShowTrayGuidance();
            _settings.DiagnosticsRequested += (_, _) => CopyDiagnostics();
        }

        if (!_panel.IsVisible)
        {
            _panel.ShowNearTray();
        }

        _settings.ShowSettings();
    }

    private void CopyDiagnostics()
    {
        if (_controller is null)
        {
            return;
        }

        try
        {
            Clipboard.SetText(_controller.BuildDiagnostics());
        }
        catch (System.Runtime.InteropServices.ExternalException)
        {
            // Another process can hold the clipboard; losing a copy is harmless.
        }
    }

    private void ExitApplication()
    {
        _shuttingDown = true;
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _shuttingDown = true;
        _refreshTimer?.Stop();
        _rotationTimer?.Stop();

        if (_controller is not null)
        {
            _controller.Changed -= OnControllerChanged;
        }

        // The tray icon goes first so it never lingers as a ghost.
        _tray?.Dispose();
        _controller?.Dispose();

        base.OnExit(e);
    }
}
