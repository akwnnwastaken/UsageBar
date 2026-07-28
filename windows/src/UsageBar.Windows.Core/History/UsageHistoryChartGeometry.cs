using System.Globalization;

namespace UsageBar.Windows.Core.History;

/// <summary>A point on the chart, in device-independent units.</summary>
public readonly record struct UsageHistoryChartPoint(double X, double Y)
{
    public override string ToString() =>
        string.Create(CultureInfo.InvariantCulture, $"({X}, {Y})");
}

/// <summary>
/// The chart's plot rectangle, in device-independent units.
///
/// Deliberately not <c>System.Windows.Rect</c>: this project must stay free of
/// WPF so the geometry can be tested on any host. The WPF view converts at the
/// drawing boundary.
/// </summary>
public readonly record struct UsageHistoryChartRect(double X, double Y, double Width, double Height)
{
    public double Left => X;

    public double Top => Y;

    public double Right => X + Width;

    public double Bottom => Y + Height;

    /// <summary>
    /// Whether the point falls inside the rectangle, matching
    /// <c>System.Windows.Rect.Contains(Point)</c> exactly.
    ///
    /// WPF documents that method as "inclusive of the edges" and implements it
    /// as <c>x >= X &amp;&amp; x - Width &lt;= X &amp;&amp; y >= Y &amp;&amp; y - Height &lt;= Y</c>,
    /// after rejecting an empty rectangle (<c>Width &lt; 0</c>). The subtraction
    /// form, rather than <c>x &lt;= X + Width</c>, is what keeps infinite
    /// rectangles well behaved, and it is reproduced here so hit testing cannot
    /// drift from the framework. A non-finite coordinate fails every
    /// comparison and is therefore outside.
    /// </summary>
    public bool Contains(double x, double y)
    {
        if (Width < 0 || Height < 0)
        {
            return false;
        }

        return x >= X && x - Width <= X && y >= Y && y - Height <= Y;
    }

    public override string ToString() =>
        string.Create(CultureInfo.InvariantCulture, $"({X}, {Y}, {Width}, {Height})");
}

/// <summary>
/// Where the usage-history chart draws its samples, and which sample a pointer
/// position refers to.
///
/// The selection rule itself belongs to <see cref="UsageHistoryChartModel"/>;
/// this type only converts between coordinates and that model. Keeping it here
/// rather than in the WPF view means the mapping the chart draws with can be
/// verified exactly, with no dispatcher, visual tree or mouse input.
///
/// Nothing is cached: every call derives from the size it is given, so a
/// resize, a DPI change or a move to another monitor cannot leave stale
/// coordinates behind. WPF layout and pointer positions already share
/// device-independent units, so no DPI conversion belongs anywhere here.
/// </summary>
public sealed class UsageHistoryChartGeometry
{
    /// <summary>
    /// The plot is inset on every side so the line and its end markers are not
    /// clipped, and so the rounded background stays visible around them.
    /// </summary>
    public const double PlotInset = 3;

    public UsageHistoryChartGeometry(UsageHistoryChartModel model)
    {
        ArgumentNullException.ThrowIfNull(model);
        Model = model;
    }

    public UsageHistoryChartModel Model { get; }

    /// <summary>
    /// The plot rectangle for a control of this size, derived fresh on every
    /// call. Width and height clamp to zero independently, so a control too
    /// small for the inset never produces a negative dimension.
    /// </summary>
    public UsageHistoryChartRect PlotRect(double actualWidth, double actualHeight) =>
        new(
            PlotInset,
            PlotInset,
            Math.Max(0, actualWidth - (PlotInset * 2)),
            Math.Max(0, actualHeight - (PlotInset * 2)));

    /// <summary>
    /// Where <paramref name="sample"/> sits inside <paramref name="plot"/>.
    ///
    /// X comes from elapsed time, not array position, because samples are not
    /// evenly spaced: the first displayed sample sits on the left edge, the
    /// last on the right edge, and the rest fall proportionally between them. A
    /// lone sample — or a series whose samples share one timestamp, and so
    /// spans no time — is centred instead.
    ///
    /// Y is measured down from the bottom, because screen Y grows downward
    /// while <see cref="UsageHistoryChartModel.NormalizedY"/> is 0 at the
    /// bottom of the range. That model call already clamps the percentage and
    /// applies the chart's adaptive vertical bounds.
    /// </summary>
    /// <exception cref="InvalidOperationException">
    /// Nothing is drawn, so there is no position to report. Callers draw only
    /// after checking <see cref="UsageHistoryChartModel.DisplaySamples"/>.
    /// </exception>
    public UsageHistoryChartPoint PointForSample(UsageHistorySample sample, UsageHistoryChartRect plot)
    {
        var points = Model.DisplaySamples;
        if (points.Count == 0)
        {
            throw new InvalidOperationException(
                "The chart has no displayed samples, so a sample has no position.");
        }

        var span = (points[^1].RecordedAt - points[0].RecordedAt).TotalSeconds;
        var x = points.Count == 1 || span <= 0
            ? plot.X + (plot.Width / 2)
            : plot.X + ((sample.RecordedAt - points[0].RecordedAt).TotalSeconds / span * plot.Width);

        var y = plot.Bottom - (Model.NormalizedY(sample.RemainingPercent) * plot.Height);
        return new UsageHistoryChartPoint(x, y);
    }

    /// <summary>
    /// The sample a pointer at (<paramref name="pointerX"/>,
    /// <paramref name="pointerY"/>) refers to, or <c>null</c> when nothing is
    /// hovered.
    ///
    /// Eligibility is the **plot rectangle**, not the whole control: the
    /// surrounding inset is hit-testable — the view fills the control with a
    /// transparent rectangle so the pointer keeps being tracked there — but it
    /// selects nothing. A non-finite position fails containment and reports
    /// nothing.
    /// </summary>
    public UsageHistorySample? HoveredSample(
        double pointerX,
        double pointerY,
        double actualWidth,
        double actualHeight)
    {
        if (Model.DisplaySamples.Count == 0)
        {
            return null;
        }

        var plot = PlotRect(actualWidth, actualHeight);
        if (plot.Width <= 0 || plot.Height <= 0)
        {
            return null;
        }

        if (!plot.Contains(pointerX, pointerY))
        {
            return null;
        }

        return Model.NearestDisplaySample((pointerX - plot.X) / plot.Width);
    }
}
