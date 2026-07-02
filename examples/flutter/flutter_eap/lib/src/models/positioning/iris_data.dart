import '../../ffi/ffi_structs.dart';
import '../base/point2d.dart';

/// Iris landmarks and distance measurement
class IrisData {
  final Point2d center;
  final Point2d top;
  final Point2d left;
  final Point2d right;
  final Point2d bottom;
  final double distance; // Distance from camera in millimeters

  const IrisData({required this.center, required this.top, required this.left, required this.right, required this.bottom, required this.distance});

  static final IrisData empty = IrisData(
    center: Point2d.empty(),
    top: Point2d.empty(),
    left: Point2d.empty(),
    right: Point2d.empty(),
    bottom: Point2d.empty(),
    distance: 0,
  );

  factory IrisData.fromEapIris(EapComplexIris iris) {
    return IrisData(
      center: Point2d.fromEapPointf(iris.center),
      top: Point2d.fromEapPointf(iris.top),
      left: Point2d.fromEapPointf(iris.left),
      right: Point2d.fromEapPointf(iris.right),
      bottom: Point2d.fromEapPointf(iris.bottom),
      distance: iris.distanceMm.toDouble(),
    );
  }

  factory IrisData.fromJson(Map<String, dynamic> json) {
    return IrisData(
      center: Point2d.fromJson(json['center']),
      top: Point2d.fromJson(json['top']),
      left: Point2d.fromJson(json['left']),
      right: Point2d.fromJson(json['right']),
      bottom: Point2d.fromJson(json['bottom']),
      distance: json['distanceMm'],
    );
  }

  Map<String, dynamic> toJson() => {
    'center': center.toJson(),
    'top': top.toJson(),
    'left': left.toJson(),
    'right': right.toJson(),
    'bottom': bottom.toJson(),
    'distanceMm': distance,
  };

  @override
  String toString() => 'IrisData(center=$center, distance=${distance}mm)';
}
