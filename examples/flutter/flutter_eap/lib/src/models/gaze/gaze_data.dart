import '../../ffi/ffi_structs.dart';
import 'gaze_type.dart';
import '../base/point2d.dart';

/// Gaze data for a single eye
/// Contains both raw and smoothed gaze positions
class GazeData {
  /// Raw gaze position (unfiltered)
  final Point2d raw;

  /// Smoothed gaze position (filtered, recommended for use)
  final Point2d smoothed;

  /// Movement type (fixation, saccade, or unknown)
  final GazeType type;

  const GazeData({required this.raw, required this.smoothed, required this.type});

  factory GazeData.fromEapComplexGaze(EapComplexGaze gaze) {
    return GazeData(raw: Point2d.fromEapPointf(gaze.raw), smoothed: Point2d.fromEapPointf(gaze.smoothed), type: GazeType.fromValue(gaze.type));
  }

  void scale(double scale) {
    raw.scale(scale);
    smoothed.scale(scale);
  }

  @override
  String toString() => 'GazeData(smoothed=$smoothed, raw=$raw, type=$type)';

  factory GazeData.fromJson(Map<String, dynamic> json) {
    return GazeData(raw: Point2d.fromJson(json['raw']), smoothed: Point2d.fromJson(json['smoothed']), type: GazeType.fromValue(json['type']));
  }

  Map<String, dynamic> toJson() => {'raw': raw.toJson(), 'smoothed': smoothed.toJson(), 'type': type.value};
}
