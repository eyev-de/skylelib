import '../base/point2d.dart';
import '../base/size2d.dart';
import '../base/sizeu.dart';

enum CalibrationType {
  one(1),
  two(2),
  five(5),
  nine(9);

  final int value;
  const CalibrationType(this.value);

  static CalibrationType fromInt(int value) {
    switch (value) {
      case 1:
        return CalibrationType.one;
      case 2:
        return CalibrationType.two;
      case 5:
        return CalibrationType.five;
      default:
        return CalibrationType.nine;
    }
  }

  List<int> get array {
    switch (this) {
      case CalibrationType.one:
        return [4];
      case CalibrationType.two:
        return [0, 8];
      case CalibrationType.five:
        return [0, 2, 6, 8, 4];
      case CalibrationType.nine:
        return [0, 2, 7, 1, 8, 3, 5, 6, 4];
    }
  }
}

/// Configuration for calibration
class CalibrationConfig {
  final List<int> points; // 2 bytes length + 1 byte each

  /// Custom coordinates
  final List<Point2d> coordinates; // 2 bytes length + 8 bytes each

  /// Screen resolution in pixels
  final Sizeu resolution; // 4 bytes

  /// Physical screen size in mm
  final Size2d size; // 8 bytes

  /// Improve calibration
  final bool improve;

  const CalibrationConfig({required this.points, required this.coordinates, required this.resolution, required this.size, required this.improve});

  @override
  String toString() => 'CalibrationConfig(points: $points, coordinates: $coordinates, resolution: $resolution, size: $size, improve: $improve)';

  factory CalibrationConfig.fromJson(Map<String, dynamic> json) {
    return CalibrationConfig(
      points: json['points'],
      coordinates: json['coordinates'],
      resolution: json['resolution'],
      size: json['size'],
      improve: json['improve'],
    );
  }

  Map<String, dynamic> toJson() => {'points': points, 'coordinates': coordinates, 'resolution': resolution, 'size': size, 'improve': improve};
}
