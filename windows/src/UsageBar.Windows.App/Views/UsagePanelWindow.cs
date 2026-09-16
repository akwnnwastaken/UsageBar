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
using UsageBar.Windows.Core.Settings;

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
    /// <summary>
    /// Narrowest the panel may get. Sized for Turkish, which runs noticeably
    /// longer than English — "Tanılama özetini kopyala" against "Copy
    /// diagnostics" — and was what overflowed the original fixed 340.
    /// </summary>
    private const double MinimumPanelWidth = 380;

    /// <summary>
    /// Widest the panel grows before text wraps instead. The real cap is the
    /// monitor's working area, applied in <see cref="ApplySizeConstraints"/>.
    /// </summary>
    private const double PreferredMaximumWidth = 560;

    /// <summary>Gap kept between the panel and the edges of the working area.</summary>
    private const double ScreenMargin = 12;

    private readonly UsageBarController _controller;
    private readonly StackPanel _content;
    private readonly WrapPanel _footer;
    private readonly ScrollViewer _scroller;
    private AppTheme _theme = AppTheme.Current();

    public UsagePanelWindow(UsageBarController controller)
    {
        _controller = controller;

        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        // Both dimensions follow the content: the panel widens for long strings
        // rather than clipping them, bounded by MinWidth/MaxWidth.
        SizeToContent = SizeToContent.WidthAndHeight;
        MinWidth = MinimumPanelWidth;
        MaxWidth = PreferredMaximumWidth;
        AllowsTransparency = false;
        Title = "UsageBar";
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");
        FontSize = 13;

        _content = new StackPanel();
        _scroller = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            // Never scroll sideways: content wraps instead, so nothing is ever
            // hidden off the right edge.
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = _content
        };

        // Actions wrap onto further lines when they do not fit on one, so a
        // long label can never push a button past the panel edge.
        _footer = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) };

        // The footer is docked, not scrolled, so the actions stay reachable
        // however long the usage list gets.
        var layout = new DockPanel { LastChildFill = true, Margin = new Thickness(16, 14, 16, 14) };
        DockPanel.SetDock(_footer, Dock.Bottom);
        layout.Children.Add(_footer);
        layout.Children.Add(_scroller);

        Content = new Border
        {
            BorderThickness = new Thickness(1),
            Child = layout
        };

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
        Show();

        // Constrain first, then measure, then place: the position depends on the
        // panel's real size, and its real size depends on how much room the
        // monitor allows.
        ApplySizeConstraints();
        UpdateLayout();
        PositionAboveTray();
        Activate();
    }

    /// <summary>
    /// The monitor's working area in device-independent pixels — the units
    /// <see cref="Window.Left"/>, <see cref="Window.Width"/> and the layout
    /// system use. Doing the conversion here is what keeps placement correct at
    /// 125% and 150% scaling and on a second monitor with a different scale.
    /// </summary>
    private Rect CurrentWorkArea()
    {
        var transform = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformFromDevice
                        ?? Matrix.Identity;

        var screen = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position);
        var work = screen.WorkingArea;

        var topLeft = transform.Transform(new Point(work.Left, work.Top));
        var bottomRight = transform.Transform(new Point(work.Right, work.Bottom));

        return new Rect(topLeft, bottomRight);
    }

    /// <summary>
    /// Bounds the panel to what the current monitor can actually show. Width is
    /// capped so it never runs off the side; height is capped so a long usage
    /// list scrolls inside the panel instead of growing past the screen.
    /// </summary>
    private void ApplySizeConstraints()
    {
        var work = CurrentWorkArea();
        var available = ScreenMargin * 2;

        MaxWidth = Math.Max(MinimumPanelWidth, Math.Min(PreferredMaximumWidth, work.Width - available));
        MaxHeight = Math.Max(240, work.Height - available);
    }

    /// <summary>
    /// Places the panel inside the working area of the monitor that currently
    /// holds the mouse, so it lands near the notification area on that display
    /// and never overlaps the taskbar — including when the taskbar is on the
    /// top, left or right edge.
    /// </summary>
    private void PositionAboveTray()
    {
        var work = CurrentWorkArea();
        var width = ActualWidth > 0 ? ActualWidth : MinimumPanelWidth;
        var height = ActualHeight > 0 ? ActualHeight : 240;

        // Preferred spot: the bottom-right of the working area, which is where
        // the notification area sits in the default Windows layout.
        var left = work.Right - width - ScreenMargin;
        var top = work.Bottom - height - ScreenMargin;

        // Clamped so a panel wider or taller than the working area still starts
        // on screen rather than disappearing off the top-left.
        Left = Math.Max(work.Left + ScreenMargin, Math.Min(left, work.Right - width - ScreenMargin));
        Top = Math.Max(work.Top + ScreenMargin, Math.Min(top, work.Bottom - height - ScreenMargin));
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
        _footer.Children.Clear();
        _content.Children.Add(Header(text));

        var connected = _controller.ConnectedProviderNames;
        if (connected.Count == 0)
        {
            _content.Children.Add(Muted(text.ConnectFirst));
        }
        else
        {
            // Auto only makes sense with more than one provider connected.
            if (connected.Count > 1)
            {
                _content.Children.Add(ProviderSelector(text, connected));
            }

            foreach (var providerName in connected)
            {
                _content.Children.Add(ProviderCard(text, providerName, colorsEnabled));
            }
        }

        if (connected.Count < 2)
        {
            _content.Children.Add(ConnectActions(text));
        }

        if (_controller.LastUpdated is DateTimeOffset updated)
        {
            _content.Children.Add(Muted(text.LastUpdated(text.FormattedTime(updated))));
        }

        BuildFooter(text);
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
            VerticalAlignment = System.Windows.VerticalAlignment.Center,
            // The title yields before the refresh button does: losing a
            // character of "UsageBar" is better than clipping an action.
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(title, 0);
        grid.Children.Add(title);

        var refresh = new Button
        {
            Content = _controller.IsRefreshing ? text.Refreshing : text.RefreshNow,
            MinWidth = 88,
            Padding = new Thickness(12, 5, 12, 5),
            Margin = new Thickness(8, 0, 0, 0),
            // Nothing to refresh while every connected provider is paused: the
            // action would launch no provider, so it must not look available.
            IsEnabled = !_controller.IsRefreshing && _controller.EligibleProviderNames.Count > 0
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

        // Wraps for the same reason the footer does: three provider names in
        // Turkish can be wider than the panel.
        var row = new WrapPanel();
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
        var isCollecting = _controller.Settings.IsCollectionEnabled(providerName);

        // The whole rendering decision, taken once and owned by the controller's
        // stored state. `usage` itself is never rewritten to produce the compact
        // form: the readings, their history and their freshness are all still
        // there, simply not drawn.
        //
        // A paused provider keeps whatever error it last had, but UsageBar is
        // not trying to collect from it, so showing that error would blame the
        // provider for a state the user chose.
        var plan = ProviderDetailPresentationPolicy.Card(
            isCollecting,
            _controller.AreDetailsVisible(providerName),
            usage?.Error is not null);

        var card = new StackPanel();
        card.Children.Add(new TextBlock
        {
            // A paused provider stays on the panel — it is still connected, and
            // the marker says why it is not moving. So does a compact one.
            Text = plan.ShowsPausedMarker ? $"{providerName} · {text.Paused}" : providerName,
            FontWeight = FontWeights.SemiBold,
            Foreground = _theme.Foreground,
            Margin = new Thickness(0, 0, 0, 4)
        });

        if (usage is null || usage.Windows.Count == 0)
        {
            if (!isCollecting)
            {
                return Section(card);
            }

            // Operational state rather than quota data, so it survives a hidden
            // body: without it a provider that has never read would look the
            // same as a healthy one the user collapsed.
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
            // The single gate on the detailed body. Making the *list* empty
            // rather than skipping a loop is deliberate: there is one place
            // windows are enumerated, so no usage row, reset line, history
            // summary or chart can be built for a hidden provider by any other
            // route.
            var detailWindows = plan.ShowsDetailBody ? usage.Windows : Array.Empty<UsageWindow>();
            for (var position = 0; position < detailWindows.Count; position++)
            {
                card.Children.Add(WindowRow(text, usage, detailWindows[position], position, colorsEnabled));
            }

            if (plan.ShowsOperationalIssue && usage.IsStale && usage.LastSuccessfulAt is DateTimeOffset lastGood)
            {
                // The stale line carries a last-successful clock, which is
                // detail, so the concise form stands in while the body is
                // hidden. Either way the failure is still reported.
                card.Children.Add(new TextBlock
                {
                    Text = plan.ShowsDetailBody
                        ? text.StaleData(text.FormattedTime(lastGood), usage.Error!)
                        : text.Issue(usage.Error!),
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

        if (text.ResetDisplay(window.ResetsAt, DateTimeOffset.Now) is string resetLine)
        {
            panel.Children.Add(new TextBlock
            {
                Text = resetLine,
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

        var defaultSummary = $"{text.UsageHistoryRange(model.RecordedDuration)} · {text.UsageHistorySummary(model)}";
        var summary = new TextBlock
        {
            Text = defaultSummary,
            Foreground = _theme.SecondaryForeground,
            FontSize = 10,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        panel.Children.Add(summary);

        var chart = new UsageHistoryChart
        {
            Samples = samples,
            Height = 34,
            LineBrush = _theme.ForLevel(level, colorsEnabled),
            PlotBackground = _theme.PlotBackground,
            Margin = new Thickness(0, 3, 0, 0)
        };

        // Each chart owns its hover state and updates only its own summary line;
        // hovering one graph must not touch another. Rebuild() recreates both,
        // so a reopened panel always starts from the normal summary.
        chart.HoveredSampleChanged += sample =>
            summary.Text = sample is null
                ? defaultSummary
                : text.UsageHistoryHover(sample.RecordedAt, sample.RemainingPercent);
        panel.Children.Add(chart);

        return panel;
    }

    /// <summary>
    /// Connect actions for whichever providers are not connected yet. Wrapped
    /// like every other action row so a long label never overflows.
    /// </summary>
    private UIElement ConnectActions(Localizer text)
    {
        var row = new WrapPanel();

        if (!_controller.Settings.CodexConnected)
        {
            row.Children.Add(ActionButton(text.ConnectCodex, _controller.ConnectCodex));
        }

        if (!_controller.Settings.ClaudeConnected)
        {
            row.Children.Add(ActionButton(text.ConnectClaude, _controller.ConnectClaude));
        }

        return row;
    }

    /// <summary>
    /// Fills the docked action area. The buttons live in a WrapPanel and size
    /// themselves to their text, so a longer translation moves a button onto the
    /// next line instead of pushing it off the panel.
    /// </summary>
    private void BuildFooter(Localizer text)
    {
        _footer.Children.Add(ActionButton(text.Settings, () => SettingsRequested?.Invoke(this, EventArgs.Empty)));
        _footer.Children.Add(ActionButton(
            text.CopyDiagnostics,
            () => DiagnosticsRequested?.Invoke(this, EventArgs.Empty)));
        _footer.Children.Add(ActionButton(text.ExitUsageBar, () => ExitRequested?.Invoke(this, EventArgs.Empty)));
    }

    private Button ActionButton(string label, Action action)
    {
        var button = new Button
        {
            Content = label,
            // No fixed width: the button measures to its own text so nothing is
            // ever trimmed. MinWidth only keeps short labels from looking
            // cramped next to long ones.
            MinWidth = 88,
            Padding = new Thickness(12, 5, 12, 5),
            Margin = new Thickness(0, 0, 8, 8)
        };
        button.Click += (_, _) => action();
        return button;
    }

    private Button SelectorButton(string label, bool isSelected, Action action)
    {
        var button = new Button
        {
            Content = label,
            MinWidth = 72,
            Padding = new Thickness(12, 4, 12, 4),
            Margin = new Thickness(0, 0, 8, 8),
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
}
