using System.Windows;
using System.Windows.Media;
using UsageBar.Windows.Core.History;

// Pen is ambiguous between System.Drawing and System.Windows.Media, and
// MouseEventArgs between Windows Forms (globally imported for NotifyIcon) and
// WPF input; this file draws and tracks the pointer with WPF.
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Pen = System.Windows.Media.Pen;

namespace UsageBar.Windows.App.Views;

/// <summary>
/// The mini history chart, drawn directly rather than pulled in from a charting
/// library.
///
/// It shows the current reset arc only: <see cref="UsageHistoryChartModel"/>
/// restarts the series at the most recent reset, so each quota period reads as
/// one clean line instead of a saw-tooth across the whole retained history. The
/// vertical range adapts so a few points of real movement stay visible.
///
/// Moving the pointer across the plot snaps to the nearest recorded sample and
/// reports it through <see cref="HoveredSampleChanged"/>; the chart draws a
/// guide and a larger point there but never formats text itself.
/// </summary>
internal sealed class UsageHistoryChart : FrameworkElement
{
    public static readonly DependencyProperty SamplesProperty = DependencyProperty.Register(
        nameof(Samples),
        typeof(IReadOnlyList<UsageHistorySample>),
        typeof(UsageHistoryChart),
        new FrameworkPropertyMetadata(
            null,
            FrameworkPropertyMetadataOptions.AffectsRender,
            OnSamplesChanged));

