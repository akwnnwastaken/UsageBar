using UsageBar.Windows.Core.History;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// The coordinate mapping the Windows history chart draws with.
///
/// <see cref="UsageHistoryChartModel"/> already decides *which* sample a
/// normalized position refers to, and that rule is covered in
/// <see cref="UsageHistoryTests"/>. These tests cover the part that used to live
/// inside the WPF view and could not be checked without a visual tree and real
/// pointer input: the plot rectangle, where a sample lands inside it, and how a
/// pointer position becomes a selection.
///
/// The numbers are deliberately literal. If the plot inset or the placement
/// formula ever change, that is a visible change and these must be updated
/// consciously. Several assertions exist specifically to stop the Windows
/// behaviour being "aligned" with macOS, which differs on purpose.
/// </summary>
public sealed class UsageHistoryChartGeometryTests
{
    private static readonly DateTimeOffset Base = new(2026, 7, 26, 12, 0, 0, TimeSpan.Zero);

    /// <summary>The size the panel actually builds the chart at.</summary>
    private const double Width = 180;
    private const double Height = 34;

    private static UsageHistorySample Sample(double offsetSeconds, int percent) =>
        new(Base.AddSeconds(offsetSeconds), percent);

    private static UsageHistoryChartGeometry Geometry(params (double Offset, int Percent)[] points) =>
        new(new UsageHistoryChartModel(points.Select(p => Sample(p.Offset, p.Percent)).ToList()));

    // MARK: - Plot rectangle

    [Fact]
    public void ThePlotIsInsetByThreeDipsOnEverySide()
    {
        Assert.Equal(3, UsageHistoryChartGeometry.PlotInset);

        var plot = Geometry((0, 50)).PlotRect(Width, Height);

        Assert.Equal(3, plot.X);
        Assert.Equal(3, plot.Y);
        Assert.Equal(174, plot.Width);
        Assert.Equal(28, plot.Height);
        Assert.Equal(3, plot.Left);
        Assert.Equal(3, plot.Top);
        Assert.Equal(177, plot.Right);
        Assert.Equal(31, plot.Bottom);
    }

    /// <summary>
    /// Layout sizes are not integers in general. Nothing rounds to pixels: WPF
    /// units are already device independent, and rounding here would fight the
    /// renderer at fractional scale factors.
    /// </summary>
    [Fact]
    public void FractionalDimensionsAreNotRounded()
    {
        var plot = Geometry((0, 50)).PlotRect(181.75, 33.5);

        Assert.Equal(175.75, plot.Width, 10);
        Assert.Equal(27.5, plot.Height, 10);
        Assert.Equal(178.75, plot.Right, 10);
        Assert.Equal(30.5, plot.Bottom, 10);
    }

    /// <summary>
    /// Nothing is cached, so a resized or re-DPI'd control is measured freshly.
    /// A stale rectangle would put the line and the hit test in different
    /// places.
    /// </summary>
    [Fact]
    public void ThePlotIsRederivedForEverySize()
    {
        var chart = Geometry((0, 50), (120, 40));

        Assert.Equal(174, chart.PlotRect(Width, Height).Width);
        Assert.Equal(84, chart.PlotRect(90, 20).Width);
        Assert.Equal(294, chart.PlotRect(300, 60).Width);
        // ...and the first answer is unaffected by the later calls.
        Assert.Equal(174, chart.PlotRect(Width, Height).Width);
    }

    [Theory]
    [InlineData(0, 0, 0, 0)]
    [InlineData(6, 6, 0, 0)]
    [InlineData(5, 40, 0, 34)]      // width clamps, height does not
    [InlineData(40, 5, 34, 0)]      // height clamps, width does not
    [InlineData(3, 3, 0, 0)]
    public void TinyDimensionsClampToZeroIndependently(
        double actualWidth, double actualHeight, double expectedWidth, double expectedHeight)
    {
        var plot = Geometry((0, 50)).PlotRect(actualWidth, actualHeight);

        Assert.Equal(expectedWidth, plot.Width);
        Assert.Equal(expectedHeight, plot.Height);
        Assert.True(plot.Width >= 0);
        Assert.True(plot.Height >= 0);
    }

    // MARK: - Sample placement

    [Fact]
    public void FirstAndLastSamplesSitOnThePlotEdges()
    {
        var chart = Geometry((0, 50), (120, 46), (240, 44));
        var plot = chart.PlotRect(Width, Height);
        var drawn = chart.Model.DisplaySamples;

        Assert.Equal(plot.Left, chart.PointForSample(drawn[0], plot).X, 10);
        Assert.Equal(plot.Right, chart.PointForSample(drawn[2], plot).X, 10);
    }

