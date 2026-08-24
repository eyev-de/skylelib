import '../../ffi/ffi_structs.dart';
import '../base/point2d.dart';
import '../base/rect2d.dart';
import '../base/rotated_rect.dart';

/// Feature data (pupil or glint)
class FeatureData {
  final Point2d center;
  final Rect2d boundingRect;
  final RotatedRect ellipse;

  const FeatureData({required this.center, required this.boundingRect, required this.ellipse});

  static final FeatureData empty = FeatureData(center: Point2d.empty(), boundingRect: Rect2d.empty, ellipse: RotatedRect.empty);

  factory FeatureData.fromSkyleFeature(SkyleComplexFeature feature) {
    return FeatureData(
      center: Point2d.fromSkylePointf(feature.center),
      boundingRect: Rect2d.fromSkyleRectf(feature.boundingRect),
      ellipse: RotatedRect.fromSkyleRotatedRect(feature.ellipse),
    );
  }

  @override
  String toString() => 'FeatureData(center=$center, ellipse=$ellipse)';

  factory FeatureData.fromJson(Map<String, dynamic> json) {
    return FeatureData(
      center: Point2d.fromJson(json['center']),
      boundingRect: Rect2d.fromJson(json['boundingRect']),
      ellipse: RotatedRect.fromJson(json['ellipse']),
    );
  }

  Map<String, dynamic> toJson() => {'center': center.toJson(), 'boundingRect': boundingRect.toJson(), 'ellipse': ellipse.toJson()};
}
