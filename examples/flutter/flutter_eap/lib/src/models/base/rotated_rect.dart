import '../../ffi/ffi_structs.dart';
import 'point2d.dart';
import 'size2d.dart';

/// Rotated rectangle (ellipse representation)
class RotatedRect {
  final Point2d center;
  final Size2d size;
  final double angle; // Rotation angle in degrees

  const RotatedRect({required this.center, required this.size, required this.angle});

  static final RotatedRect empty = RotatedRect(center: Point2d.empty(), size: Size2d.empty, angle: 0);

  factory RotatedRect.fromEapRotatedRect(EapRotatedRect rect) {
    return RotatedRect(center: Point2d.fromEapPointf(rect.center), size: Size2d.fromEapSizef(rect.size), angle: rect.angle.toDouble());
  }

  @override
  String toString() => 'RotatedRect(center=$center, size=$size, angle=$angle°)';

  factory RotatedRect.fromJson(Map<String, dynamic> json) {
    return RotatedRect(center: Point2d.fromJson(json['center']), size: Size2d.fromJson(json['size']), angle: json['angle']);
  }

  Map<String, dynamic> toJson() => {'center': center.toJson(), 'size': size.toJson(), 'angle': angle};
}
