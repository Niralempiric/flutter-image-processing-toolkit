import 'dart:io';
import 'dart:ui' as ui;

/// Pixel dimensions of an image.
typedef ImageSize = ({int width, int height});

/// Reads the pixel dimensions of [file], or returns null when they cannot be
/// determined (an unreadable file, or a format Flutter cannot decode).
typedef ImageSizeReader = Future<ImageSize?> Function(File file);

/// Default [ImageSizeReader]: reads the image header without decoding pixels.
Future<ImageSize?> readImageSize(File file) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes());
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return (width: descriptor.width, height: descriptor.height);
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Scales [source] down to fit inside [maxWidth] by [maxHeight], keeping the
/// aspect ratio.
///
/// Either bound may be null, meaning unbounded on that side. An image that
/// already fits is returned unchanged: this never upscales. Each side is at
/// least one pixel.
ImageSize fitWithin(ImageSize source, {int? maxWidth, int? maxHeight}) {
  var scale = 1.0;
  if (maxWidth != null && source.width > maxWidth) {
    scale = maxWidth / source.width;
  }
  if (maxHeight != null && source.height > maxHeight) {
    final heightScale = maxHeight / source.height;
    if (heightScale < scale) scale = heightScale;
  }
  if (scale == 1.0) return source;
  return (
    width: (source.width * scale).round().clamp(1, source.width),
    height: (source.height * scale).round().clamp(1, source.height),
  );
}
