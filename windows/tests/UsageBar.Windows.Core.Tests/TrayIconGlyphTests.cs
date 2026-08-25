using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// The tray icon layout decision, which physical testing showed to be wrong:
/// the icon drew a square chip around the number and replaced 100 with a dot.
/// The rules below pin the corrected behavior — the number is the icon, and no
/// value is ever swapped for a symbol.
/// </summary>
public sealed class TrayIconGlyphTests
{
    private static readonly Localizer English = new(AppLanguage.English);
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static TrayPresentation Presentation(int remaining, bool stale = false)
    {
        var windows = new[] { new UsageWindow(UsageWindowKind.FiveHour, 100 - remaining, null, 300) };
        var usage = stale
            ? new ProviderUsage(ProviderNames.Codex, windows, ProviderIssue.CodexTimedOut, Now.AddMinutes(-5))
            : new ProviderUsage(ProviderNames.Codex, windows, error: null, lastSuccessfulAt: Now);

        return TrayPresentationCalculator.Calculate(
            ProviderNames.Codex,
            hasConnectedProviders: true,
            new Dictionary<string, ProviderUsage>(StringComparer.Ordinal) { [ProviderNames.Codex] = usage },
            new UsageAlertPolicy(true, UsageAlertPreset.Balanced),
            English,
            isRefreshing: false,
            showResetCountdown: false,
            Now);
    }

    /// <summary>
    /// The regression this fix exists for. 100 must render as the number, at a
    /// size of its own, never as a dot or any other stand-in.
    /// </summary>
    [Fact]
    public void OneHundredRendersAsTheNumberNotASymbol()
    {
        var glyph = TrayIconGlyph.For(Presentation(100));

        Assert.Equal("100", glyph.Text);
        Assert.True(glyph.Condensed, "100 must be condensed to fit rather than shrunk or replaced.");

        // Explicitly not any of the stand-ins that were used before.
        foreach (var placeholder in new[] { "•", "·", "*", "—", "…", "↻" })
        {
            Assert.NotEqual(placeholder, glyph.Text);
        }
    }

    [Theory]
    [InlineData(99)]
    [InlineData(98)]
    [InlineData(75)]
    [InlineData(42)]
    [InlineData(18)]
    [InlineData(7)]
    public void EveryOtherPercentageRendersAsItsOwnNumber(int remaining)
    {
        var glyph = TrayIconGlyph.For(Presentation(remaining));

        Assert.Equal(remaining.ToString(System.Globalization.CultureInfo.InvariantCulture), glyph.Text);
        // Only three digits need compressing; one and two digits get their full
        // size so they stay crisp.
        Assert.False(glyph.Condensed);
        Assert.True(glyph.FontScale >= TrayIconGlyph.MinimumFontScale);
    }

    /// <summary>Fewer characters get more height, so a single digit fills the icon.</summary>
    [Fact]
    public void FontScaleShrinksOnlyAsCharactersAreAdded()
    {
        var single = TrayIconGlyph.For(Presentation(7)).FontScale;
        var pair = TrayIconGlyph.For(Presentation(42)).FontScale;
        var triple = TrayIconGlyph.For(Presentation(100)).FontScale;

        Assert.True(single > pair);
        Assert.True(pair > triple);
        Assert.True(triple >= TrayIconGlyph.MinimumFontScale);
    }

    [Fact]
    public void NoDataAndRefreshingKeepTheirOwnGlyphs()
    {
        var empty = new Dictionary<string, ProviderUsage>(StringComparer.Ordinal);
        var policy = new UsageAlertPolicy(true, UsageAlertPreset.Balanced);

        var noData = TrayIconGlyph.For(TrayPresentationCalculator.Calculate(
            null, hasConnectedProviders: false, empty, policy, English, isRefreshing: false, showResetCountdown: false, Now));
        Assert.Equal("—", noData.Text);
        Assert.Equal(TrayUnderline.None, noData.Underline);

        var refreshing = TrayIconGlyph.For(TrayPresentationCalculator.Calculate(
            ProviderNames.Codex,
            hasConnectedProviders: true, empty, policy, English, isRefreshing: true, showResetCountdown: false, Now));
        Assert.Equal("↻", refreshing.Text);
        Assert.Equal(TrayUnderline.None, refreshing.Underline);
    }

