using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using UsageBar.Windows.Core.Policies;

// This file draws with GDI+. Color, Pen and FontStyle exist in both
// System.Drawing and System.Windows.Media, so they are pinned to the GDI+
// meaning for this file.
using Color = System.Drawing.Color;
using FontStyle = System.Drawing.FontStyle;
using Pen = System.Drawing.Pen;

namespace UsageBar.Windows.Infrastructure.Tray;

/// <summary>
/// Draws the remaining percentage as the tray icon.
///
/// Windows has no persistent text label beside a notification-area icon, so the
/// number is the icon. The composition is deliberately bare: no border, no
/// plate, no chip. Physical testing showed the earlier boxed treatment looked
/// like a tiny blurry button and left so little room that "100" had to be
/// replaced by a dot — the value the user most wants to see.
///
/// The state still reads without colour: a thin rule under the number says
/// warning, critical or stale, and no-data and refreshing have their own
/// glyphs. Colour reinforces those, it does not carry them alone.
///
/// Every GDI object is disposed and every native HICON is destroyed. Rendered
/// icons are cached per state so a five-minute refresh does not churn handles.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class TrayIconRenderer : IDisposable
{
    /// <summary>
    /// Fraction of the icon left clear on each side. Small, because with no
    /// border the number can use nearly the whole square.
    /// </summary>
    private const float HorizontalPadding = 0.04f;

    private readonly Dictionary<string, CachedIcon> _cache = new(StringComparer.Ordinal);
    private readonly object _gate = new();
    private bool _disposed;

    /// <summary>
    /// Returns a cached icon for the given state. The renderer owns it — callers
    /// must not dispose the returned icon.
    /// </summary>
    public Icon Render(TrayPresentation presentation, int size, bool lightForeground)
    {
        ArgumentNullException.ThrowIfNull(presentation);

        var glyph = TrayIconGlyph.For(presentation);
        var key = string.Create(
            System.Globalization.CultureInfo.InvariantCulture,
            $"{presentation.State}|{glyph.Text}|{size}|{lightForeground}");

        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);

            if (_cache.TryGetValue(key, out var cached))
            {
                return cached.Icon;
            }

            var created = Create(presentation, glyph, size, lightForeground);
            _cache[key] = created;
            return created.Icon;
        }
    }

    /// <summary>
    /// Draws the icon into a bitmap. Separate from icon creation so tests can
    /// inspect the actual pixels — that the corners stay clear, and that "100"
    /// really is three digits across the icon rather than a mark in the middle.
    /// The caller owns the returned bitmap.
    /// </summary>
    public static Bitmap RenderBitmap(TrayPresentation presentation, int size, bool lightForeground)
    {
        ArgumentNullException.ThrowIfNull(presentation);

        var glyph = TrayIconGlyph.For(presentation);
        var bitmap = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        try
        {
            using var graphics = Graphics.FromImage(bitmap);
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            // Grayscale anti-aliasing, not ClearType. Subpixel rendering on a
            // transparent bitmap produces coloured fringes that read as a blurry,
            // low-quality glyph once the icon is composited onto the taskbar.
            graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.Clear(Color.Transparent);

            var foreground = ForegroundColor(presentation.State, lightForeground);
            var underlineHeight = glyph.Underline == TrayUnderline.None ? 0f : Math.Max(1.5f, size / 8f);

            DrawGlyph(graphics, glyph, size, underlineHeight, foreground);
            DrawUnderline(graphics, glyph.Underline, size, foreground);

            return bitmap;
        }
        catch
        {
            bitmap.Dispose();
            throw;
        }
    }

    private static CachedIcon Create(
        TrayPresentation presentation,
        TrayIconGlyph glyph,
        int size,
        bool lightForeground)
    {
        var bitmap = RenderBitmap(presentation, size, lightForeground);
        try
        {
            var handle = bitmap.GetHicon();
            try
            {
                // Icon.FromHandle does not take ownership, so the handle is kept
                // and destroyed explicitly on disposal.
                return new CachedIcon(Icon.FromHandle(handle), handle);
            }
            catch
            {
                DestroyIcon(handle);
                throw;
            }
        }
        finally
        {
            bitmap.Dispose();
        }
    }

    /// <summary>
    /// Draws the number centred on its measured ink, not on the font's line box.
    /// Centring on the line box leaves digits sitting visibly high, which is
    /// what made the old icon look cramped.
    ///
    /// A label that is still too wide at its own size — "100" at 16 px — is
    /// compressed horizontally rather than shrunk further, so it stays a
    /// readable three-digit number instead of becoming a smudge.
    /// </summary>
    private static void DrawGlyph(
        Graphics graphics,
        TrayIconGlyph glyph,
        int size,
        float underlineHeight,
        Color foreground)
    {
        var fontSize = Math.Max((float)(size * TrayIconGlyph.MinimumFontScale), (float)(size * glyph.FontScale));

        using var font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel);
        using var brush = new SolidBrush(foreground);
        using var format = (StringFormat)StringFormat.GenericTypographic.Clone();
        format.FormatFlags |= StringFormatFlags.NoWrap | StringFormatFlags.NoClip;
        format.Alignment = StringAlignment.Near;
        format.LineAlignment = StringAlignment.Near;

        var measured = graphics.MeasureString(glyph.Text, font, PointF.Empty, format);
        var available = size * (1f - (HorizontalPadding * 2f));

        // Horizontal compression only: the height stays as chosen, so the digits
        // keep their weight instead of turning spindly.
        var scaleX = glyph.Condensed && measured.Width > available && measured.Width > 0
            ? available / measured.Width
            : 1f;

        var drawnWidth = measured.Width * scaleX;
        var contentHeight = size - underlineHeight;
        var x = (size - drawnWidth) / 2f;
        var y = (contentHeight - measured.Height) / 2f;

        var state = graphics.Save();
        try
        {
            graphics.TranslateTransform(x, y);
            if (scaleX < 1f)
            {
                graphics.ScaleTransform(scaleX, 1f);
            }

            graphics.DrawString(glyph.Text, font, brush, PointF.Empty, format);
        }
        finally
        {
            graphics.Restore(state);
        }
    }

    /// <summary>
    /// The non-colour state cue: a thin rule under the number. Its width and
    /// dash pattern differ per state, so warning, critical and stale are
    /// distinguishable without seeing the colour.
    /// </summary>
    private static void DrawUnderline(Graphics graphics, TrayUnderline underline, int size, Color foreground)
    {
        if (underline == TrayUnderline.None)
        {
            return;
        }

        var width = underline switch
        {
            TrayUnderline.Short => size * 0.40f,
            TrayUnderline.Dashed => size * 0.56f,
            _ => size * 0.68f
        };

        var thickness = Math.Max(1.5f, size / 10f);
        var y = size - (thickness / 2f) - Math.Max(0.5f, size * 0.02f);
        var left = (size - width) / 2f;

        using var pen = new Pen(foreground, thickness)
        {
            StartCap = LineCap.Round,
            EndCap = LineCap.Round
        };

        if (underline == TrayUnderline.Dashed)
        {
            pen.DashStyle = DashStyle.Custom;
            pen.DashPattern = new[] { 1.6f, 1.2f };
        }

        graphics.DrawLine(pen, left, y, left + width, y);
    }

    /// <summary>
    /// Colour for the number itself. With the plate gone there is no background
    /// to contrast against, so the glyph carries the colour directly and the
    /// neutral states follow the taskbar's own foreground.
    /// </summary>
    public static Color ForegroundColor(TrayIconState state, bool lightForeground) => state switch
    {
        // Lightened for a dark taskbar so the accents keep their contrast.
        TrayIconState.Critical => lightForeground ? Color.FromArgb(255, 107, 99) : Color.FromArgb(196, 43, 27),
        TrayIconState.Warning => lightForeground ? Color.FromArgb(255, 185, 0) : Color.FromArgb(160, 98, 0),
        TrayIconState.Stale => lightForeground ? Color.FromArgb(200, 200, 200) : Color.FromArgb(90, 90, 90),
        // Paused joins the existing neutral group: it is a deliberate stop, not
        // a failure, and it introduces no colour of its own.
        TrayIconState.NoData or TrayIconState.Refreshing or TrayIconState.Paused =>
            lightForeground ? Color.FromArgb(190, 190, 190) : Color.FromArgb(110, 110, 110),
        _ => lightForeground ? Color.FromArgb(245, 245, 245) : Color.FromArgb(26, 26, 26)
    };

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            foreach (var cached in _cache.Values)
            {
                cached.Icon.Dispose();
                DestroyIcon(cached.Handle);
            }

            _cache.Clear();
        }
    }

    private readonly record struct CachedIcon(Icon Icon, IntPtr Handle);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);
}
