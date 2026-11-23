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
  /// Both limits are measured on the stored pixel grid, before any EXIF
  /// rotation is applied. Must be positive when set.
  final int? maxWidth;

  /// Largest output height in pixels, or null for no limit. See [maxWidth].
  final int? maxHeight;
}
