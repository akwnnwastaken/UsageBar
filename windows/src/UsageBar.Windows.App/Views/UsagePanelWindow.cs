using System.Globalization;
using System.Runtime.Versioning;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;

namespace UsageBar.Windows.App.Views;

/// <summary>
/// The compact panel that opens above the taskbar next to the notification
/// area.
///
/// It is not a main window: it never appears in the taskbar, closing it does not
/// end the application, and it hides itself when it loses activation — unless an
/// intentional child window (the settings dialog) is what took focus.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class UsagePanelWindow : Window
{
    private const double PanelWidth = 340;

    private readonly UsageBarController _controller;
    private readonly StackPanel _content;
    private AppTheme _theme = AppTheme.Current();

    public UsagePanelWindow(UsageBarController controller)
    {
        _controller = controller;

        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        SizeToContent = SizeToContent.Height;
        Width = PanelWidth;
        AllowsTransparency = false;
        Title = "UsageBar";
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");
        FontSize = 13;

        _content = new StackPanel { Margin = new Thickness(14) };
        var border = new Border
        {
            BorderThickness = new Thickness(1),
            Child = new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                MaxHeight = 620,
                Content = _content
            }
        };

        Content = border;
        Deactivated += OnDeactivated;
        // Closing the panel must never end the application.
        Closing += (_, e) =>
        {
            e.Cancel = true;
            Hide();
        };
    }

    /// <summary>Set while a child settings window is open, so focus loss to it does not hide the panel.</summary>
    public Func<bool>? IsChildWindowActive { get; set; }

    public event EventHandler? SettingsRequested;

    public event EventHandler? DiagnosticsRequested;

    public event EventHandler? ExitRequested;

    public void ToggleVisibility()
    {
        if (IsVisible)
        {
            Hide();
            return;
        }

        ShowNearTray();
    }

    public void ShowNearTray()
    {
        _theme = AppTheme.Current();
        Rebuild();

        // Measure before positioning so the panel can be placed by its real
        // height, not an estimate.
        Show();
        UpdateLayout();
        PositionAboveTray();
        Activate();
    }

    /// <summary>
    /// Places the panel inside the working area of the monitor that currently
    /// holds the mouse, so it lands next to the notification area on that
    /// display and never overlaps the taskbar.
    /// </summary>
    private void PositionAboveTray()
    {
        var source = PresentationSource.FromVisual(this);
        var transform = source?.CompositionTarget?.TransformFromDevice ?? Matrix.Identity;

        var screen = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position);
        var work = screen.WorkingArea;

        var topLeft = transform.Transform(new Point(work.Left, work.Top));
        var bottomRight = transform.Transform(new Point(work.Right, work.Bottom));

        const double margin = 12;
        var width = ActualWidth > 0 ? ActualWidth : PanelWidth;
        var height = ActualHeight > 0 ? ActualHeight : 200;

        var left = bottomRight.X - width - margin;
        var top = bottomRight.Y - height - margin;

        // Clamp into the working area so a taskbar on the top or the left, or a
        // panel taller than the screen, still lands somewhere visible.
        Left = Math.Max(topLeft.X + margin, Math.Min(left, bottomRight.X - width - margin));
        Top = Math.Max(topLeft.Y + margin, Math.Min(top, bottomRight.Y - height - margin));
    }

    private void OnDeactivated(object? sender, EventArgs e)
    {
        // Clicking outside closes the panel, but opening the settings dialog
        // must not.
        if (IsChildWindowActive?.Invoke() == true)
        {
            return;
        }

        Hide();
    }

    public void Rebuild()
    {
        var text = _controller.Text;
        var colorsEnabled = _controller.Settings.UsageColorsEnabled ?? true;

        Background = _theme.Background;
        Foreground = _theme.Foreground;
        if (Content is Border border)
        {
            border.Background = _theme.Background;
            border.BorderBrush = _theme.Border;
        }

        _content.Children.Clear();
        _content.Children.Add(Header(text));

        var connected = _controller.ConnectedProviderNames;
        if (connected.Count == 0)
        {
            _content.Children.Add(Muted(text.ConnectFirst));
            _content.Children.Add(ActionButton(text.ConnectCodex, _controller.ConnectCodex));
        }
        else
        {
            if (connected.Count > 1)
            {
                _content.Children.Add(ProviderSelector(text, connected));
            }

            foreach (var providerName in connected)
            {
                _content.Children.Add(ProviderCard(text, providerName, colorsEnabled));
            }
        }

        // Claude is listed so its absence is explicit rather than a silent gap.
        _content.Children.Add(ClaudeNotice(text));

        if (_controller.LastUpdated is DateTimeOffset updated)
        {
            _content.Children.Add(Muted(text.LastUpdated(text.FormattedTime(updated))));
        }

        _content.Children.Add(FooterButtons(text));
    }

    private UIElement Header(Localizer text)
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 10) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var title = new TextBlock
        {
            Text = text.AppName,
            FontSize = 17,
            FontWeight = FontWeights.SemiBold,
            Foreground = _theme.Foreground,
            VerticalAlignment = System.Windows.VerticalAlignment.Center
        };
        Grid.SetColumn(title, 0);
        grid.Children.Add(title);

        var refresh = new Button
        {
            Content = _controller.IsRefreshing ? text.Refreshing : text.RefreshNow,
            Padding = new Thickness(10, 3, 10, 3),
            IsEnabled = !_controller.IsRefreshing && _controller.ConnectedProviderNames.Count > 0
        };
        refresh.Click += (_, _) => _ = _controller.RefreshAsync();
        Grid.SetColumn(refresh, 1);
        grid.Children.Add(refresh);

        return grid;
    }

    private UIElement ProviderSelector(Localizer text, IReadOnlyList<string> connected)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 0, 8) };
        panel.Children.Add(Caption(text.ShowInTray));

        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(SelectorButton(
            text.Automatic,
            _controller.Settings.AutoRotateProviders,
            () => _controller.UpdateSettings(settings => settings.AutoRotateProviders = true)));

        foreach (var providerName in connected)
        {
            var isSelected = !_controller.Settings.AutoRotateProviders &&
                             _controller.Settings.SelectedProvider == providerName;
            var label = providerName == ProviderNames.ClaudeCode ? "Claude" : providerName;
            row.Children.Add(SelectorButton(label, isSelected, () => _controller.UpdateSettings(settings =>
            {
                settings.AutoRotateProviders = false;
                settings.SelectedProvider = providerName;
            })));
        }

        panel.Children.Add(row);
        return panel;
    }

    private UIElement ProviderCard(Localizer text, string providerName, bool colorsEnabled)
    {
        var usage = _controller.DisplayUsages.TryGetValue(providerName, out var found) ? found : null;

        var card = new StackPanel();
        card.Children.Add(new TextBlock
        {
            Text = providerName,
            FontWeight = FontWeights.SemiBold,
            Foreground = _theme.Foreground,
            Margin = new Thickness(0, 0, 0, 4)
        });

        if (usage is null || usage.Windows.Count == 0)
        {
            var issue = usage?.Error ?? (_controller.IsRefreshing ? ProviderIssue.Refreshing : ProviderIssue.NoData);
            card.Children.Add(new TextBlock
            {
                Text = text.Issue(issue),
                Foreground = issue.IsInformational ? _theme.SecondaryForeground : _theme.Critical,
                TextWrapping = TextWrapping.Wrap
            });
        }
        else
        {
            for (var position = 0; position < usage.Windows.Count; position++)
            {
                card.Children.Add(WindowRow(text, usage, usage.Windows[position], position, colorsEnabled));
            }

            if (usage.IsStale && usage.LastSuccessfulAt is DateTimeOffset lastGood)
            {
                card.Children.Add(new TextBlock
                {
                    Text = text.StaleData(text.FormattedTime(lastGood), usage.Error!),
                    Foreground = _theme.Stale,
                    FontSize = 11,
                    TextWrapping = TextWrapping.Wrap,
                    Margin = new Thickness(0, 4, 0, 0)
                });
            }
        }

        return Section(card);
    }

    private UIElement WindowRow(
        Localizer text,
        ProviderUsage usage,
        UsageWindow window,
        int position,
        bool colorsEnabled)
    {
        var remaining = window.RemainingPercent;
        var level = _controller.AlertPolicy.Level(remaining);

        var panel = new StackPanel { Margin = new Thickness(0, 3, 0, 3) };

        var line = new TextBlock { TextWrapping = TextWrapping.Wrap };
        line.Inlines.Add(new System.Windows.Documents.Run($"{text.UsageWindowLabel(window, position)}: ")
        {
            Foreground = _theme.Foreground
        });
        line.Inlines.Add(new System.Windows.Documents.Run(text.Remaining(remaining))
        {
            Foreground = _theme.ForLevel(level, colorsEnabled),
            FontWeight = FontWeights.SemiBold
        });
        panel.Children.Add(line);

        if (window.ResetsAt is DateTimeOffset resetsAt)
        {
            panel.Children.Add(new TextBlock
            {
                Text = text.ResetIn(text.RelativeReset(resetsAt, DateTimeOffset.Now)),
                Foreground = _theme.SecondaryForeground,
                FontSize = 11
            });
        }

        if (_controller.Settings.UsageHistoryEnabled ?? true)
        {
            var key = UsageHistoryModel.SeriesKey(usage.Name, window.Kind);
            if (_controller.History.TryGetValue(key, out var samples) && samples.Count > 0)
            {
                panel.Children.Add(HistoryBlock(text, samples, level, colorsEnabled));
            }
        }

        return panel;
    }

    private UIElement HistoryBlock(
        Localizer text,
        IReadOnlyList<UsageHistorySample> samples,
        UsageAlertLevel level,
        bool colorsEnabled)
    {
        var model = new UsageHistoryChartModel(samples);
        var panel = new StackPanel { Margin = new Thickness(0, 4, 0, 0) };

        panel.Children.Add(new TextBlock
        {
            Text = $"{text.UsageHistoryRange(model.RecordedDuration)} · {text.UsageHistorySummary(model)}",
            Foreground = _theme.SecondaryForeground,
            FontSize = 10,
            TextTrimming = TextTrimming.CharacterEllipsis
        });

        panel.Children.Add(new UsageHistoryChart
        {
            Samples = samples,
            Height = 34,
            LineBrush = _theme.ForLevel(level, colorsEnabled),
            PlotBackground = _theme.PlotBackground,
            Margin = new Thickness(0, 3, 0, 0)
        });

        return panel;
    }

    private UIElement ClaudeNotice(Localizer text)
    {
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock
        {
            Text = text.ClaudeNotSupportedYet,
            Foreground = _theme.SecondaryForeground,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap
        });
        panel.Children.Add(new TextBlock
        {
            Text = text.ClaudeNotSupportedYetDetail,
            Foreground = _theme.SecondaryForeground,
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 2, 0, 0)
        });

        return Section(panel);
    }

    private UIElement FooterButtons(Localizer text)
    {
        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(0, 10, 0, 0)
        };

        row.Children.Add(ActionButton(text.Settings, () => SettingsRequested?.Invoke(this, EventArgs.Empty)));
        row.Children.Add(ActionButton(
            text.CopyDiagnostics,
            () => DiagnosticsRequested?.Invoke(this, EventArgs.Empty)));
        row.Children.Add(ActionButton(text.ExitUsageBar, () => ExitRequested?.Invoke(this, EventArgs.Empty)));

        return row;
    }

    private Button ActionButton(string label, Action action)
    {
        var button = new Button
        {
            Content = label,
            Padding = new Thickness(10, 4, 10, 4),
            Margin = new Thickness(0, 0, 6, 0)
        };
        button.Click += (_, _) => action();
        return button;
    }

    private Button SelectorButton(string label, bool isSelected, Action action)
    {
        var button = new Button
        {
            Content = label,
            Padding = new Thickness(12, 3, 12, 3),
            Margin = new Thickness(0, 0, 6, 0),
            FontWeight = isSelected ? FontWeights.SemiBold : FontWeights.Normal,
            BorderBrush = isSelected ? _theme.Normal : _theme.Border,
            BorderThickness = new Thickness(isSelected ? 2 : 1)
        };
        button.Click += (_, _) => action();
        return button;
    }

    private TextBlock Caption(string value) => new()
    {
        Text = value,
        Foreground = _theme.SecondaryForeground,
        FontSize = 11,
        Margin = new Thickness(0, 0, 0, 4)
    };

    private TextBlock Muted(string value) => new()
    {
        Text = value,
        Foreground = _theme.SecondaryForeground,
        FontSize = 11,
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 6, 0, 0)
    };

    private Border Section(UIElement child) => new()
    {
        Background = _theme.Surface,
        BorderBrush = _theme.Border,
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(6),
        Padding = new Thickness(10),
        Margin = new Thickness(0, 0, 0, 8),
        Child = child
    };

    /// <summary>Keeps the panel positioned correctly when the display scale changes.</summary>
    protected override void OnDpiChanged(DpiScale oldDpi, DpiScale newDpi)
    {
        base.OnDpiChanged(oldDpi, newDpi);
        if (IsVisible)
        {
            UpdateLayout();
            PositionAboveTray();
        }
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        // A tool window never gets a taskbar button, even transiently.
        var helper = new WindowInteropHelper(this);
        var style = GetWindowLong(helper.Handle, GwlExStyle);
        SetWindowLong(helper.Handle, GwlExStyle, style | WsExToolWindow);
    }

    private const int GwlExStyle = -20;
    private const int WsExToolWindow = 0x00000080;

    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr window, int index);

    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)]
    private static extern int SetWindowLong(IntPtr window, int index, int value);

    internal static string FormatPercent(int value) =>
        value.ToString(CultureInfo.InvariantCulture);
}
