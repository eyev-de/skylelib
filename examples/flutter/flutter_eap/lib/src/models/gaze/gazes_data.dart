import 'dart:typed_data';

import '../../ffi/ffi_structs.dart';
import 'gaze_data.dart';
import 'gaze_type.dart';
import '../base/point2d.dart';

/// Number of doubles in the binary gaze representation.
/// Layout: [timestamp, left(raw.x, raw.y, smoothed.x, smoothed.y, type),
///          right(...), combined(...)]
const _gazeBufferLength = 16;

/// Reusable buffer for zero-allocation binary serialization at 60Hz.
final _sharedBuf = Float64List(_gazeBufferLength);

/// Complete gaze data with both eyes and combined gaze
class GazesData {
  /// Device timestamp of the gaze data
  final int timestamp;

  /// Left eye gaze data
  final GazeData leftEye;

  /// Right eye gaze data
  final GazeData rightEye;

  /// Combined gaze data (most accurate)
  final GazeData combined;

  const GazesData({required this.timestamp, required this.leftEye, required this.rightEye, required this.combined});

  factory GazesData.fromEapGazeResponse(EapGazeResponse response) {
    return GazesData(
      timestamp: response.header.timestampMs,
      leftEye: GazeData.fromEapComplexGaze(response.left),
      rightEye: GazeData.fromEapComplexGaze(response.right),
      combined: GazeData.fromEapComplexGaze(response.both),
    );
  }

  void scale(double scale) {
    leftEye.scale(scale);
    rightEye.scale(scale);
    combined.scale(scale);
  }

  /// Convenience getter for combined gaze X coordinate (screen space, pixels)
  double get gazeX => combined.smoothed.x;

  /// Convenience getter for combined gaze Y coordinate (screen space, pixels)
  double get gazeY => combined.smoothed.y;

  @override
  String toString() => 'GazeData(combined=$combined, left=$leftEye, right=$rightEye)';

  factory GazesData.fromJson(Map<String, dynamic> json) {
    return GazesData(
      timestamp: json['timestamp'],
      leftEye: GazeData.fromJson(json['left']),
      rightEye: GazeData.fromJson(json['right']),
      combined: GazeData.fromJson(json['combined']),
    );
  }

  Map<String, dynamic> toJson() => {'timestamp': timestamp, 'left': leftEye.toJson(), 'right': rightEye.toJson(), 'combined': combined.toJson()};

  /// Serialize to a reusable Float64List for zero-allocation IPC at 60Hz.
  /// The returned view is backed by a shared buffer -- copy it if you need
  /// to store it beyond the current call frame.
  Float64List toBytes() {
    _sharedBuf[0] = timestamp.toDouble();
    _sharedBuf[1] = leftEye.raw.x;
    _sharedBuf[2] = leftEye.raw.y;
    _sharedBuf[3] = leftEye.smoothed.x;
    _sharedBuf[4] = leftEye.smoothed.y;
    _sharedBuf[5] = leftEye.type.value.toDouble();
    _sharedBuf[6] = rightEye.raw.x;
    _sharedBuf[7] = rightEye.raw.y;
    _sharedBuf[8] = rightEye.smoothed.x;
    _sharedBuf[9] = rightEye.smoothed.y;
    _sharedBuf[10] = rightEye.type.value.toDouble();
    _sharedBuf[11] = combined.raw.x;
    _sharedBuf[12] = combined.raw.y;
    _sharedBuf[13] = combined.smoothed.x;
    _sharedBuf[14] = combined.smoothed.y;
    _sharedBuf[15] = combined.type.value.toDouble();
    return _sharedBuf;
  }

  /// Reconstruct GazesData from a Float64List produced by [toBytes].
  factory GazesData.fromBytes(Float64List b) {
    return GazesData(
      timestamp: b[0].toInt(),
      leftEye: GazeData(raw: Point2d(b[1], b[2]), smoothed: Point2d(b[3], b[4]), type: GazeType.fromValue(b[5].toInt())),
      rightEye: GazeData(raw: Point2d(b[6], b[7]), smoothed: Point2d(b[8], b[9]), type: GazeType.fromValue(b[10].toInt())),
      combined: GazeData(raw: Point2d(b[11], b[12]), smoothed: Point2d(b[13], b[14]), type: GazeType.fromValue(b[15].toInt())),
    );
  }
}
