using System;
using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using SkyleAvaloniaExample.Interop;

namespace SkyleAvaloniaExample.Views;

/// <summary>
/// Diagnostic positioning view. Draws the per-eye bounding box, pupil (with its
/// fitted ellipse), the two glints and the iris in the camera/sensor coordinate
/// space (2464 x 2064), letterboxed into the control — mirroring the geometry the
/// Flutter app uses in menu_positioning_view.dart.
/// </summary>
public class PositioningView : Control
{
    private const float SensorWidth = 2464f;
    private const float SensorHeight = 2064f;

    public static readonly StyledProperty<object?> SourceProperty =
        AvaloniaProperty.Register<PositioningView, object?>(nameof(Source));

    public object? Source
    {
        get => GetValue(SourceProperty);
        set => SetValue(SourceProperty, value);
    }

    static PositioningView()
    {
        AffectsRender<PositioningView>(SourceProperty);
    }

    private static readonly IBrush PanelBrush = new SolidColorBrush(Color.FromArgb(0x33, 0, 0, 0));
    private static readonly IPen BoxPen = new Pen(new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF)), 1);
    private static readonly IPen IrisPen = new Pen(new SolidColorBrush(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF)), 1.5);
    private static readonly IPen PupilPen = new Pen(new SolidColorBrush(Color.FromRgb(0x5C, 0xD6, 0x5C)), 1.5);
    private static readonly IBrush PupilFill = new SolidColorBrush(Color.FromRgb(0x5C, 0xD6, 0x5C));
    private static readonly IBrush GlintFill = new SolidColorBrush(Color.FromRgb(0x4F, 0xC3, 0xF7));
    private static readonly IBrush TextBrush = Brushes.White;
    private static readonly IBrush HintBrush = new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF));

    public override void Render(DrawingContext context)
    {
        var size = Bounds.Size;
        double scale = Math.Min(size.Width / SensorWidth, size.Height / SensorHeight);
        if (scale <= 0) return;

        double drawW = SensorWidth * scale;
        double drawH = SensorHeight * scale;
        double ox = (size.Width - drawW) / 2.0;
        double oy = (size.Height - drawH) / 2.0;

        context.DrawRectangle(PanelBrush, null, new RoundedRect(new Rect(ox, oy, drawW, drawH), 10));

        if (Source is not PositioningSnapshot snap)
        {
            DrawCentered(context, "Waiting for positioning data…", ox + drawW / 2, oy + drawH / 2, HintBrush, 16);
            return;
        }

        Point Map(float x, float y) => new(ox + x * scale, oy + y * scale);

        DrawEye(context, snap.Face.Eyes.Left, scale, Map);
        DrawEye(context, snap.Face.Eyes.Right, scale, Map);

        float leftMm = snap.Face.Eyes.Left.Iris.DistanceMm;
        float rightMm = snap.Face.Eyes.Right.Iris.DistanceMm;
        string distance = $"Distance   L {Format(leftMm)}   R {Format(rightMm)}";
        DrawText(context, distance, ox + 14, oy + drawH - 26, TextBrush, 14);
    }

    private static void DrawEye(DrawingContext ctx, EapComplexEye eye, double scale, Func<float, float, Point> map)
    {
        // Eye bounding box (image-space uint16). Skip if empty.
        var b = eye.BoundingRect;
        if (b.Right > b.Left && b.Bottom > b.Top)
        {
            var tl = map(b.Left, b.Top);
            var br = map(b.Right, b.Bottom);
            ctx.DrawRectangle(null, BoxPen, new Rect(tl, br));
        }

        // Iris ring from the four extreme points.
        var iris = eye.Iris;
        if (!IsZero(iris.Center))
        {
            var c = map(iris.Center.X, iris.Center.Y);
            double rx = (Math.Abs(iris.Right.X - iris.Center.X) + Math.Abs(iris.Left.X - iris.Center.X)) / 2.0 * scale;
            double ry = (Math.Abs(iris.Bottom.Y - iris.Center.Y) + Math.Abs(iris.Top.Y - iris.Center.Y)) / 2.0 * scale;
            if (rx > 0 && ry > 0)
                ctx.DrawEllipse(null, IrisPen, c, rx, ry);
        }

        // Pupil: fitted ellipse (rotated) + a centre dot.
        var pupil = eye.Pupil;
        if (!IsZero(pupil.Center))
        {
            var c = map(pupil.Ellipse.Center.X, pupil.Ellipse.Center.Y);
            double rx = pupil.Ellipse.Size.Width / 2.0 * scale;
            double ry = pupil.Ellipse.Size.Height / 2.0 * scale;
            if (rx > 0 && ry > 0)
            {
                double angle = pupil.Ellipse.Angle * Math.PI / 180.0;
                var m = Matrix.CreateTranslation(-c.X, -c.Y)
                        * Matrix.CreateRotation(angle)
                        * Matrix.CreateTranslation(c.X, c.Y);
                using (ctx.PushTransform(m))
                    ctx.DrawEllipse(null, PupilPen, c, rx, ry);
            }
            ctx.DrawEllipse(PupilFill, null, map(pupil.Center.X, pupil.Center.Y), 2.5, 2.5);
        }

        // Glints.
        DrawDot(ctx, eye.LeftGlint.Center, map);
        DrawDot(ctx, eye.RightGlint.Center, map);
    }

    private static void DrawDot(DrawingContext ctx, EapPointF p, Func<float, float, Point> map)
    {
        if (IsZero(p)) return;
        ctx.DrawEllipse(GlintFill, null, map(p.X, p.Y), 2.0, 2.0);
    }

    private static bool IsZero(EapPointF p) => p.X == 0f && p.Y == 0f;

    private static string Format(float mm) => mm > 0 ? $"{mm:0} mm" : "—";

    private static void DrawText(DrawingContext ctx, string text, double x, double y, IBrush brush, double size)
    {
        var ft = new FormattedText(text, CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
            Typeface.Default, size, brush);
        ctx.DrawText(ft, new Point(x, y));
    }

    private static void DrawCentered(DrawingContext ctx, string text, double cx, double cy, IBrush brush, double size)
    {
        var ft = new FormattedText(text, CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
            Typeface.Default, size, brush);
        ctx.DrawText(ft, new Point(cx - ft.Width / 2, cy - ft.Height / 2));
    }
}
