import 'dart:io';

import 'image_output_format.dart';

/// The successful outcome of an image compression operation.
class CompressionResult {
  const CompressionResult({
    required this.originalFile,
    required this.outputFile,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    required this.outputFormat,
    this.usedFallbackFormat = false,
    this.outputWidth,
    this.outputHeight,
  });

  final File originalFile;
  final File outputFile;
  final int originalSizeBytes;
  final int compressedSizeBytes;

  /// The format that was actually written, which differs from the requested
  /// one when [usedFallbackFormat] is `true`.
  final ImageOutputFormat outputFormat;

  /// Whether [outputFormat] is the `fallbackFormat` used after the requested
  /// format failed.
  final bool usedFallbackFormat;

  /// Pixel width of [outputFile], or null if it could not be read (for
  /// example a HEIC file on a platform whose Flutter engine cannot decode it).
  final int? outputWidth;

  /// Pixel height of [outputFile], or null under the same conditions as
  /// [outputWidth].
  final int? outputHeight;

  /// Fraction of bytes saved, clamped to avoid invalid percentages.
  double get compressionRatio {
    if (originalSizeBytes <= 0) return 0;
    final ratio = (originalSizeBytes - compressedSizeBytes) / originalSizeBytes;
    return ratio.clamp(0, 1).toDouble();
  }

  /// Percentage of bytes saved, in the inclusive range 0 to 100.
  double get compressionPercentage => compressionRatio * 100;
}
