import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_eap_riverpod/flutter_eap_riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows the device video stream. Each frame (1=grayscale, 3=BGR, 4=BGRA) is
/// converted to RGBA and decoded to a `ui.Image`, drawn scaled to fit.
class VideoView extends ConsumerStatefulWidget {
  const VideoView({super.key});

  @override
  ConsumerState<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends ConsumerState<VideoView> {
  ui.Image? _image;
  bool _decoding = false;

  void _onFrame(VideoFrame frame) {
    if (_decoding || frame.width <= 0 || frame.height <= 0) return;
    _decoding = true;

    final rgba = _toRgba(frame);
    ui.decodeImageFromPixels(
      rgba,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      (img) {
        _decoding = false;
        if (!mounted) {
          img.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = img;
        });
      },
    );
  }

  static Uint8List _toRgba(VideoFrame frame) {
    final n = frame.width * frame.height;
    final src = frame.pixelData;
    final out = Uint8List(n * 4);
    final ch = frame.channels;
    for (var i = 0; i < n; i++) {
      final d = i * 4;
      if (ch == 1) {
        final g = i < src.length ? src[i] : 0;
        out[d] = g;
        out[d + 1] = g;
        out[d + 2] = g;
      } else {
        final s = i * ch;
        // BGR(A) -> RGBA
        out[d] = s + 2 < src.length ? src[s + 2] : 0;
        out[d + 1] = s + 1 < src.length ? src[s + 1] : 0;
        out[d + 2] = s < src.length ? src[s] : 0;
      }
      out[d + 3] = 255;
    }
    return out;
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(eapVideoDataStreamProvider, (_, next) {
      final frame = next.value;
      if (frame != null) _onFrame(frame);
    });

    final image = _image;
    // Constrain the panel to the frame's aspect ratio so its edge is the real
    // frame edge (matches the positioning view). Fall back to the sensor aspect
    // before the first frame so layout is stable.
    final aspect = image != null ? image.width / image.height : 2464 / 2064;

    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: image == null
              ? Center(
                  child: Text('No video',
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                )
              : RawImage(image: image, fit: BoxFit.fill),
        ),
      ),
    );
  }
}
