using System.Runtime.Versioning;
using System.Windows.Forms;
using Microsoft.Win32;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Infrastructure.Startup;

namespace UsageBar.Windows.App.Tray;

/// <summary>
/// Owns the notification-area icon: its rendered image, its tooltip, the
/// left-click toggle, the right-click menu and the one-time visibility
/// guidance.
///
/// UsageBar never tries to pin itself into the always-visible area. It does not
/// touch Explorer's TrayNotify state, does not restart Explorer and does not
/// synthesize input; it only explains, once, how the user can drag the icon out
/// of the overflow menu themselves.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class TrayIconController : IDisposable
{
    private readonly UsageBarController _controller;
    private readonly TrayIconRenderer _renderer = new();
    private readonly NotifyIcon _notifyIcon;
    private readonly ContextMenuStrip _menu;
    private bool _disposed;

    public TrayIconController(UsageBarController controller)
    {
        _controller = controller;
        _menu = new ContextMenuStrip { ShowImageMargin = false };
        _notifyIcon = new NotifyIcon
        {
            ContextMenuStrip = _menu,
            Visible = false
        };

        _notifyIcon.MouseClick += OnMouseClick;
        _menu.Opening += (_, _) => BuildMenu();
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
    }

    /// <summary>Raised on left-click; the host toggles the popup.</summary>
    public event EventHandler? ToggleRequested;

    public event EventHandler? ShowRequested;

    public event EventHandler? SettingsRequested;

    public event EventHandler? ExitRequested;

    /// <summary>True once the icon has actually been created in the tray.</summary>
    public bool IsVisible => _notifyIcon.Visible;

    public void Show()
    {
        Update();
        _notifyIcon.Visible = true;
    }

    /// <summary>Redraws the icon and refreshes the tooltip from current state.</summary>
    public void Update()
    {
        if (_disposed)
        {
            return;
        }

        var presentation = _controller.Presentation;
        _notifyIcon.Icon = _renderer.Render(presentation, IconSize(), UsesLightTrayForeground());
        _notifyIcon.Text = presentation.Tooltip;
    }

    /// <summary>
    /// Shows the first-run guidance if it has not been shown for the current
    /// guidance version. Called only after the icon exists, never modal, and it
    /// never blocks startup.
    /// </summary>
    public void ShowTrayGuidanceIfNeeded()
    {
        if (!TrayGuidancePolicy.ShouldShowAutomatically(_controller.Settings.TrayGuidanceVersionShown))
        {
            return;
        }

        ShowTrayGuidance();
    }

    /// <summary>The manual "show it again" action. Always shows.</summary>
    public void ShowTrayGuidance()
    {
        if (!_notifyIcon.Visible)
        {
            return;
        }

        var text = _controller.Text;
        _notifyIcon.BalloonTipTitle = text.TrayGuidanceTitle;
        _notifyIcon.BalloonTipText = text.TrayGuidanceBody;
        _notifyIcon.BalloonTipIcon = ToolTipIcon.Info;
        _notifyIcon.ShowBalloonTip(15_000);

        // Recorded only after the request was issued, and never rolled back to
        // an older version than the settings already carry.
        _controller.UpdateSettings(settings =>
            settings.TrayGuidanceVersionShown = TrayGuidancePolicy.VersionAfterShowing(
                settings.TrayGuidanceVersionShown));
    }

    private void OnMouseClick(object? sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            ToggleRequested?.Invoke(this, EventArgs.Empty);
        }
    }

    private void BuildMenu()
    {
        var text = _controller.Text;
        _menu.Items.Clear();

        _menu.Items.Add(Item(text.RefreshNow, () => _ = _controller.RefreshAsync(), !_controller.IsRefreshing));
        _menu.Items.Add(Item(text.ShowUsageBar, () => ShowRequested?.Invoke(this, EventArgs.Empty)));
        _menu.Items.Add(new ToolStripSeparator());

        if (!_controller.Settings.CodexConnected)
        {
            _menu.Items.Add(Item(text.ConnectCodex, _controller.ConnectCodex));
        }
        else
        {
            _menu.Items.Add(Item(
                text.DisconnectCodex,
                () => _controller.DisconnectProvider(ProviderNames.Codex)));
        }

        // Claude has no Windows adapter yet. It is shown disabled and labeled
        // rather than offered as if it worked.
        var claude = Item(text.ClaudeNotSupportedYet, static () => { }, enabled: false);
        claude.ToolTipText = text.ClaudeNotSupportedYetDetail;
        _menu.Items.Add(claude);

        _menu.Items.Add(new ToolStripSeparator());

        var autoStart = Item(text.LaunchAtStartup, () => _controller.ToggleAutoStart());
        autoStart.Checked = _controller.AutoStartState.IsOn;
        autoStart.Enabled = _controller.AutoStartState.Status != AutoStartStatus.Unavailable;
        if (_controller.AutoStartState.Status == AutoStartStatus.EnabledForDifferentPath)
        {
            autoStart.ToolTipText = text.LaunchAtStartupStalePath;
        }
        else if (_controller.AutoStartState.Status == AutoStartStatus.Unavailable)
        {
            autoStart.ToolTipText = text.LaunchAtStartupBlockedByPolicy;
        }

        _menu.Items.Add(autoStart);
        _menu.Items.Add(Item(text.ShowTrayGuidanceAgain, ShowTrayGuidance));
        _menu.Items.Add(Item(text.Settings, () => SettingsRequested?.Invoke(this, EventArgs.Empty)));
        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(Item(text.ExitUsageBar, () => ExitRequested?.Invoke(this, EventArgs.Empty)));
    }

    private static ToolStripMenuItem Item(string label, Action action, bool enabled = true)
    {
        var item = new ToolStripMenuItem(label) { Enabled = enabled };
        item.Click += (_, _) => action();
        return item;
    }

    /// <summary>
    /// Tray icons are drawn at the system's small-icon size, which grows with
    /// the display scale.
    /// </summary>
    private static int IconSize()
    {
        var height = SystemInformation.SmallIconSize.Height;
        return height is >= 16 and <= 64 ? height : 16;
    }

    /// <summary>
    /// A dark taskbar needs a light glyph. Read from the same setting Explorer
    /// uses; anything unreadable falls back to the dark-taskbar default.
    /// </summary>
    private static bool UsesLightTrayForeground()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("SystemUsesLightTheme") is not int light || light == 0;
        }
        catch (Exception exception) when (
            exception is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            return true;
        }
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category is UserPreferenceCategory.General or UserPreferenceCategory.Color
            or UserPreferenceCategory.VisualStyle)
        {
            Update();
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;

        // Hide before disposing so the icon leaves the tray immediately rather
        // than lingering as a ghost until the user hovers over it.
        _notifyIcon.Visible = false;
        _notifyIcon.Icon = null;
        _notifyIcon.Dispose();
        _menu.Dispose();
        _renderer.Dispose();
    }
}
