import '../../ffi/ffi_structs.dart';

/// Positioning data from eye tracking device
/// Contains face bounding box, pupil positions, and detailed eye features

/// Point with double coordinates
class Point2d {
  double _x;
  double _y;

  double get x => _x;
  double get y => _y;

  Point2d(this._x, this._y);

  factory Point2d.empty() => Point2d(0, 0);

  factory Point2d.fromEapPointf(EapPointf point) {
    return Point2d(point.x.toDouble(), point.y.toDouble());
  }

  void scale(double scale) {
    _x *= scale;
    _y *= scale;
  }

  bool isZero() => x == 0.0 && y == 0.0;

  @override
  String toString() => '($x, $y)';

  factory Point2d.fromJson(Map<String, dynamic> json) {
    return Point2d(json['x'], json['y']);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}
