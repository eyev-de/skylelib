/// Calibration progress for current point
class CalibrationProgress {
  /// Current point index being calibrated
  final int index;

  /// Collection progress 0-255, 255 = point complete (not a percentage)
  final int progress;

  const CalibrationProgress({required this.index, required this.progress});

  @override
  String toString() => 'CalibrationProgress(point: $index, progress: $progress/255)';
}
