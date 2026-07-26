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

namespace UsageBar.Windows.App.Tray;

/// <summary>
/// Draws the remaining percentage inside the tray icon.
///
/// Windows has no persistent text label beside a notification-area icon, so the
/// value is rendered into the icon itself. Colour never carries the meaning
/// alone: the number is always readable, the warning and critical states also
/// get a filled background and a ring, and the tooltip spells the state out.
///
/// Every GDI object is disposed and every native HICON is destroyed. Rendered
/// icons are cached by state so a five-minute refresh does not churn handles.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class TrayIconRenderer : IDisposable
{
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

        var key = string.Create(
            System.Globalization.CultureInfo.InvariantCulture,
            $"{presentation.State}|{presentation.Label}|{size}|{lightForeground}");

        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);

            if (_cache.TryGetValue(key, out var cached))
            {
                return cached.Icon;
            }

            var created = Create(presentation, size, lightForeground);
            _cache[key] = created;
            return created.Icon;
        }
    }

    private static CachedIcon Create(TrayPresentation presentation, int size, bool lightForeground)
    {
        var bitmap = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        try
        {
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.SmoothingMode = SmoothingMode.AntiAlias;
                graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.Clear(Color.Transparent);

                var accent = AccentColor(presentation.State, lightForeground);
                var bounds = new RectangleF(0.5f, 0.5f, size - 1f, size - 1f);

                // Warning and critical additionally get a filled plate, so the
                // state survives a monochrome or high-contrast display.
                if (presentation.State is TrayIconState.Warning or TrayIconState.Critical)
                {
                    using var fill = new SolidBrush(accent);
                    using var path = RoundedRectangle(bounds, size * 0.22f);
                    graphics.FillPath(fill, path);
                }
                else
                {
                    using var outline = new Pen(accent, Math.Max(1f, size / 16f));
                    using var path = RoundedRectangle(bounds, size * 0.22f);
                    graphics.DrawPath(outline, path);
                }

                var foreground = presentation.State is TrayIconState.Warning or TrayIconState.Critical
                    ? ContrastColor(accent)
                    : accent;

                DrawLabel(graphics, presentation, size, foreground);

                // Stale data gets a dotted underline: a second, non-colour cue
                // that the number is not fresh.
                if (presentation.State == TrayIconState.Stale)
                {
                    using var pen = new Pen(foreground, Math.Max(1f, size / 16f))
                    {
                        DashStyle = DashStyle.Dot
                    };
                    var y = size - Math.Max(2f, size / 8f);
                    graphics.DrawLine(pen, size * 0.22f, y, size * 0.78f, y);
                }
            }

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

    private static void DrawLabel(Graphics graphics, TrayPresentation presentation, int size, Color foreground)
    {
        var label = presentation.Label;
        // Three digits would be unreadable at 16px; 100% shows as a full ring.
        if (label.Length > 2 && presentation.RemainingPercent is 100)
        {
            label = "•";
        }

        var fontSize = label.Length switch
        {
            1 => size * 0.72f,
            2 => size * 0.60f,
            _ => size * 0.48f
        };

        using var font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel);
        using var brush = new SolidBrush(foreground);
        using var format = new StringFormat
        {
            Alignment = StringAlignment.Center,
            LineAlignment = StringAlignment.Center,
            FormatFlags = StringFormatFlags.NoWrap
        };

        var box = new RectangleF(0, presentation.State == TrayIconState.Stale ? -size * 0.06f : 0, size, size);
        graphics.DrawString(label, font, brush, box, format);
    }

    private static GraphicsPath RoundedRectangle(RectangleF bounds, float radius)
    {
        var path = new GraphicsPath();
        var diameter = radius * 2;
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    internal static Color AccentColor(TrayIconState state, bool lightForeground) => state switch
    {
        TrayIconState.Critical => Color.FromArgb(232, 17, 35),
        TrayIconState.Warning => Color.FromArgb(202, 111, 0),
        TrayIconState.Stale => lightForeground ? Color.FromArgb(200, 200, 200) : Color.FromArgb(96, 96, 96),
        TrayIconState.NoData or TrayIconState.Refreshing =>
            lightForeground ? Color.FromArgb(180, 180, 180) : Color.FromArgb(120, 120, 120),
        _ => lightForeground ? Color.White : Color.FromArgb(32, 32, 32)
    };

    private static Color ContrastColor(Color background)
    {
        // Perceived luminance, so text stays readable on either plate colour.
        var luminance = ((0.299 * background.R) + (0.587 * background.G) + (0.114 * background.B)) / 255.0;
        return luminance > 0.6 ? Color.FromArgb(16, 16, 16) : Color.White;
    }

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
