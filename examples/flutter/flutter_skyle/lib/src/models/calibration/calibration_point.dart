import '../base/point2d.dart';

/// Calibration point to display to the user
class CalibrationPoint {
  /// Point index (0-8 for 9-point calibration, 0-4 for 5-point)
  final int index;

  /// Screen coordinates (pixels)
  final Point2d coordinates;

  const CalibrationPoint({required this.index, required this.coordinates});

  @override
  String toString() => 'CalibrationPoint(index: $index, coordinates: $coordinates)';
}
