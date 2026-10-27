using System.Runtime.Versioning;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Localization;
using ComboBox = System.Windows.Controls.ComboBox;

namespace UsageBar.Windows.App.Views;

[SupportedOSPlatform("windows")]
internal sealed class WeeklyHistoryWindow : Window
{
    private readonly UsageBarController _controller;
    private string? _selectedKey;
    private DateTimeOffset? _selectedAt;
    private Slider? _sampleSlider;
    private IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>>? _renderedHistory;
    private AppLanguage? _renderedLanguage;
    private bool? _renderedRecording;
    private bool? _renderedDark;

    public WeeklyHistoryWindow(UsageBarController controller)
    {
        _controller = controller;
        Width = 740;
        Height = 500;
        MinWidth = 640;
        MinHeight = 470;
        ShowInTaskbar = false;
        UseLayoutRounding = true;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");
        FontSize = 13;
        Closing += (_, e) => { e.Cancel = true; Hide(); };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { Hide(); e.Handled = true; } };
    }

    public void ShowHistory()
    {
        _controller.RetainWeeklyHistory(DateTimeOffset.Now);
        Rebuild();
        Show();
        Activate();
    }

    public void Rebuild(bool force = false)
    {
        var theme = AppTheme.Current();
        var text = _controller.Text;
        var history = _controller.WeeklyHistory;
        var recording = _controller.Settings.WeeklyHistoryEnabled ?? false;
        if (!force && ReferenceEquals(history, _renderedHistory) && text.Language == _renderedLanguage &&
            recording == _renderedRecording && theme.IsDark == _renderedDark) return;
        _renderedHistory = history;
        _renderedLanguage = text.Language;
        _renderedRecording = recording;
        _renderedDark = theme.IsDark;
        var restoreSliderFocus = _sampleSlider?.IsKeyboardFocusWithin == true;
        Title = text.WeeklyHistoryTitle;
        Background = theme.Background;
        Foreground = theme.Foreground;
        var root = new Grid { Margin = new Thickness(24) };
        foreach (var height in new[] { GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto })
            root.RowDefinitions.Add(new RowDefinition { Height = height });
        Content = root;

        TextBlock Label(string value, double size = 12, bool secondary = false) => new()
        {
            Text = value, FontSize = size, VerticalAlignment = VerticalAlignment.Center,
            Foreground = secondary ? theme.SecondaryForeground : theme.Foreground
        };
        DockPanel Row(UIElement leading, UIElement trailing)
        {
            var row = new DockPanel();
            DockPanel.SetDock(trailing, Dock.Right);
            row.Children.Add(trailing);
            row.Children.Add(leading);
            return row;
        }
        void Add(UIElement view, int row, Grid parent) { Grid.SetRow(view, row); parent.Children.Add(view); }

        var title = Label(text.WeeklyHistoryTitle, 20);
        title.FontWeight = FontWeights.SemiBold;
        var status = Label((_controller.Settings.WeeklyHistoryEnabled ?? false) ? text.WeeklyHistoryRecording : text.WeeklyHistoryPaused, 11, true);
        status.ToolTip = text.WeeklyHistoryHelp;
        var header = Row(title, status);
        header.Margin = new Thickness(0, 0, 0, 18);
        Add(header, 0, root);

        var keys = new List<string> { "Codex|weekly", "Claude Code|weekly" };
        if (_selectedKey is null || !keys.Contains(_selectedKey)) _selectedKey = keys.FirstOrDefault();
        var picker = new ComboBox { Width = 180, HorizontalAlignment = System.Windows.HorizontalAlignment.Left, IsEnabled = keys.Count > 0 };
        foreach (var key in keys) picker.Items.Add(new ComboBoxItem { Content = key.Split('|')[0], Tag = key });
        picker.SelectedIndex = _selectedKey is null ? -1 : keys.IndexOf(_selectedKey);
        AutomationProperties.SetName(picker, text.HistorySeries);
        picker.SelectionChanged += (_, _) =>
        {
            _selectedKey = (picker.SelectedItem as ComboBoxItem)?.Tag as string;
            _selectedAt = null;
            Rebuild(force: true);
        };
        var samples = _selectedKey is not null && history.TryGetValue(_selectedKey, out var series)
            ? series : Array.Empty<UsageHistorySample>();
        var model = new UsageHistoryChartModel(samples, startsAtLatestReset: false);
        var range = Label(text.UsageHistoryRange(model.RecordedDuration), secondary: true);
        range.Visibility = samples.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        var toolbar = Row(picker, range);
        toolbar.Margin = new Thickness(0, 0, 0, 18);
        Add(toolbar, 1, root);

        var card = new Grid { Margin = new Thickness(20, 18, 20, 18) };
        foreach (var height in new[] { GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto })
            card.RowDefinitions.Add(new RowDefinition { Height = height });
        Add(Label(text.HistoryRemaining, 11, true), 0, card);
        var percent = Label("—", 34);
        percent.FontWeight = FontWeights.SemiBold;
        var readout = Label(text.NoData, secondary: true);
        var hero = Row(percent, readout);
        hero.Margin = new Thickness(0, 6, 0, 12);
        Add(hero, 1, card);

        var plot = new Grid { Margin = new Thickness(0, 6, 0, 12), MinHeight = 120 };
        var chart = new UsageHistoryChart
        {
            StartsAtLatestReset = false, Samples = samples,
            LineBrush = theme.Foreground
        };
        if (samples.Count == 0)
        {
            var empty = Label(text.WeeklyHistoryEmpty, 13, true);
            empty.TextWrapping = TextWrapping.Wrap;
            empty.TextAlignment = TextAlignment.Center;
            empty.HorizontalAlignment = System.Windows.HorizontalAlignment.Center;
            empty.MaxWidth = 360;
            plot.Children.Add(empty);
        }
        else
        {
            plot.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(34) });
            plot.ColumnDefinitions.Add(new ColumnDefinition());
            foreach (var (value, alignment) in new[] { (100, VerticalAlignment.Top), (50, VerticalAlignment.Center), (0, VerticalAlignment.Bottom) })
                plot.Children.Add(new TextBlock { Text = $"{value}", FontSize = 10, VerticalAlignment = alignment, Foreground = theme.SecondaryForeground });
            Grid.SetColumn(chart, 1);
            plot.Children.Add(chart);
        }
        AutomationProperties.SetName(chart, _selectedKey?.Split('|')[0] ?? text.WeeklyHistoryTitle);
        Add(plot, 2, card);
        if (samples.Count > 0)
            Add(Row(Label(text.HistoryDate(samples[0].RecordedAt), 10, true), Label(text.HistoryDate(samples[^1].RecordedAt), 10, true)), 3, card);
        Add(new Border
        {
            Background = theme.Surface, BorderBrush = theme.Border, BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12), Child = card
        }, 2, root);

        var slider = new Slider
        {
            Minimum = 0, Maximum = Math.Max(1, samples.Count - 1),
            Value = model.SelectionIndex(_selectedAt), TickFrequency = 1,
            IsSnapToTickEnabled = true, SmallChange = 1, LargeChange = 10,
            IsEnabled = samples.Count > 0, Width = 140, VerticalAlignment = VerticalAlignment.Center,
            ToolTip = text.HistorySample
        };
        _sampleSlider = slider;
        if (restoreSliderFocus)
            slider.Loaded += (_, _) => { if (IsActive) slider.Focus(); };
        AutomationProperties.SetName(slider, text.HistorySample);
        void ShowSample(UsageHistorySample? sample)
        {
            percent.Text = sample is null ? "—" : text.Language == AppLanguage.Turkish ? $"%{sample.RemainingPercent}" : $"{sample.RemainingPercent}%";
            readout.Text = sample is null ? text.NoData : text.HistoryDate(sample.RecordedAt);
            AutomationProperties.SetName(percent, $"{text.HistoryRemaining}: {percent.Text}");
            var accessible = sample is null ? text.NoData : $"{readout.Text} · {text.Remaining(sample.RemainingPercent)}";
            AutomationProperties.SetHelpText(chart, accessible);
            AutomationProperties.SetHelpText(slider, accessible);
        }
        UsageHistorySample? Selected() => samples.Count == 0 ? null : model.DisplaySamples[Math.Clamp((int)Math.Round(slider.Value), 0, samples.Count - 1)];
        slider.ValueChanged += (_, _) =>
        {
            _selectedAt = (int)Math.Round(slider.Value) >= samples.Count - 1 ? null : Selected()?.RecordedAt;
            ShowSample(Selected());
        };
        chart.HoveredSampleChanged += sample => ShowSample(sample ?? Selected());
        ShowSample(Selected());
        var local = Label(text.HistoryLocal, 11, true);
        local.ToolTip = text.WeeklyHistoryHelp;
        var footer = Row(local, slider);
        footer.Margin = new Thickness(0, 16, 0, 0);
        Add(footer, 3, root);
    }
}
