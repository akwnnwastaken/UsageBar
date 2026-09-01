using System.Runtime.Versioning;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Settings;
using UsageBar.Windows.Infrastructure.Startup;

namespace UsageBar.Windows.App.Views;

/// <summary>
/// The intentional child window for settings. It is deliberately a separate
/// window so the panel can stay open while it has focus.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class SettingsWindow : Window
{
    private readonly UsageBarController _controller;
    private readonly StackPanel _content;
    private AppTheme _theme = AppTheme.Current();

    public SettingsWindow(UsageBarController controller, Window owner)
    {
        _controller = controller;

        Owner = owner;
        Width = 360;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");
        FontSize = 13;

        _content = new StackPanel { Margin = new Thickness(16) };
        Content = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MaxHeight = 640,
            Content = _content
        };

        Closing += (_, e) =>
        {
            e.Cancel = true;
            Hide();
        };
    }

    public event EventHandler? TrayGuidanceRequested;

    public event EventHandler? DiagnosticsRequested;

    public void ShowSettings()
    {
        _theme = AppTheme.Current();
        Rebuild();
        Show();
        Activate();
    }

    public void Rebuild()
    {
        var text = _controller.Text;
        Title = text.Settings;
        Background = _theme.Background;
        Foreground = _theme.Foreground;

        _content.Children.Clear();

        _content.Children.Add(Caption(text.LanguageTitle));
        _content.Children.Add(Choice(
            new[] { ("Türkçe", AppLanguage.Turkish), ("English", AppLanguage.English) },
            _controller.Language,
            language => _controller.UpdateSettings(
                settings => settings.Language = language.StorageValue())));

        _content.Children.Add(Caption(text.RefreshIntervalTitle));
        _content.Children.Add(Choice(
            UsageRefreshIntervals.All
                .Select(interval => (text.RefreshIntervalOption(interval), interval))
                .ToArray(),
            _controller.RefreshInterval,
            interval => _controller.UpdateSettings(
                settings => settings.RefreshInterval = interval.StorageValue())));

        // Collection can be paused per provider without disconnecting it, so
        // the control belongs beside the other provider settings and stays
        // available while the provider is paused. The controller owns the
        // transition; this only forwards the intent.
        //
        // "Show details" is a second, separate control answering a separate
        // question: whether the panel draws the provider's detailed body. It
        // lives here rather than in the panel it collapses, so hiding the
        // details can never hide the way back.
        foreach (var providerName in _controller.ConnectedProviderNames)
        {
            var isCollecting = _controller.Settings.IsCollectionEnabled(providerName);
            _content.Children.Add(Caption(
                isCollecting ? providerName : $"{providerName} · {text.Paused}"));
            _content.Children.Add(Toggle(
                text.CollectUsage,
                isCollecting,
                value => _controller.SetCollectionEnabled(providerName, value)));
            _content.Children.Add(Toggle(
                text.ShowDetails,
                _controller.AreDetailsVisible(providerName),
                value => _controller.SetDetailsVisible(providerName, value)));
        }

        _content.Children.Add(Caption(text.UsageColorsTitle));
        _content.Children.Add(Toggle(
            text.UsageColorsEnabled,
            _controller.Settings.UsageColorsEnabled ?? true,
            value => _controller.UpdateSettings(settings => settings.UsageColorsEnabled = value)));

        _content.Children.Add(Caption(text.ThresholdProfileTitle));
        foreach (var preset in new[] { UsageAlertPreset.Late, UsageAlertPreset.Balanced, UsageAlertPreset.Early })
        {
            var current = UsageBarSettingsSanitizer.ResolvePreset(_controller.Settings.UsageAlertPreset);
            _content.Children.Add(Radio(
                text.AlertPresetTitle(preset),
                current == preset,
                _controller.Settings.UsageColorsEnabled ?? true,
                () => _controller.UpdateSettings(
                    settings => settings.UsageAlertPreset = preset.ToStorageValue())));
        }

        _content.Children.Add(Caption(text.TrayAppearance));
        _content.Children.Add(Toggle(
            text.ShowResetCountdown,
            _controller.Settings.ShowResetCountdown ?? false,
            value => _controller.UpdateSettings(settings => settings.ShowResetCountdown = value)));

        _content.Children.Add(Caption(text.UsageHistoryTitle));
        _content.Children.Add(Toggle(
            text.ShowUsageHistory,
            _controller.Settings.UsageHistoryEnabled ?? true,
            value => _controller.UpdateSettings(settings => settings.UsageHistoryEnabled = value)));
        _content.Children.Add(Action(text.ClearUsageHistory, _controller.ClearHistory));

        _content.Children.Add(Caption(text.LaunchAtStartup));
        var autoStart = _controller.AutoStartState;
        _content.Children.Add(Toggle(
            text.LaunchAtStartup,
            autoStart.IsOn,
            _ => _controller.ToggleAutoStart(),
            enabled: autoStart.Status != AutoStartStatus.Unavailable));

        if (autoStart.Status == AutoStartStatus.Unavailable)
        {
            _content.Children.Add(Note(text.LaunchAtStartupBlockedByPolicy));
        }
        else if (autoStart.Status == AutoStartStatus.EnabledForDifferentPath)
        {
            _content.Children.Add(Note(text.LaunchAtStartupStalePath));
        }

        _content.Children.Add(Caption(text.ClaudeInstallationTitle));
        _content.Children.Add(Explanation(text.ClaudeInstallationHelp));
        _content.Children.Add(Choice(
            new[]
            {
                (text.ClaudeAdapterModeAutomatic, ClaudeAdapterMode.Automatic),
                (text.ClaudeAdapterModeNative, ClaudeAdapterMode.NativeWindows),
                (text.ClaudeAdapterModeWsl, ClaudeAdapterMode.Wsl)
            },
            ClaudeAdapterModes.Resolved(_controller.Settings.ClaudeAdapterMode),
            mode => _controller.UpdateSettings(
                settings => settings.ClaudeAdapterMode = mode.StorageValue())));

        // Only offered when WSL can actually be used, and only ever a
        // distribution name — never a path inside the distribution.
        var distributions = _controller.WslDistributions;
        if (ClaudeAdapterModes.Resolved(_controller.Settings.ClaudeAdapterMode) != ClaudeAdapterMode.NativeWindows &&
            distributions.Count > 0)
        {
            _content.Children.Add(Caption(text.ClaudeWslDistributionTitle));

            var options = new List<(string, string?)>
            {
                (text.ClaudeWslDistributionAutomatic, null)
            };
            options.AddRange(distributions.Select(name => (name, (string?)name)));

            _content.Children.Add(Choice(
                options,
                _controller.Settings.ClaudeWslDistribution,
                distribution => _controller.UpdateSettings(
                    settings => settings.ClaudeWslDistribution = distribution)));
        }

        _content.Children.Add(Caption(text.TrayGuidanceTitle));
        _content.Children.Add(Explanation(text.TrayGuidanceDetail));
        _content.Children.Add(Explanation(text.TrayGuidanceSettingsPath));
        _content.Children.Add(Action(
            text.ShowTrayGuidanceAgain,
            () => TrayGuidanceRequested?.Invoke(this, EventArgs.Empty)));
        _content.Children.Add(Action(
            text.CopyDiagnostics,
            () => DiagnosticsRequested?.Invoke(this, EventArgs.Empty)));

        _content.Children.Add(new TextBlock
        {
            Text = text.AppVersion(
                Infrastructure.Diagnostics.WindowsEnvironmentInfo.ApplicationVersion),
            Foreground = _theme.SecondaryForeground,
            FontSize = 11,
            Margin = new Thickness(0, 12, 0, 0)
        });

        var close = new Button
        {
            Content = text.Close,
            Padding = new Thickness(14, 4, 14, 4),
            HorizontalAlignment = System.Windows.HorizontalAlignment.Right,
            Margin = new Thickness(0, 10, 0, 0)
        };
        close.Click += (_, _) => Hide();
        _content.Children.Add(close);
    }

    private UIElement Choice<T>(
        IReadOnlyList<(string Label, T Value)> options,
        T current,
        Action<T> select)
    {
        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(0, 0, 0, 10)
        };

        foreach (var (label, value) in options)
        {
            var isSelected = EqualityComparer<T>.Default.Equals(value, current);
            var button = new Button
            {
                Content = label,
                Padding = new Thickness(12, 3, 12, 3),
                Margin = new Thickness(0, 0, 6, 0),
                FontWeight = isSelected ? FontWeights.SemiBold : FontWeights.Normal,
                BorderBrush = isSelected ? _theme.Normal : _theme.Border,
                BorderThickness = new Thickness(isSelected ? 2 : 1)
            };
            button.Click += (_, _) =>
            {
                select(value);
                Rebuild();
            };
            row.Children.Add(button);
        }

        return row;
    }

    private UIElement Toggle(string label, bool isChecked, Action<bool> set, bool enabled = true)
    {
        var box = new CheckBox
        {
            Content = label,
            IsChecked = isChecked,
            IsEnabled = enabled,
            Foreground = _theme.Foreground,
            Margin = new Thickness(0, 0, 0, 8)
        };
        box.Click += (_, _) =>
        {
            set(box.IsChecked == true);
            Rebuild();
        };
        return box;
    }

    private UIElement Radio(string label, bool isChecked, bool enabled, Action select)
    {
        var radio = new RadioButton
        {
            Content = label,
            IsChecked = isChecked,
            IsEnabled = enabled,
            GroupName = "threshold",
            Foreground = _theme.Foreground,
            Margin = new Thickness(0, 0, 0, 6)
        };
        radio.Checked += (_, _) =>
        {
            if (!isChecked)
            {
                select();
                Rebuild();
            }
        };
        return radio;
    }

    private UIElement Action(string label, Action action)
    {
        var button = new Button
        {
            Content = label,
            Padding = new Thickness(10, 4, 10, 4),
            HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
            Margin = new Thickness(0, 0, 0, 10)
        };
        button.Click += (_, _) =>
        {
            action();
            Rebuild();
        };
        return button;
    }

    private TextBlock Caption(string value) => new()
    {
        Text = value,
        Foreground = _theme.SecondaryForeground,
        FontSize = 11,
        FontWeight = FontWeights.SemiBold,
        Margin = new Thickness(0, 6, 0, 6)
    };

    /// <summary>Wrapping explanatory text; never clipped, however long.</summary>
    private TextBlock Explanation(string value) => new()
    {
        Text = value,
        Foreground = _theme.SecondaryForeground,
        FontSize = 11,
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 0, 0, 8)
    };

    private TextBlock Note(string value) => new()
    {
        Text = value,
        Foreground = _theme.Warning,
        FontSize = 11,
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 0, 0, 8)
    };
}