    public static readonly DependencyProperty LineBrushProperty = DependencyProperty.Register(
        nameof(LineBrush),
        typeof(Brush),
        typeof(UsageHistoryChart),
        new FrameworkPropertyMetadata(Brushes.SteelBlue, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty PlotBackgroundProperty = DependencyProperty.Register(
        nameof(PlotBackground),
        typeof(Brush),
        typeof(UsageHistoryChart),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public IReadOnlyList<UsageHistorySample>? Samples
    {
        get => (IReadOnlyList<UsageHistorySample>?)GetValue(SamplesProperty);
        set => SetValue(SamplesProperty, value);
    }

    public Brush LineBrush
    {
        get => (Brush)GetValue(LineBrushProperty);
        set => SetValue(LineBrushProperty, value);
    }

    public Brush? PlotBackground
    {
        get => (Brush?)GetValue(PlotBackgroundProperty);
        set => SetValue(PlotBackgroundProperty, value);
    }

    /// <summary>
    /// Raised when the pointer snaps to a different drawn sample, with
    /// <c>null</c> when the pointer leaves the plot or the series changes. The
    /// chart reports data only; the panel owns the localized text.
    /// </summary>
    public event Action<UsageHistorySample?>? HoveredSampleChanged;

    /// <summary>
    /// Built once per series instead of on every render and mouse move, and
    /// shared by drawing and hit selection so both describe the same line.
    /// </summary>
    private UsageHistoryChartModel? _model;

    private UsageHistorySample? _hoveredSample;

    private static void OnSamplesChanged(
        DependencyObject dependencyObject,
        DependencyPropertyChangedEventArgs eventArgs)
    {
        var chart = (UsageHistoryChart)dependencyObject;
        var samples = eventArgs.NewValue as IReadOnlyList<UsageHistorySample>;
        chart._model = samples is { Count: > 0 } ? new UsageHistoryChartModel(samples) : null;

        // A new series invalidates any previous selection, so the panel falls
        // back to its normal summary. AffectsRender already schedules the
        // redraw for the property itself.
        chart.SetHoveredSample(null);
    }

    /// <summary>
    /// Derived from the current size on every use, so a resize, a DPI change or
    /// a move to another monitor can never leave stale coordinates behind.
    /// </summary>
    private Rect PlotRect()
    {
        var width = Math.Max(0, ActualWidth - 6);
        var height = Math.Max(0, ActualHeight - 6);
        return new Rect(3, 3, width, height);
    }

    /// <summary>
    /// The single timestamp-to-X / percentage-to-Y mapping shared by the line,
    /// the latest marker and the hover guide and point.
    /// </summary>
    private static Point PointForSample(UsageHistorySample sample, UsageHistoryChartModel model, Rect plot)
    {
        var points = model.DisplaySamples;
        var span = (points[^1].RecordedAt - points[0].RecordedAt).TotalSeconds;
        var x = points.Count == 1 || span <= 0
            ? plot.X + (plot.Width / 2)
            : plot.X + ((sample.RecordedAt - points[0].RecordedAt).TotalSeconds / span * plot.Width);

        // NormalizedY is 0 at the bottom of the range; screen Y grows down.
        var y = plot.Bottom - (model.NormalizedY(sample.RemainingPercent) * plot.Height);
        return new Point(x, y);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        ArgumentNullException.ThrowIfNull(e);
        base.OnMouseMove(e);

        var model = _model;
        if (model is null || model.DisplaySamples.Count == 0)
        {
            SetHoveredSample(null);
            return;
        }

        var plot = PlotRect();
        if (plot.Width <= 0 || plot.Height <= 0)
        {
            SetHoveredSample(null);
            return;
        }

        // WPF pointer positions and layout geometry share the same
        // device-independent units, so no manual DPI conversion belongs here.
        var position = e.GetPosition(this);
        if (!plot.Contains(position))
        {
            SetHoveredSample(null);
            return;
        }

        SetHoveredSample(model.NearestDisplaySample((position.X - plot.X) / plot.Width));
    }

    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        SetHoveredSample(null);
    }

    private void SetHoveredSample(UsageHistorySample? sample)
    {
        if (_hoveredSample == sample)
        {
            return;
        }

        _hoveredSample = sample;
        InvalidateVisual();
        HoveredSampleChanged?.Invoke(sample);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        ArgumentNullException.ThrowIfNull(drawingContext);
        base.OnRender(drawingContext);

        var area = new Rect(0, 0, ActualWidth, ActualHeight);
        if (area.Width <= 2 || area.Height <= 2)
        {
            return;
        }

        if (PlotBackground is { } background)
        {
            drawingContext.DrawRoundedRectangle(background, null, area, 4, 4);
        }

        // A transparent fill costs nothing visually but makes the whole control
        // hit-testable, so the pointer is still tracked over the padding and
        // over the rounded corners the background leaves out.
        drawingContext.DrawRectangle(Brushes.Transparent, null, area);

        var model = _model;
        if (model is null)
        {
            return;
        }

        var points = model.DisplaySamples;
        if (points.Count == 0)
        {
            return;
        }

        var plot = PlotRect();
        if (plot.Width <= 0 || plot.Height <= 0)
        {
            return;
        }

        Point At(int index) => PointForSample(points[index], model, plot);

        var pen = new Pen(LineBrush, 1.75)
        {
            LineJoin = PenLineJoin.Round,
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        pen.Freeze();

        // Resolved before the line is drawn so the guide can sit under it.
        Point? hoveredPoint = _hoveredSample is { } hovered
            ? PointForSample(hovered, model, plot)
            : null;

        if (hoveredPoint is { } guidePoint)
        {
            var guidePen = new Pen(LineBrush, 0.75);
            guidePen.Freeze();

            // PushOpacity keeps the guide subtle without cloning or mutating the
            // theme brush, which may be shared and frozen.
            drawingContext.PushOpacity(0.35);
            drawingContext.DrawLine(
                guidePen,
                new Point(guidePoint.X, plot.Top),
                new Point(guidePoint.X, plot.Bottom));
            drawingContext.Pop();
        }

        if (points.Count == 1)
        {
            drawingContext.DrawEllipse(LineBrush, null, At(0), 2.5, 2.5);
        }
        else
        {
            var geometry = new StreamGeometry();
            using (var context = geometry.Open())
            {
                context.BeginFigure(At(0), isFilled: false, isClosed: false);
                for (var index = 1; index < points.Count; index++)
                {
                    context.LineTo(At(index), isStroked: true, isSmoothJoin: true);
                }
            }

            geometry.Freeze();
            drawingContext.DrawGeometry(null, pen, geometry);
            drawingContext.DrawEllipse(LineBrush, null, At(points.Count - 1), 2.5, 2.5);
        }

        // Drawn last so it reads on top of the line and of the latest marker,
        // which stays visible underneath it.
        if (hoveredPoint is { } markerPoint)
        {
            drawingContext.DrawEllipse(LineBrush, null, markerPoint, 4, 4);
        }
    }
}
