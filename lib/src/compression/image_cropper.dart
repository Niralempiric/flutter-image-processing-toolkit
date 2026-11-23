import 'dart:io';
import 'dart:ui' as ui;

/// Writes a rectangular part of an image to a new file.
///
/// The service uses this before compressing when a crop is requested. It is an
/// interface so tests can replace the decoder.
abstract interface class ImageCropper {
  /// Writes the pixels of [input] inside the given rectangle to [output] as a
  /// lossless PNG.
  ///
  /// The rectangle is in pixels of the image as displayed, that is after any
  /// EXIF orientation is applied, and has already been checked to lie inside
  /// the image.
  Future<void> cropToPng({
    required File input,
    required int left,
    required int top,
    required int width,
    required int height,
    required File output,
  });
}

/// Crops with `dart:ui`: decode, draw the wanted part, encode as PNG.
///
/// The whole source is decoded into memory, so a very large photo needs
/// roughly four bytes per pixel while it is cropped.
class UiImageCropper implements ImageCropper {
  const UiImageCropper();

  @override
  Future<void> cropToPng({
    required File input,
    required int left,
    required int top,
    required int width,
    required int height,
    required File output,
  }) async {
    final codec = await ui.instantiateImageCodec(await input.readAsBytes());
    ui.Image? source;
    ui.Image? cropped;
    ui.Picture? picture;
    try {
      source = (await codec.getNextFrame()).image;
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        source,
        ui.Rect.fromLTWH(
          left.toDouble(),
          top.toDouble(),
          width.toDouble(),
          height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        // No smoothing: source and destination are the same size, so this
        // copies pixels as they are.
        ui.Paint()..filterQuality = ui.FilterQuality.none,
      );
      picture = recorder.endRecording();
      cropped = await picture.toImage(width, height);
      final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw StateError('The cropped image could not be encoded.');
      }
      await output.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
    } finally {
      cropped?.dispose();
      picture?.dispose();
      source?.dispose();
      codec.dispose();
    }
  }
}
