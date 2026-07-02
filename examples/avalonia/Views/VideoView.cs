using System;
using System.Globalization;
using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using SkyleAvaloniaExample.Interop;

namespace SkyleAvaloniaExample.Views;

/// <summary>
/// Renders the device video stream. Converts each frame (1=grayscale, 3=RGB,
/// 4=RGBA) into a reused BGRA <see cref="WriteableBitmap"/> and draws it scaled
/// to the control while preserving aspect ratio.
/// </summary>
public class VideoView : Control
{
    public static readonly StyledProperty<object?> SourceProperty =
        AvaloniaProperty.Register<VideoView, object?>(nameof(Source));

    public object? Source
    {
        get => GetValue(SourceProperty);
        set => SetValue(SourceProperty, value);
    }

    static VideoView()
    {
        AffectsRender<VideoView>(SourceProperty);
    }

    private static readonly IBrush PanelBrush = new SolidColorBrush(Color.FromArgb(0x33, 0, 0, 0));
    private static readonly IBrush HintBrush = new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF));

    private WriteableBitmap? _bitmap;
    private int _bmpWidth;
    private int _bmpHeight;

    public override void Render(DrawingContext context)
    {
        var size = Bounds.Size;
        context.DrawRectangle(PanelBrush, null, new RoundedRect(new Rect(size), 10));

        if (Source is not VideoFrame frame || frame.Width <= 0 || frame.Height <= 0 || frame.Pixels.Length == 0)
        {
            var ft = new FormattedText("No video", CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                Typeface.Default, 16, HintBrush);
            context.DrawText(ft, new Point(size.Width / 2 - ft.Width / 2, size.Height / 2 - ft.Height / 2));
            return;
        }

        UpdateBitmap(frame);
        if (_bitmap == null) return;

        double scale = Math.Min(size.Width / frame.Width, size.Height / frame.Height);
        double dw = frame.Width * scale;
        double dh = frame.Height * scale;
        double ox = (size.Width - dw) / 2.0;
        double oy = (size.Height - dh) / 2.0;

        context.DrawImage(_bitmap,
            new Rect(0, 0, frame.Width, frame.Height),
            new Rect(ox, oy, dw, dh));
    }

    private void UpdateBitmap(VideoFrame frame)
    {
        if (_bitmap == null || _bmpWidth != frame.Width || _bmpHeight != frame.Height)
        {
            _bitmap?.Dispose();
            _bitmap = new WriteableBitmap(
                new PixelSize(frame.Width, frame.Height),
                new Vector(96, 96),
                PixelFormat.Bgra8888,
                AlphaFormat.Opaque);
            _bmpWidth = frame.Width;
            _bmpHeight = frame.Height;
        }

        using var fb = _bitmap.Lock();
        int w = frame.Width;
        int h = frame.Height;
        int ch = frame.Channels;
        var src = frame.Pixels;
        var row = new byte[w * 4];

        for (int y = 0; y < h; y++)
        {
            int srcBase = y * w * ch;
            for (int x = 0; x < w; x++)
            {
                int s = srcBase + x * ch;
                int d = x * 4;
                byte r, g, b;
                if (ch == 1)
                {
                    r = g = b = s < src.Length ? src[s] : (byte)0;
                }
                else
                {
                    r = s < src.Length ? src[s] : (byte)0;
                    g = s + 1 < src.Length ? src[s + 1] : (byte)0;
                    b = s + 2 < src.Length ? src[s + 2] : (byte)0;
                }
                row[d + 0] = b;   // BGRA
                row[d + 1] = g;
                row[d + 2] = r;
                row[d + 3] = 0xFF;
            }
            Marshal.Copy(row, 0, IntPtr.Add(fb.Address, y * fb.RowBytes), row.Length);
        }
    }
}
