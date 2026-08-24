import '../../ffi/ffi_structs.dart';
import 'feature_data.dart';

class GlintsData {
  final FeatureData left;
  final FeatureData right;

  const GlintsData({required this.left, required this.right});

  static final GlintsData empty = GlintsData(left: FeatureData.empty, right: FeatureData.empty);

  factory GlintsData.fromSkyleGlints(SkyleComplexFeature left, SkyleComplexFeature right) {
    return GlintsData(left: FeatureData.fromSkyleFeature(left), right: FeatureData.fromSkyleFeature(right));
  }

  factory GlintsData.fromJson(Map<String, dynamic> json) {
    return GlintsData(left: FeatureData.fromJson(json['left']), right: FeatureData.fromJson(json['right']));
  }

  Map<String, dynamic> toJson() => {'left': left.toJson(), 'right': right.toJson()};

  @override
  String toString() => 'GlintsData(left=$left, right=$right)';
}