    /// <summary>
    /// X follows elapsed time, not array position. The middle sample here sits
    /// five sixths of the way along in time; an index-based chart would put it
    /// at the halfway point.
    /// </summary>
    [Fact]
    public void IntermediateSamplesArePlacedByElapsedTimeNotIndex()
    {
        var chart = Geometry((0, 50), (600, 46), (720, 44));
        var plot = chart.PlotRect(Width, Height);
        var drawn = chart.Model.DisplaySamples;

        var middle = chart.PointForSample(drawn[1], plot).X;

        Assert.Equal(plot.X + (plot.Width * 600.0 / 720.0), middle, 10);
        // The index-based answer would be the centre; it must not be that.
        Assert.True(Math.Abs(middle - (plot.X + (plot.Width / 2))) > 1);
    }

    [Fact]
    public void ASingleSampleIsCentredHorizontally()
    {
        var chart = Geometry((0, 42));
        var plot = chart.PlotRect(Width, Height);

        var point = chart.PointForSample(chart.Model.DisplaySamples[0], plot);

        Assert.Equal(plot.X + (plot.Width / 2), point.X, 10);
        Assert.Equal(90, point.X, 10);
    }

    /// <summary>
    /// Windows centres a zero-span series. macOS instead collapses such samples
    /// onto its left edge — a deliberate platform difference, so this asserts
    /// the Windows rule and explicitly rejects both the macOS behaviour and even
    /// index spacing.
    /// </summary>
    [Fact]
    public void DuplicateTimestampsStayCentredRatherThanCollapsingOrSpreading()
    {
        var chart = Geometry((0, 50), (0, 44), (0, 47));
        var plot = chart.PlotRect(Width, Height);
        var centre = plot.X + (plot.Width / 2);

        Assert.True(chart.Model.DisplaySamples.Count > 1);
        foreach (var sample in chart.Model.DisplaySamples)
        {
            var x = chart.PointForSample(sample, plot).X;
            Assert.Equal(centre, x, 10);
            Assert.NotEqual(plot.Left, x);   // not the macOS collapse-to-left rule
            Assert.NotEqual(plot.Right, x);  // not evenly spread across the plot
        }
    }

    [Fact]
    public void AnEmptyChartHasNoSamplePosition()
    {
        var empty = new UsageHistoryChartGeometry(
            new UsageHistoryChartModel(Array.Empty<UsageHistorySample>()));
        var plot = empty.PlotRect(Width, Height);

        Assert.Empty(empty.Model.DisplaySamples);
        Assert.Throws<InvalidOperationException>(
            () => empty.PointForSample(Sample(0, 50), plot));
    }

    // MARK: - Percentage to Y

    /// <summary>
    /// Screen Y grows downward while NormalizedY is 0 at the bottom of the
    /// range, so a higher remaining percentage must produce a *smaller* Y.
    /// </summary>
    [Fact]
    public void PercentageMapsUpThePlotWithScreenYGrowingDownward()
    {
        var chart = Geometry((0, 33));
        var plot = chart.PlotRect(Width, Height);
        // A flat series pads to a 10-point window around the value.
        Assert.Equal(28, chart.Model.LowerBound);
        Assert.Equal(38, chart.Model.UpperBound);

        double Y(int percent) => chart.PointForSample(Sample(0, percent), plot).Y;

        Assert.Equal(plot.Bottom, Y(28), 10);   // lower bound -> bottom
        Assert.Equal(plot.Top, Y(38), 10);      // upper bound -> top
        Assert.Equal(plot.Y + (plot.Height / 2), Y(33), 10);
        Assert.True(Y(36) < Y(30));             // higher percentage is higher up
    }

    /// <summary>
    /// The model clamps the *percentage* into 0...100 before projecting; the
    /// projected position itself is deliberately not clamped again here.
    /// </summary>
    [Fact]
    public void PercentageIsClampedByTheModelBeforeProjection()
    {
        var chart = Geometry((0, 33));
        var plot = chart.PlotRect(Width, Height);

        double Y(int percent) => chart.PointForSample(Sample(0, percent), plot).Y;

        Assert.Equal(Y(0), Y(-40), 10);
        Assert.Equal(Y(0), Y(-1000), 10);
        Assert.Equal(Y(100), Y(140), 10);
        Assert.Equal(Y(100), Y(1000), 10);
    }

