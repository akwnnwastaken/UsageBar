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
    /// shared by drawing and hit selection so both describe the same line. The
    /// seam owns every coordinate calculation, so the drawn line and the hover
    /// hit test can never disagree; the model it wraps stays reachable through
    /// <see cref="UsageHistoryChartGeometry.Model"/>.
    /// </summary>
    private UsageHistoryChartGeometry? _chartGeometry;

    private UsageHistorySample? _hoveredSample;

    private static void OnSamplesChanged(
        DependencyObject dependencyObject,
        DependencyPropertyChangedEventArgs eventArgs)
    {
        var chart = (UsageHistoryChart)dependencyObject;
        var samples = eventArgs.NewValue as IReadOnlyList<UsageHistorySample>;
        chart._chartGeometry = samples is { Count: > 0 }
            ? new UsageHistoryChartGeometry(new UsageHistoryChartModel(samples))
            : null;

        // A new series invalidates any previous selection, so the panel falls
        // back to its normal summary. AffectsRender already schedules the
        // redraw for the property itself.
        chart.SetHoveredSample(null);
    }

    /// <summary>
    /// The plot rectangle as WPF geometry. Derived from the current size on
    /// every use, so a resize, a DPI change or a move to another monitor can
    /// never leave stale coordinates behind.
    /// </summary>
    private static Rect ToRect(UsageHistoryChartRect plot) =>
        new(plot.X, plot.Y, plot.Width, plot.Height);

    private static Point ToPoint(UsageHistoryChartPoint point) => new(point.X, point.Y);

    protected override void OnMouseMove(MouseEventArgs e)
    {
        ArgumentNullException.ThrowIfNull(e);
        base.OnMouseMove(e);

        if (_chartGeometry is not { } chartGeometry)
        {
            SetHoveredSample(null);
            return;
        }

        // WPF pointer positions and layout geometry share the same
        // device-independent units, so no manual DPI conversion belongs here.
        // Which sample the position refers to — including whether it is over
        // the plot at all — is decided by the geometry.
        var position = e.GetPosition(this);
        SetHoveredSample(chartGeometry.HoveredSample(position.X, position.Y, ActualWidth, ActualHeight));
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

        if (_chartGeometry is not { } chartGeometry)
        {
            return;
        }

        var points = chartGeometry.Model.DisplaySamples;
        if (points.Count == 0)
        {
            return;
        }

        var plotRect = chartGeometry.PlotRect(ActualWidth, ActualHeight);
        if (plotRect.Width <= 0 || plotRect.Height <= 0)
        {
            return;
        }

        var plot = ToRect(plotRect);

        Point At(int index) => ToPoint(chartGeometry.PointForSample(points[index], plotRect));

        var pen = new Pen(LineBrush, 1.75)
        {
            LineJoin = PenLineJoin.Round,
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        pen.Freeze();

        // Resolved before the line is drawn so the guide can sit under it.
        Point? hoveredPoint = _hoveredSample is { } hovered
            ? ToPoint(chartGeometry.PointForSample(hovered, plotRect))
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
