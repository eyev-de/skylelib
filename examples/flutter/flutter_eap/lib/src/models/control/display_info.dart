import '../base/size2d.dart';
import '../base/sizeu.dart';

/// Display information sent to the device so it can map gaze coordinates
/// and drive calibration using the client's physical display.
///
/// - [resolution] in pixels (logical or physical — must match the coordinate
///   space used elsewhere by the device).
/// - [sizeMm] physical display size in millimeters.
///
/// Corresponds to the EAP `SetDisplayInfo` message (type 0x00E2).
final class DisplayInfo {
  final Sizeu resolution;
  final Size2d sizeMm;

  const DisplayInfo({required this.resolution, required this.sizeMm});

  @override
  String toString() => 'DisplayInfo(${resolution.width}x${resolution.height}px, '
      '${sizeMm.width.toStringAsFixed(1)}x${sizeMm.height.toStringAsFixed(1)}mm)';

  Map<String, dynamic> toJson() => {
        'resolution': resolution.toJson(),
        'sizeMm': sizeMm.toJson(),
      };

  factory DisplayInfo.fromJson(Map<String, dynamic> json) => DisplayInfo(
        resolution: Sizeu.fromJson(json['resolution'] as Map<String, dynamic>),
        sizeMm: Size2d.fromJson(json['sizeMm'] as Map<String, dynamic>),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplayInfo &&
          other.resolution.width == resolution.width &&
          other.resolution.height == resolution.height &&
          other.sizeMm.width == sizeMm.width &&
          other.sizeMm.height == sizeMm.height;

  @override
  int get hashCode => Object.hash(
      resolution.width, resolution.height, sizeMm.width, sizeMm.height);
}
