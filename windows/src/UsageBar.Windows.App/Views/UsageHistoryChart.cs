using System.Windows;
using System.Windows.Media;
using UsageBar.Windows.Core.History;

// Pen is ambiguous between System.Drawing and System.Windows.Media; this file
// draws with WPF.
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
/// </summary>
internal sealed class UsageHistoryChart : FrameworkElement
{
    public static readonly DependencyProperty SamplesProperty = DependencyProperty.Register(
        nameof(Samples),
        typeof(IReadOnlyList<UsageHistorySample>),
        typeof(UsageHistoryChart),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

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

        var samples = Samples;
        if (samples is null || samples.Count == 0)
        {
            return;
        }

        var model = new UsageHistoryChartModel(samples);
        var points = model.DisplaySamples;
        if (points.Count == 0)
        {
            return;
        }

        var plot = new Rect(area.X + 3, area.Y + 3, area.Width - 6, area.Height - 6);
        var span = (points[^1].RecordedAt - points[0].RecordedAt).TotalSeconds;

        Point At(int index)
        {
            var sample = points[index];
            var x = points.Count == 1 || span <= 0
                ? plot.X + (plot.Width / 2)
                : plot.X + ((sample.RecordedAt - points[0].RecordedAt).TotalSeconds / span * plot.Width);

            // NormalizedY is 0 at the bottom of the range; screen Y grows down.
            var y = plot.Bottom - (model.NormalizedY(sample.RemainingPercent) * plot.Height);
            return new Point(x, y);
        }

        var pen = new Pen(LineBrush, 1.75)
        {
            LineJoin = PenLineJoin.Round,
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        pen.Freeze();

        if (points.Count == 1)
        {
            drawingContext.DrawEllipse(LineBrush, null, At(0), 2.5, 2.5);
            return;
        }

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
}
