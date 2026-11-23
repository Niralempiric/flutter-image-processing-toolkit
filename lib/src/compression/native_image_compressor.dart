import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/image_output_format.dart';
import 'image_compressor.dart';

// Defaults of FlutterImageCompress.compressAndGetFile (flutter_image_compress
// 2.x), kept so that a request without a resize target behaves as it did.
const _pluginDefaultMinWidth = 1920;
const _pluginDefaultMinHeight = 1080;

class NativeImageCompressor implements ImageCompressor {
  const NativeImageCompressor();

  @override
  Future<String?> compress({
    required String inputPath,
    required String outputPath,
    required int quality,
    required ImageOutputFormat format,
    int? targetWidth,
    int? targetHeight,
    bool keepExif = false,
  }) async {
    final output = await FlutterImageCompress.compressAndGetFile(
      inputPath,
      outputPath,
      quality: quality,
      // The plugin's "min" size is the size to keep. For a size that has the
      // source's aspect ratio it yields exactly that size. When no target is
      // given, the plugin's own defaults are passed so behavior is unchanged.
      minWidth: targetWidth ?? _pluginDefaultMinWidth,
      minHeight: targetHeight ?? _pluginDefaultMinHeight,
      keepExif: keepExif,
      format: switch (format) {
        ImageOutputFormat.jpeg => CompressFormat.jpeg,
        ImageOutputFormat.png => CompressFormat.png,
        ImageOutputFormat.webp => CompressFormat.webp,
        ImageOutputFormat.heic => CompressFormat.heic,
      },
    );
    return output?.path;
  }
}