    /// <summary>
    /// What actually gets drawn always fits: the vertical window is computed
    /// from the displayed samples themselves.
    /// </summary>
    [Fact]
    public void EveryDrawnSampleLandsInsideThePlot()
    {
        var charts = new[]
        {
            Geometry((0, 100), (120, 60), (240, 3)),
            Geometry((0, 42)),
            Geometry((0, 50), (120, 49), (240, 50)),
            Geometry((0, 0), (120, 0)),
        };

        foreach (var chart in charts)
        {
            var plot = chart.PlotRect(Width, Height);
            foreach (var sample in chart.Model.DisplaySamples)
            {
                var point = chart.PointForSample(sample, plot);
                Assert.InRange(point.X, plot.Left - 1e-9, plot.Right + 1e-9);
                Assert.InRange(point.Y, plot.Top - 1e-9, plot.Bottom + 1e-9);
            }
        }
    }

    // MARK: - Pointer to sample

    [Fact]
    public void HoverReturnsNullForAnEmptyChart()
    {
        var empty = new UsageHistoryChartGeometry(
            new UsageHistoryChartModel(Array.Empty<UsageHistorySample>()));

        Assert.Null(empty.HoveredSample(90, 17, Width, Height));
        Assert.Null(empty.HoveredSample(3, 3, Width, Height));
    }

    [Fact]
    public void ASingleSampleAnswersEveryPositionInsideThePlot()
    {
        var chart = Geometry((0, 42));

        for (var x = 3.0; x <= 177; x += 17.4)
        {
            Assert.Equal(42, chart.HoveredSample(x, 17, Width, Height)?.RemainingPercent);
        }
    }

    [Fact]
    public void HoverSelectsTheSampleUnderThePointer()
    {
        var chart = Geometry((0, 50), (120, 46), (240, 44));
        var plot = chart.PlotRect(Width, Height);

        Assert.Equal(50, chart.HoveredSample(plot.Left, 17, Width, Height)?.RemainingPercent);
        Assert.Equal(46, chart.HoveredSample(plot.X + (plot.Width / 2), 17, Width, Height)?.RemainingPercent);
        Assert.Equal(44, chart.HoveredSample(plot.Right, 17, Width, Height)?.RemainingPercent);
    }

    /// <summary>
    /// Eligibility is the plot rectangle, not the whole control. The view fills
    /// the control with a transparent rectangle so the pointer is still tracked
    /// over the 3-DIP padding, but that padding must select nothing. macOS
    /// deliberately differs here, using its full view bounds.
    /// </summary>
    [Theory]
    [InlineData(2.5, 17)]     // left padding
    [InlineData(177.5, 17)]   // right padding
    [InlineData(90, 2.5)]     // top padding
    [InlineData(90, 31.5)]    // bottom padding
    [InlineData(0, 0)]        // corner
    [InlineData(179.9, 33.9)] // opposite corner, still inside the control
    public void ThePaddingAroundThePlotSelectsNothing(double pointerX, double pointerY)
    {
        var chart = Geometry((0, 50), (120, 46), (240, 44));

        Assert.Null(chart.HoveredSample(pointerX, pointerY, Width, Height));
    }

    /// <summary>
    /// System.Windows.Rect.Contains is documented as "inclusive of the edges"
    /// and implemented as <c>x >= X &amp;&amp; x - Width &lt;= X &amp;&amp; ...</c>
    /// (dotnet/wpf, WindowsBase/System/Windows/Rect.cs). All four edges
    /// therefore select, and one unit beyond any of them does not. This differs
    /// from the half-open CGRect rule macOS uses.
    /// </summary>
    [Fact]
    public void EveryPlotEdgeIsInclusiveJustAsWpfRectContainsIs()
    {
        var chart = Geometry((0, 50), (120, 46), (240, 44));
        var plot = chart.PlotRect(Width, Height);
        var midY = plot.Y + (plot.Height / 2);
        var midX = plot.X + (plot.Width / 2);

        // On the edges: contained.
        Assert.True(plot.Contains(plot.Left, midY));
        Assert.True(plot.Contains(plot.Right, midY));
        Assert.True(plot.Contains(midX, plot.Top));
        Assert.True(plot.Contains(midX, plot.Bottom));
        Assert.NotNull(chart.HoveredSample(plot.Left, midY, Width, Height));
        Assert.NotNull(chart.HoveredSample(plot.Right, midY, Width, Height));
        Assert.NotNull(chart.HoveredSample(midX, plot.Top, Width, Height));
        Assert.NotNull(chart.HoveredSample(midX, plot.Bottom, Width, Height));

        // Just outside any edge: not contained.
        Assert.False(plot.Contains(plot.Left - 0.001, midY));
        Assert.False(plot.Contains(plot.Right + 0.001, midY));
        Assert.False(plot.Contains(midX, plot.Top - 0.001));
        Assert.False(plot.Contains(midX, plot.Bottom + 0.001));
        Assert.Null(chart.HoveredSample(plot.Left - 0.001, midY, Width, Height));
        Assert.Null(chart.HoveredSample(plot.Right + 0.001, midY, Width, Height));
        Assert.Null(chart.HoveredSample(midX, plot.Top - 0.001, Width, Height));
        Assert.Null(chart.HoveredSample(midX, plot.Bottom + 0.001, Width, Height));
    }

