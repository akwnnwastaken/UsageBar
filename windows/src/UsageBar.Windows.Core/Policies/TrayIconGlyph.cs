namespace UsageBar.Windows.Core.Policies;

/// <summary>
/// The non-colour cue a tray icon state carries, drawn as a rule under the
/// number. Colour alone never conveys the state, but the cue is a thin rule
/// rather than a border: a box around a 16 px glyph steals the space the number
/// needs.
/// </summary>
public enum TrayUnderline
{
    /// <summary>Nothing under the number — the normal state.</summary>
    None,

    /// <summary>A short rule: approaching the warning threshold.</summary>
    Short,

    /// <summary>A full-width rule: critical.</summary>
    Full,

    /// <summary>A dashed rule: the value is the last good one, not a fresh read.</summary>
    Dashed
}

/// <summary>
/// How the tray icon should be drawn for a given state.
///
/// This is the layout decision, kept separate from the drawing so it can be
/// tested without a graphics device. The design is number-first: the percentage
/// is the icon, with no border, plate or chip around it. Physical testing showed
/// the previous boxed treatment made the icon look like a tiny blurry button and
/// left no room for three digits.
/// </summary>
public readonly record struct TrayIconGlyph(
    string Text,
    double FontScale,
    bool Condensed,
    TrayUnderline Underline)
{
    /// <summary>
    /// Smallest share of the icon height the text may use. Anything below this
    /// stops being readable at 16 px, so a long label is condensed horizontally
    /// instead of shrunk further.
    /// </summary>
    public const double MinimumFontScale = 0.50;

    public static TrayIconGlyph For(TrayPresentation presentation)
    {
        ArgumentNullException.ThrowIfNull(presentation);

        var text = presentation.Label;

        return new TrayIconGlyph(
            text,
            FontScaleFor(text),
            // Three characters — in practice only "100" — are drawn at their
            // own size and squeezed horizontally to fit, so the value stays
            // legible as a number instead of being replaced by a symbol.
            Condensed: text.Length >= 3,
            UnderlineFor(presentation.State));
    }

    /// <summary>
    /// Font size as a share of the icon height. Fewer characters get more
    /// height, so a single digit fills the icon and three digits still fit.
    /// </summary>
    internal static double FontScaleFor(string text) => text.Length switch
    {
        <= 1 => 0.80,
        2 => 0.68,
        _ => 0.56
    };

    internal static TrayUnderline UnderlineFor(TrayIconState state) => state switch
    {
        TrayIconState.Warning => TrayUnderline.Short,
        TrayIconState.Critical => TrayUnderline.Full,
        TrayIconState.Stale => TrayUnderline.Dashed,
        _ => TrayUnderline.None
    };
}
