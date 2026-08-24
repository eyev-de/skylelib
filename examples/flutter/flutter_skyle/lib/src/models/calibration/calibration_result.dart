import '../base/point2d.dart';

/// Calibration result after completion

class CalibrationQualityPoint {
  final int index;
  final Point2d accuracy;
  final double precision;
  final int quality;

  const CalibrationQualityPoint({required this.index, required this.accuracy, required this.precision, required this.quality});

  @override
  String toString() => 'CalibrationQualityPoint(index: $index, accuracy: $accuracy, precision: $precision, quality: $quality)';
}

class CalibrationResult {
  final List<CalibrationQualityPoint> left;
  final List<CalibrationQualityPoint> right;

  const CalibrationResult({required this.left, required this.right});

  @override
  String toString() => 'CalibrationResult(left: $left, right: $right)';
}
