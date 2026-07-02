import '../../ffi/ffi_structs.dart';

/// Size with uint16 dimensions
final class Sizeu {
  final int width;
  final int height;

  const Sizeu(this.width, this.height);

  factory Sizeu.fromEapSizeu(EapSizeu size) {
    return Sizeu(size.width.toInt(), size.height.toInt());
  }

  @override
  String toString() => 'Sizeu16($width x $height)';

  factory Sizeu.fromJson(Map<String, dynamic> json) {
    return Sizeu(json['width'], json['height']);
  }

  Map<String, dynamic> toJson() => {'width': width, 'height': height};
}
