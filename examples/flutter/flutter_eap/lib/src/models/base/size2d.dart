import '../../ffi/ffi_structs.dart';

/// Size with double dimensions
class Size2d {
  final double width;
  final double height;

  const Size2d(this.width, this.height);

  static const Size2d empty = Size2d(0, 0);

  factory Size2d.fromEapSizef(EapSizef size) {
    return Size2d(size.width.toDouble(), size.height.toDouble());
  }

  @override
  String toString() => 'Size2D($width x $height)';

  factory Size2d.fromJson(Map<String, dynamic> json) {
    return Size2d(json['width'], json['height']);
  }

  Map<String, dynamic> toJson() => {'width': width, 'height': height};
}
