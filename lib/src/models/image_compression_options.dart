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
    this.fallbackFormat,
  });

  /// Codec quality, from 0 (smallest) to 100 (highest quality).
  final int quality;

  /// Requested output format. Native platform support varies by format.
  final ImageOutputFormat? outputFormat;

  /// Directory for the generated file. A directory is created if necessary.
  final Directory? outputDirectory;

  /// Format to retry with when a HEIC request fails.
  ///
  /// HEIC output is not available on every device, and the native codec
  /// reports the failure as `compressionFailed`. When this is set and the
  /// HEIC attempt fails, the operation is retried once in this format and
  /// `CompressionResult.usedFallbackFormat` is `true`. Null (the default)
  /// disables the retry, so a failed HEIC request throws as before. It must
  /// not be [ImageOutputFormat.heic].
  final ImageOutputFormat? fallbackFormat;
}
