import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_eap_riverpod/flutter_eap_riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Diagnostic positioning view: draws per-eye box, pupil (with fitted ellipse),
/// glints, iris ring and per-eye distance in camera/sensor space (2464 × 2064) —
/// matching the Avalonia/SwiftUI examples.
///
/// The dark panel is constrained to the sensor aspect ratio, so its edge is the
/// real sensor edge: a feature near the panel border really is near the sensor
/// border.
class PositioningView extends ConsumerWidget {
  const PositioningView({super.key});

  static const double sensorW = 2464;
  static const double sensorH = 2064;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final face = ref.watch(eapPositioningDataStreamProvider).value;
    return Center(
      child: AspectRatio(
        aspectRatio: sensorW / sensorH,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: face == null
              ? Center(
                  child: Text('Waiting for positioning data…',
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                )
              : CustomPaint(
                  painter: _PositioningPainter(face),
                  child: const SizedBox.expand(),
                ),
        ),
      ),
    );
  }
}

class _PositioningPainter extends CustomPainter {
  _PositioningPainter(this.face);

  final FaceData face;

  @override
  void paint(Canvas canvas, Size size) {
    // The canvas already has the sensor aspect ratio, so map directly with no
    // letterbox offset — (0,0) is the sensor's top-left corner.
    final scale = size.width / PositioningView.sensorW;
    if (scale <= 0) return;

    Offset map(double x, double y) => Offset(x * scale, y * scale);

    _drawEye(canvas, face.leftEye, scale, map);
    _drawEye(canvas, face.rightEye, scale, map);

    final tp = TextPainter(
      text: TextSpan(
        text: 'Distance   L ${_mm(face.leftEye.iris.distance)}   '
            'R ${_mm(face.rightEye.iris.distance)}',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(10, size.height - tp.height - 8));
  }

  void _drawEye(Canvas canvas, EyeData eye, double scale,
      Offset Function(double, double) map) {
    final boxPen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.4);
    final irisPen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.8);
    final pupilPen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF5CD65C);
    final pupilFill = Paint()..color = const Color(0xFF5CD65C);
    final glintFill = Paint()..color = const Color(0xFF4FC3F7);

    // Eye bounding box (image space)
    final b = eye.boundingRect;
    if (b.right > b.left && b.bottom > b.top) {
      canvas.drawRect(
          Rect.fromPoints(map(b.left, b.top), map(b.right, b.bottom)), boxPen);
    }

    // Iris ring from the four extreme points
    final iris = eye.iris;
    if (!_isZero(iris.center)) {
      final c = map(iris.center.x, iris.center.y);
      final rx = (((iris.right.x - iris.center.x).abs() +
                  (iris.left.x - iris.center.x).abs()) /
              2) *
          scale;
      final ry = (((iris.bottom.y - iris.center.y).abs() +
                  (iris.top.y - iris.center.y).abs()) /
              2) *
          scale;
      if (rx > 0 && ry > 0) {
        canvas.drawOval(
            Rect.fromCenter(center: c, width: 2 * rx, height: 2 * ry), irisPen);
      }
    }

    // Pupil: fitted (rotated) ellipse + centre dot
    final pupil = eye.pupil;
    if (!_isZero(pupil.center)) {
      final c = map(pupil.ellipse.center.x, pupil.ellipse.center.y);
      final rx = pupil.ellipse.size.width / 2 * scale;
      final ry = pupil.ellipse.size.height / 2 * scale;
      if (rx > 0 && ry > 0) {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(pupil.ellipse.angle * math.pi / 180.0);
        canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: 2 * rx, height: 2 * ry),
            pupilPen);
        canvas.restore();
      }
      canvas.drawCircle(map(pupil.center.x, pupil.center.y), 2.5, pupilFill);
    }

    // Glints
    for (final g in [eye.glints.left.center, eye.glints.right.center]) {
      if (!_isZero(g)) canvas.drawCircle(map(g.x, g.y), 2, glintFill);
    }
  }

  bool _isZero(Point2d p) => p.x == 0 && p.y == 0;
  String _mm(double v) => v > 0 ? '${v.toStringAsFixed(0)} mm' : '—';

  @override
  bool shouldRepaint(covariant _PositioningPainter old) =>
      !identical(old.face, face);
}
