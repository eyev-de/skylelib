/// Calibration progress for current point
class CalibrationProgress {
  /// Current point index being calibrated
  final int index;

  /// Progress percentage (0-100)
  final int progress;

  const CalibrationProgress({required this.index, required this.progress});

  @override
  String toString() => 'CalibrationProgress(point: $index, progress: $progress%)';
}
