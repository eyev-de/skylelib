import '../base/point2d.dart';

/// Calibration result after completion

class CalibrationQualityPoint {
  /// [flags] bit: this eye's own measured data; clear for the untracked eye in a left or right only mode, whose entry
  /// repeats the tracked eye's values.
  static const int flagValid = 0x01;

  /// [flags] bit: excluded by the grid validator (not used in the fit).
  static const int flagExcluded = 0x02;

  /// [flags] bit: synthesised marker (1- and 2-point calibrations), no measured data.
  static const int flagSynthesised = 0x04;

  /// [flags] bit: the eye was not seen to settle on the marker; the frames were collected after the fixation gate's
  /// fallback wait (3 s), so the point is unverified.
  static const int flagUnsettled = 0x08;

  final int index;
  final Point2d accuracy;
  final double precision;
  final int quality;

  /// Per-eye flag bits (see the `flag*` constants), other bits are reserved; 0 without [CalibrationResult.details].
  final int flags;

  /// Samples of this eye the fit used at this point; 0 without [CalibrationResult.details].
  final int sampleCount;

  const CalibrationQualityPoint({
    required this.index,
    required this.accuracy,
    required this.precision,
    required this.quality,
    this.flags = 0,
    this.sampleCount = 0,
  });

  bool get isValid => flags & flagValid != 0;

  bool get isExcluded => flags & flagExcluded != 0;

  bool get isSynthesised => flags & flagSynthesised != 0;

  bool get isUnsettled => flags & flagUnsettled != 0;

  @override
  String toString() =>
      'CalibrationQualityPoint(index: $index, accuracy: $accuracy, precision: $precision, quality: $quality, flags: 0x${flags.toRadixString(16)}, '
      'sampleCount: $sampleCount)';
}

class CalibrationResult {
  final List<CalibrationQualityPoint> left;
  final List<CalibrationQualityPoint> right;

  /// Calibration details sent with the FinishedCalibration message; null with firmware that sends none.
  final CalibrationDetails? details;

  const CalibrationResult({required this.left, required this.right, this.details});

  @override
  String toString() => 'CalibrationResult(left: $left, right: $right, details: $details)';
}

/// Why a calibration failed ([CalibrationDetails.reason]).
///
/// Wire values match `skyle_calibration_failure_reason` (append only); unknown values decode as [unspecified].
enum CalibrationFailureReason {
  /// No reason given (always on success).
  unspecified(0),

  /// Global calibration timeout.
  timeout(1),

  /// One point did not finish within its per-point timeout.
  pointTimeout(2),

  /// Samples were collected but the fit was rejected.
  fitRejected(3),

  /// ConfigureCalibration refused: another client (gRPC) runs a calibration.
  otherClientCalibrating(4),

  /// ConfigureCalibration refused: invalid points, nothing to improve or busy.
  configurationRejected(5);

  const CalibrationFailureReason(this.value);

  /// Wire value.
  final int value;

  static CalibrationFailureReason fromValue(int value) =>
      values.firstWhere((e) => e.value == value, orElse: () => CalibrationFailureReason.unspecified);
}

/// Calibration details, the optional trailer of the FinishedCalibration message ([CalibrationResult.details]).
///
/// [success] decides on its own: a successful fit can have every quality at 0. Accuracy is not sent; derive it per eye
/// from the [CalibrationQualityPoint.quality] with [accuracyDegForQuality].
class CalibrationDetails {
  final bool success;

  /// [CalibrationFailureReason.unspecified] on success.
  final CalibrationFailureReason reason;

  /// Accuracy in degrees that maps to quality 0; a quality of 0 means an accuracy of this value or worse.
  final double zeroQualityAccuracyDeg;

  const CalibrationDetails({required this.success, required this.reason, required this.zeroQualityAccuracyDeg});

  /// Accuracy in degrees for a quality 0..255; a lower bound for quality 0.
  double accuracyDegForQuality(int quality) => zeroQualityAccuracyDeg * (1 - quality / 255);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalibrationDetails &&
          other.success == success &&
          other.reason == reason &&
          other.zeroQualityAccuracyDeg == zeroQualityAccuracyDeg;

  @override
  int get hashCode => Object.hash(success, reason, zeroQualityAccuracyDeg);

  @override
  String toString() => 'CalibrationDetails(success: $success, reason: ${reason.name}, zeroQualityAccuracyDeg: $zeroQualityAccuracyDeg)';
}
