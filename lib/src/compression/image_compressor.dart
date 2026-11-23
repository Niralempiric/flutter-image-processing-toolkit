import '../models/image_output_format.dart';

/// Boundary around the native codec used by [ImageCompressionService].
abstract interface class ImageCompressor {
  Future<String?> compress({
    required String inputPath,
    required String outputPath,
    required int quality,
    required ImageOutputFormat format,
    int? targetWidth,
    int? targetHeight,
    bool keepExif = false,
  });
}
