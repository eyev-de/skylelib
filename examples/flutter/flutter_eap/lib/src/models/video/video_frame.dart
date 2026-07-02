import 'dart:typed_data';

/// A single video frame with dimension metadata from the device.
class VideoFrame {
  final int width;
  final int height;
  final int channels;
  final Uint8List pixelData;

  const VideoFrame({
    required this.width,
    required this.height,
    required this.channels,
    required this.pixelData,
  });

  @override
  String toString() => 'VideoFrame(${width}x$height, channels=$channels, ${pixelData.length} bytes)';
}