    /// <summary>
    /// The state must be readable without seeing the colour. With the box gone
    /// that cue is the rule under the number, and each state's rule differs.
    /// </summary>
    [Fact]
    public void EachStateHasADistinctNonColourCue()
    {
        Assert.Equal(TrayUnderline.None, TrayIconGlyph.For(Presentation(42)).Underline);
        Assert.Equal(TrayUnderline.Short, TrayIconGlyph.For(Presentation(18)).Underline);
        Assert.Equal(TrayUnderline.Full, TrayIconGlyph.For(Presentation(7)).Underline);
        Assert.Equal(TrayUnderline.Dashed, TrayIconGlyph.For(Presentation(42, stale: true)).Underline);

        // All four are different, so the cue actually distinguishes them.
        var cues = new[]
        {
            TrayIconGlyph.For(Presentation(42)).Underline,
            TrayIconGlyph.For(Presentation(18)).Underline,
            TrayIconGlyph.For(Presentation(7)).Underline,
            TrayIconGlyph.For(Presentation(42, stale: true)).Underline
        };
        Assert.Equal(cues.Length, cues.Distinct().Count());
    }

    [Theory]
    [InlineData(TrayIconState.Normal, TrayUnderline.None)]
    [InlineData(TrayIconState.Warning, TrayUnderline.Short)]
    [InlineData(TrayIconState.Critical, TrayUnderline.Full)]
    [InlineData(TrayIconState.Stale, TrayUnderline.Dashed)]
    [InlineData(TrayIconState.NoData, TrayUnderline.None)]
    [InlineData(TrayIconState.Refreshing, TrayUnderline.None)]
    public void EveryStateMapsToACue(TrayIconState state, TrayUnderline expected)
    {
        Assert.Equal(expected, TrayIconGlyph.UnderlineFor(state));
    }

    /// <summary>
    /// A stale value still shows the number it is stale about — the cue and the
    /// tooltip say it is not fresh, the icon does not go blank.
    /// </summary>
    [Fact]
    public void StaleStillShowsTheValue()
    {
        var glyph = TrayIconGlyph.For(Presentation(42, stale: true));

        Assert.Equal("42", glyph.Text);
        Assert.Equal(TrayUnderline.Dashed, glyph.Underline);
    }

    /// <summary>
    /// Nothing in the layout describes a border, plate or chip any more: the
    /// glyph is text, a size, and a rule. This is what keeps the icon from
    /// regressing into a tiny boxed button.
    /// </summary>
    [Fact]
    public void TheLayoutHasNoBoxToDraw()
    {
        var names = typeof(TrayIconGlyph)
            .GetProperties()
            .Select(property => property.Name)
            .ToList();

        Assert.Equal(new[] { "Text", "FontScale", "Condensed", "Underline" }.OrderBy(name => name),
            names.OrderBy(name => name));

        foreach (var forbidden in new[] { "Border", "Background", "Plate", "Chip", "Corner", "Fill" })
        {
            Assert.DoesNotContain(forbidden, names, StringComparer.OrdinalIgnoreCase);
        }
    }

    /// <summary>
    /// The presentation layer never substitutes a placeholder for a real
    /// reading — the substitution that broke 100 lived in the renderer, and
    /// must not come back anywhere.
    /// </summary>
    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(9)]
    [InlineData(10)]
    [InlineData(99)]
    [InlineData(100)]
    public void APercentageIsAlwaysItsOwnDigits(int remaining)
    {
        var presentation = Presentation(remaining);

        Assert.Equal(remaining, presentation.RemainingPercent);
        Assert.Equal(
            remaining.ToString(System.Globalization.CultureInfo.InvariantCulture),
            presentation.Label);
        Assert.Equal(presentation.Label, TrayIconGlyph.For(presentation).Text);
    }
}
