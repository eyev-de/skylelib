import '../../ffi/ffi_structs.dart';
import 'feature_data.dart';
import 'glints_data.dart';
import 'iris_data.dart';
import '../base/rect2d.dart';

/// Complete eye data with all features
class EyeData {
  final Rect2d boundingRect; // Eye bounding rectangle (uint16 in C)
  final FeatureData pupil;
  final GlintsData glints;
  final IrisData iris;

  const EyeData({required this.boundingRect, required this.pupil, required this.glints, required this.iris});

  static final EyeData empty = EyeData(boundingRect: Rect2d.empty, pupil: FeatureData.empty, glints: GlintsData.empty, iris: IrisData.empty);

  factory EyeData.fromSkyleEye(SkyleComplexEye eye) {
    return EyeData(
      boundingRect: Rect2d.fromSkyleRectu(eye.boundingRect),
      pupil: FeatureData.fromSkyleFeature(eye.pupil),
      glints: GlintsData.fromSkyleGlints(eye.leftGlint, eye.rightGlint),
      iris: IrisData.fromSkyleIris(eye.iris),
    );
  }

  @override
  String toString() => 'EyeData(pupil=${pupil.center}, iris=${iris.center}, distance=${iris.distance}mm)';

  factory EyeData.fromJson(Map<String, dynamic> json) {
    return EyeData(
      boundingRect: Rect2d.fromJson(json['boundingRect']),
      pupil: FeatureData.fromJson(json['pupil']),
      glints: GlintsData.fromJson(json['glints']),
      iris: IrisData.fromJson(json['iris']),
    );
  }

  Map<String, dynamic> toJson() => {'boundingRect': boundingRect.toJson(), 'pupil': pupil.toJson(), 'glints': glints.toJson(), 'iris': iris.toJson()};
}
