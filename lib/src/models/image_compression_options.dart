import 'dart:io';

import 'image_output_format.dart';

/// Controls one compression operation.
class ImageCompressionOptions {
  /// Creates compression options.
  ///
  /// [quality] is an inclusive value between 0 and 100. A null [outputFormat]
  /// preserves the input format when that format is supported.
  const ImageCompressionOptions({
    this.quality = 80,
    this.outputFormat,
    this.outputDirectory,
    this.maxWidth,
    this.maxHeight,
    this.keepExif = false,
    this.stripLocation = false,
  });

  /// Codec quality, from 0 (smallest) to 100 (highest quality).
  final int quality;

  /// Requested output format. Native platform support varies by format.
  final ImageOutputFormat? outputFormat;

  /// Directory for the generated file. A directory is created if necessary.
  final Directory? outputDirectory;

  /// Largest output width in pixels, or null for no limit.
  ///
  /// The image is scaled down to fit inside [maxWidth] by [maxHeight] while
  /// keeping its aspect ratio. An image that already fits is never upscaled.
  /// Both limits apply to the image as it is displayed, after any EXIF
  /// orientation is applied, so a portrait photo stored rotated is limited
  /// the same way as an upright one. Must be positive when set.
  final int? maxWidth;

  /// Largest output height in pixels, or null for no limit. See [maxWidth].
  final int? maxHeight;

  /// Whether to copy the source's EXIF metadata (camera, date, GPS and so on)
  /// into the output. Defaults to false, which writes no metadata, as in 0.1.0.
  ///
  /// The orientation tag is always reset, because the pixels are already
  /// rotated into display orientation. Only JPEG output carries EXIF through
  /// the native codec.
  final bool keepExif;

  /// Whether to remove the GPS location from the output while keeping the rest
  /// of the EXIF metadata. Only meaningful with [keepExif]: when EXIF is not
  /// kept there is no location to remove.
  ///
  /// Supported for JPEG output only; combining it with [keepExif] and another
  /// output format is rejected. If the location cannot be removed the
  /// operation fails and no output is left behind, rather than writing a file
  /// that still contains it. Other metadata that can reveal a place, such as a
  /// free-text caption, is kept.
  final bool stripLocation;
}
