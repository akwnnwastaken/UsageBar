using System.Runtime.Versioning;
using System.Windows.Media;
using Microsoft.Win32;
using UsageBar.Windows.Core.Policies;

// Color is ambiguous between System.Drawing and System.Windows.Media; this
// file builds WPF brushes.
using Color = System.Windows.Media.Color;

namespace UsageBar.Windows.App.Views;

/// <summary>
/// Colours for the panel, following the Windows light/dark app setting.
///
/// The palette is opaque on purpose: the panel must stay readable without any
/// transparency effect. Mica or Acrylic could be layered on later without
/// changing these values.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class AppTheme
{
    private AppTheme(bool isDark)
    {
        IsDark = isDark;

        Background = isDark ? Frozen(0x20, 0x20, 0x20) : Frozen(0xF9, 0xF9, 0xF9);
        Surface = isDark ? Frozen(0x2B, 0x2B, 0x2B) : Frozen(0xFF, 0xFF, 0xFF);
        Border = isDark ? Frozen(0x3A, 0x3A, 0x3A) : Frozen(0xE0, 0xE0, 0xE0);
        Foreground = isDark ? Frozen(0xF2, 0xF2, 0xF2) : Frozen(0x1A, 0x1A, 0x1A);
        SecondaryForeground = isDark ? Frozen(0xA0, 0xA0, 0xA0) : Frozen(0x60, 0x60, 0x60);
        PlotBackground = isDark ? Frozen(0x33, 0x33, 0x33) : Frozen(0xEE, 0xEE, 0xEE);

        // Accents are lightened for dark mode so they keep enough contrast
        // against the dark surface.
        Normal = isDark ? Frozen(0x6C, 0xCB, 0x5E) : Frozen(0x0F, 0x7B, 0x38);
        Warning = isDark ? Frozen(0xFF, 0xB9, 0x00) : Frozen(0xB7, 0x6E, 0x00);
        Critical = isDark ? Frozen(0xFF, 0x6B, 0x63) : Frozen(0xC4, 0x2B, 0x1B);
        Stale = Warning;
    }

    public bool IsDark { get; }

    public SolidColorBrush Background { get; }

    public SolidColorBrush Surface { get; }

    public SolidColorBrush Border { get; }

    public SolidColorBrush Foreground { get; }

    public SolidColorBrush SecondaryForeground { get; }

    public SolidColorBrush PlotBackground { get; }

    public SolidColorBrush Normal { get; }

    public SolidColorBrush Warning { get; }

    public SolidColorBrush Critical { get; }

    public SolidColorBrush Stale { get; }

    /// <summary>Reads the current Windows app theme.</summary>
    public static AppTheme Current()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return new AppTheme(key?.GetValue("AppsUseLightTheme") is not int light || light == 0);
        }
        catch (Exception exception) when (
            exception is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            return new AppTheme(isDark: false);
        }
    }

    /// <summary>
    /// The colour for a remaining percentage. With colours turned off every
    /// value uses the normal foreground, exactly as on macOS.
    /// </summary>
    public SolidColorBrush ForLevel(UsageAlertLevel level, bool colorsEnabled) =>
        !colorsEnabled
            ? Foreground
            : level switch
            {
                UsageAlertLevel.Critical => Critical,
                UsageAlertLevel.Warning => Warning,
                _ => Normal
            };

    private static SolidColorBrush Frozen(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }
}