    [Theory]
    [InlineData(6, 34)]     // zero plot width
    [InlineData(180, 6)]    // zero plot height
    [InlineData(6, 6)]      // both zero
    [InlineData(0, 0)]
    [InlineData(3, 3)]
    public void ADegeneratePlotSelectsNothing(double actualWidth, double actualHeight)
    {
        var chart = Geometry((0, 50), (120, 46));

        Assert.Null(chart.HoveredSample(3, 3, actualWidth, actualHeight));
        Assert.Null(chart.HoveredSample(0, 0, actualWidth, actualHeight));
    }

    [Theory]
    [InlineData(double.NaN, 17)]
    [InlineData(90, double.NaN)]
    [InlineData(double.NaN, double.NaN)]
    [InlineData(double.PositiveInfinity, 17)]
    [InlineData(double.NegativeInfinity, 17)]
    [InlineData(90, double.PositiveInfinity)]
    [InlineData(90, double.NegativeInfinity)]
    public void NonFinitePointerPositionsSelectNothingWithoutThrowing(double pointerX, double pointerY)
    {
        var chart = Geometry((0, 50), (120, 46), (240, 44));

        Assert.Null(chart.HoveredSample(pointerX, pointerY, Width, Height));
    }

    // MARK: - Composition with the selection model

    /// <summary>
    /// The geometry must agree with the already-tested model: converting a
    /// position and asking the model directly are the same answer.
    /// </summary>
    [Fact]
    public void GeometryAgreesWithTheSelectionModel()
    {
        var chart = Geometry((0, 50), (3540, 40), (3560, 39), (3600, 38));
        var plot = chart.PlotRect(Width, Height);

        for (var step = 0; step <= 40; step++)
        {
            var x = plot.X + (plot.Width * step / 40.0);
            var progress = (x - plot.X) / plot.Width;

            Assert.Equal(
                chart.Model.NearestDisplaySample(progress),
                chart.HoveredSample(x, 17, Width, Height));
        }
    }

    /// <summary>An exact midpoint resolves to the earlier sample, never an average.</summary>
    [Fact]
    public void AnExactMidpointStillSelectsTheEarlierSample()
    {
        var chart = Geometry((0, 48), (300, 46));
        var plot = chart.PlotRect(Width, Height);

        var middle = chart.HoveredSample(plot.X + (plot.Width / 2), 17, Width, Height);

        Assert.Equal(48, middle?.RemainingPercent);
        Assert.Equal(Base, middle?.RecordedAt);
    }

    /// <summary>
    /// Only samples drawn since the most recent reset can be hovered; the
    /// pre-reset history is not on the line.
    /// </summary>
    [Fact]
    public void HoverCannotReachSamplesBeforeTheLatestReset()
    {
        var chart = Geometry((0, 80), (120, 50), (240, 30), (360, 100), (480, 90), (600, 70));
        Assert.Equal(new[] { 100, 90, 70 }, chart.Model.DisplaySamples.Select(s => s.RemainingPercent));

        var plot = chart.PlotRect(Width, Height);
        for (var step = 0; step <= 36; step++)
        {
            var x = plot.X + (plot.Width * step / 36.0);
            var selected = chart.HoveredSample(x, 17, Width, Height);

            Assert.NotNull(selected);
            Assert.Contains(selected!, chart.Model.DisplaySamples);
            Assert.Contains(selected!.RemainingPercent, new[] { 100, 90, 70 });
        }
    }

    /// <summary>
    /// The hovered value matches the drawn line, so an isolated one-point spike
    /// reports its flattened value rather than the raw reading.
    /// </summary>
    [Fact]
    public void HoverReportsTheFlattenedValueThatIsDrawn()
    {
        var chart = Geometry((0, 33), (120, 34), (240, 33));
        Assert.Equal(new[] { 33, 34, 33 }, chart.Model.Samples.Select(s => s.RemainingPercent));

        var plot = chart.PlotRect(Width, Height);
        var middle = chart.HoveredSample(plot.X + (plot.Width / 2), 17, Width, Height);

        Assert.Equal(Base.AddSeconds(120), middle?.RecordedAt);
        Assert.Equal(33, middle?.RemainingPercent);
    }
}
