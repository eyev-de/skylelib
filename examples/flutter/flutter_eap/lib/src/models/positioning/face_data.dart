import '../../ffi/ffi_structs.dart';
import 'eye_data.dart';
import '../base/rect2d.dart';

/// Complete face data with both eyes and face
class FaceData {
  final Rect2d faceRect;
  final EyeData leftEye;
  final EyeData rightEye;

  const FaceData({required this.faceRect, required this.leftEye, required this.rightEye});

  static final FaceData empty = FaceData(faceRect: Rect2d.empty, leftEye: EyeData.empty, rightEye: EyeData.empty);

  factory FaceData.fromEapPositioningResponse(EapPositioningResponse response) {
    return FaceData(
      faceRect: Rect2d.fromEapRectf(response.face.boundingRect),
      leftEye: EyeData.fromEapEye(response.face.eyes.left),
      rightEye: EyeData.fromEapEye(response.face.eyes.right),
    );
  }

  @override
  String toString() => 'FaceData(face=$faceRect, leftEye=$leftEye, rightEye=$rightEye)';

  factory FaceData.fromJson(Map<String, dynamic> json) {
    return FaceData(faceRect: Rect2d.fromJson(json['faceRect']), leftEye: EyeData.fromJson(json['leftEye']), rightEye: EyeData.fromJson(json['rightEye']));
  }

  Map<String, dynamic> toJson() => {'faceRect': faceRect.toJson(), 'leftEye': leftEye.toJson(), 'rightEye': rightEye.toJson()};
}
