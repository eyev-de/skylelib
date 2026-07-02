import '../../ffi/ffi_structs.dart';
import 'point2d.dart';
import 'size2d.dart';

/// Rectangle with double coordinates
class Rect2d {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const Rect2d({required this.left, required this.top, required this.right, required this.bottom});

  static const Rect2d empty = Rect2d(left: 0, top: 0, right: 0, bottom: 0);

  double get width => right - left;
  double get height => bottom - top;
  Point2d get center => Point2d((left + right) / 2, (top + bottom) / 2);
  Point2d get topLeft => Point2d(left, top);
  Point2d get bottomRight => Point2d(right, bottom);
  Size2d get size => Size2d(width, height);

  factory Rect2d.fromEapRectf(EapRectf rect) {
    return Rect2d(left: rect.left.toDouble(), top: rect.top.toDouble(), right: rect.right.toDouble(), bottom: rect.bottom.toDouble());
  }

  factory Rect2d.fromEapRectu(EapRectu rect) {
    return Rect2d(left: rect.left.toDouble(), top: rect.top.toDouble(), right: rect.right.toDouble(), bottom: rect.bottom.toDouble());
  }

  @override
  String toString() => 'Rect2D(l=$left, t=$top, r=$right, b=$bottom)';

  factory Rect2d.fromJson(Map<String, dynamic> json) {
    return Rect2d(left: json['left'], top: json['top'], right: json['right'], bottom: json['bottom']);
  }

  Map<String, dynamic> toJson() => {'left': left, 'top': top, 'right': right, 'bottom': bottom};
}
