import 'calibration_point.dart';
import 'calibration_progress.dart';
import 'calibration_result.dart';

abstract class CalibrationMessage {
  @override
  String toString();
}

class NextCalibrationPointMessage extends CalibrationMessage {
  final CalibrationPoint point;
  NextCalibrationPointMessage({required this.point});

  @override
  String toString() => 'NextCalibrationPointMessage(point: $point)';
}

class ProgressCalibrationPointMessage extends CalibrationMessage {
  final CalibrationProgress progress;
  ProgressCalibrationPointMessage({required this.progress});

  @override
  String toString() => 'ProgressCalibrationPointMessage(progress: $progress)';
}

class PausedCalibrationMessage extends CalibrationMessage {
  @override
  String toString() => 'PausedCalibrationMessage()';
}

class AbortCalibrationMessage extends CalibrationMessage {
  @override
  String toString() => 'AbortCalibrationMessage()';
}

class FinishedCalibrationMessage extends CalibrationMessage {
  final CalibrationResult result;

  FinishedCalibrationMessage({required this.result});

  @override
  String toString() => 'FinishedCalibrationMessage(result: $result)';
}
