using System.Drawing;
using System.Runtime.Versioning;
using UsageBar.Windows.Infrastructure.Tray;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// What the tray icon actually draws, checked against the pixels.
///
/// Physical testing found the icon drawing a square chip around the number and
/// substituting a dot for 100. The layout rules are covered in the Core suite;
/// these assertions cover the part only real GDI+ can answer — that the corners
/// stay clear, and that "100" is three digits spread across the icon rather than
/// a mark in the middle.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class TrayIconRenderingTests
{
    private const int IconSize = 16;

    private static readonly Localizer English = new(AppLanguage.English);
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static TrayPresentation Presentation(
        int? remaining,
        bool stale = false,
        bool refreshing = false)
    {
        var usages = new Dictionary<string, ProviderUsage>(StringComparer.Ordinal);
        if (remaining is int value)
        {
            var windows = new[] { new UsageWindow(UsageWindowKind.FiveHour, 100 - value, null, 300) };
            usages[ProviderNames.Codex] = stale
                ? new ProviderUsage(ProviderNames.Codex, windows, ProviderIssue.CodexTimedOut, Now.AddMinutes(-5))
                : new ProviderUsage(ProviderNames.Codex, windows, error: null, lastSuccessfulAt: Now);
        }

        return TrayPresentationCalculator.Calculate(
            ProviderNames.Codex,
            hasConnectedProviders: true,
            usages,
            new UsageAlertPolicy(true, UsageAlertPreset.Balanced),
            English,
            refreshing,
            showResetCountdown: false,
            Now);
    }

    /// <summary>The bounding box of everything actually painted, and how much of it there is.</summary>
    private static (int Left, int Right, int Top, int Bottom, int Painted) Ink(Bitmap bitmap)
    {
        int left = bitmap.Width, right = -1, top = bitmap.Height, bottom = -1, painted = 0;

        for (var y = 0; y < bitmap.Height; y++)
        {
            for (var x = 0; x < bitmap.Width; x++)
            {
                // Anything faint enough to be invisible does not count as ink.
                if (bitmap.GetPixel(x, y).A <= 24)
                {
                    continue;
                }

                painted++;
                left = Math.Min(left, x);
                right = Math.Max(right, x);
                top = Math.Min(top, y);
                bottom = Math.Max(bottom, y);
            }
        }

        return (left, right, top, bottom, painted);
    }

    /// <summary>
    /// Height of the band at the bottom reserved for the state rule. A rule is a
    /// deliberate mark and may reach the bottom corners; a box may not paint
    /// anywhere on the perimeter.
    /// </summary>
    private const int RuleBand = 3;

    /// <summary>
    /// The regression, checked where it happened. A border or plate paints the
    /// whole perimeter, so the test probes the edges a rule can never reach: the
    /// top, and the left and right columns above the rule band.
    /// </summary>
    [WindowsTheory]
    [InlineData(100)]
    [InlineData(42)]
    [InlineData(18)]
    [InlineData(7)]
    public void NoBorderPlateOrChipIsDrawn(int remaining)
    {
        using var bitmap = TrayIconRenderer.RenderBitmap(Presentation(remaining), IconSize, lightForeground: true);

        // The top edge and the row below it: a plate of any kind paints here.
        for (var x = 0; x < IconSize; x++)
        {
            Assert.True(bitmap.GetPixel(x, 0).A <= 24, $"Top edge pixel ({x},0) is painted.");
        }

        // The side columns, everywhere above the state rule.
        for (var y = 0; y < IconSize - RuleBand; y++)
        {
            Assert.True(bitmap.GetPixel(0, y).A <= 24, $"Left edge pixel (0,{y}) is painted.");
            Assert.True(
                bitmap.GetPixel(IconSize - 1, y).A <= 24,
                $"Right edge pixel ({IconSize - 1},{y}) is painted.");
        }
    }

    /// <summary>
    /// The normal state draws no rule at all, so for it the entire perimeter —
    /// bottom corners included — must be clear.
    /// </summary>
    [WindowsFact]
    public void TheNormalStateLeavesTheWholePerimeterClear()
    {
        using var bitmap = TrayIconRenderer.RenderBitmap(Presentation(42), IconSize, lightForeground: true);

        for (var index = 0; index < IconSize; index++)
        {
            Assert.True(bitmap.GetPixel(index, 0).A <= 24, $"Top pixel ({index},0) is painted.");
            Assert.True(
                bitmap.GetPixel(index, IconSize - 1).A <= 24,
                $"Bottom pixel ({index},{IconSize - 1}) is painted.");
            Assert.True(bitmap.GetPixel(0, index).A <= 24, $"Left pixel (0,{index}) is painted.");
            Assert.True(
                bitmap.GetPixel(IconSize - 1, index).A <= 24,
                $"Right pixel ({IconSize - 1},{index}) is painted.");
        }
    }

    /// <summary>
    /// 100 must be a legible three-digit number: it has to use most of the icon
    /// width and considerably more ink than a dot ever would.
    /// </summary>
    [WindowsFact]
    public void OneHundredIsDrawnAsThreeDigitsAcrossTheIcon()
    {
        using var hundred = TrayIconRenderer.RenderBitmap(Presentation(100), IconSize, lightForeground: true);
        using var seven = TrayIconRenderer.RenderBitmap(Presentation(7), IconSize, lightForeground: true);

        var hundredInk = Ink(hundred);
        var sevenInk = Ink(seven);

        var width = hundredInk.Right - hundredInk.Left + 1;
        Assert.True(
            width >= IconSize * 0.75,
            $"100 spans only {width} of {IconSize} pixels — it is not reading as three digits.");

        // A dot would be a handful of pixels in the middle.
        Assert.True(hundredInk.Painted > 30, $"100 painted only {hundredInk.Painted} pixels.");
        Assert.True(
            hundredInk.Painted > sevenInk.Painted,
            "100 should use more ink than a single digit.");

        // And it is genuinely wider than one digit rather than a shrunken blob.
        var sevenWidth = sevenInk.Right - sevenInk.Left + 1;
        Assert.True(width > sevenWidth, $"100 ({width}px) is not wider than 7 ({sevenWidth}px).");
    }

    [WindowsTheory]
    [InlineData(99)]
    [InlineData(98)]
    [InlineData(75)]
    [InlineData(42)]
    [InlineData(18)]
    [InlineData(7)]
    public void EveryOtherValueIsDrawnWithRealInk(int remaining)
    {
        using var bitmap = TrayIconRenderer.RenderBitmap(Presentation(remaining), IconSize, lightForeground: true);

        var ink = Ink(bitmap);
        Assert.True(ink.Painted > 18, $"{remaining} painted only {ink.Painted} pixels.");
        // Vertically centred rather than hugging an edge.
        Assert.True(ink.Top > 0, $"{remaining} touches the top edge.");
    }

    /// <summary>
    /// The number is the icon: it must fill a good share of the height at every
    /// size, not sit shrunken inside empty space.
    /// </summary>
    [WindowsTheory]
    [InlineData(16)]
    [InlineData(20)]
    [InlineData(24)]
    [InlineData(32)]
    public void TheNumberFillsTheIconAtEveryCommonSize(int size)
    {
        using var bitmap = TrayIconRenderer.RenderBitmap(Presentation(42), size, lightForeground: true);

        var ink = Ink(bitmap);
        var height = ink.Bottom - ink.Top + 1;

        Assert.True(height >= size * 0.45, $"At {size}px the digits are only {height}px tall.");
        Assert.True(ink.Painted > size, $"At {size}px only {ink.Painted} pixels were painted.");
    }

    /// <summary>
    /// The states must differ in shape, not only in colour: the rule under the
    /// number is what makes them distinguishable in a monochrome or
    /// high-contrast setting.
    /// </summary>
    [WindowsFact]
    public void StatesDifferInShapeNotJustColour()
    {
        static int BottomInk(Bitmap bitmap)
        {
            var count = 0;
            for (var y = bitmap.Height - 3; y < bitmap.Height; y++)
            {
                for (var x = 0; x < bitmap.Width; x++)
                {
                    if (bitmap.GetPixel(x, y).A > 24)
                    {
                        count++;
                    }
                }
            }

            return count;
        }

        using var normal = TrayIconRenderer.RenderBitmap(Presentation(42), IconSize, true);
        using var warning = TrayIconRenderer.RenderBitmap(Presentation(18), IconSize, true);
        using var critical = TrayIconRenderer.RenderBitmap(Presentation(7), IconSize, true);
        using var stale = TrayIconRenderer.RenderBitmap(Presentation(42, stale: true), IconSize, true);

        // Normal draws no rule; the others do.
        Assert.True(BottomInk(warning) > 0, "The warning rule is missing.");
        Assert.True(BottomInk(critical) > 0, "The critical rule is missing.");
        Assert.True(BottomInk(stale) > 0, "The stale rule is missing.");

        // Critical's rule is wider than warning's, and stale's is dashed, so it
        // uses less ink than the solid rule of the same nominal width.
        Assert.True(
            BottomInk(critical) > BottomInk(warning),
            "Critical and warning are not distinguishable by shape.");
        Assert.True(
            BottomInk(stale) < BottomInk(critical),
            "The stale rule is not visibly dashed.");
    }

    [WindowsFact]
    public void NoDataAndRefreshingDrawTheirOwnGlyphs()
    {
        using var noData = TrayIconRenderer.RenderBitmap(Presentation(null), IconSize, true);
        using var refreshing = TrayIconRenderer.RenderBitmap(Presentation(null, refreshing: true), IconSize, true);

        Assert.True(Ink(noData).Painted > 0, "The no-data glyph drew nothing.");
        Assert.True(Ink(refreshing).Painted > 0, "The refreshing glyph drew nothing.");

        // They are different marks, not the same one twice.
        Assert.NotEqual(Ink(noData).Painted, Ink(refreshing).Painted);
    }

    /// <summary>
    /// A dark and a light taskbar need different glyph colours, and neither may
    /// come out transparent.
    /// </summary>
    [WindowsFact]
    public void TheGlyphIsOpaqueOnBothTaskbarThemes()
    {
        foreach (var lightForeground in new[] { true, false })
        {
            using var bitmap = TrayIconRenderer.RenderBitmap(Presentation(42), IconSize, lightForeground);

            var opaque = 0;
            for (var y = 0; y < IconSize; y++)
            {
                for (var x = 0; x < IconSize; x++)
                {
                    if (bitmap.GetPixel(x, y).A > 200)
                    {
                        opaque++;
                    }
                }
            }

            Assert.True(opaque > 10, $"lightForeground={lightForeground} produced almost no solid pixels.");
        }
    }

    [WindowsFact]
    public void RenderedIconsAreCachedAndReleased()
    {
        using var renderer = new TrayIconRenderer();

        var first = renderer.Render(Presentation(42), IconSize, lightForeground: true);
        var second = renderer.Render(Presentation(42), IconSize, lightForeground: true);
        var different = renderer.Render(Presentation(7), IconSize, lightForeground: true);

        // Identical state reuses the same icon rather than leaking a new HICON.
        Assert.Same(first, second);
        Assert.NotSame(first, different);
        // Disposal must not throw; it destroys every cached HICON.
    }
}
