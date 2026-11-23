import 'dart:io';

import 'package:path/path.dart' as path;

import '../exceptions/image_processing_exception.dart';
import '../models/compression_result.dart';
import '../models/image_compression_options.dart';
import '../models/image_output_format.dart';
import 'image_compressor.dart';
import 'native_image_compressor.dart';
import 'resize.dart';

/// Compresses image files using the native Android and iOS codecs.
class ImageCompressionService {
  ImageCompressionService({
    ImageCompressor? compressor,
    ImageSizeReader imageSizeReader = readImageSize,
  }) : _compressor = compressor ?? const NativeImageCompressor(),
       _readImageSize = imageSizeReader;

  final ImageCompressor _compressor;
  final ImageSizeReader _readImageSize;

  /// Creates a new compressed file and leaves [input] unchanged.
  Future<CompressionResult> compress(
    File input, {
    ImageCompressionOptions options = const ImageCompressionOptions(),
  }) async {
    _validateOptions(options);
    final originalSize = await _validateInput(input);
    final format = options.outputFormat ?? _formatForPath(input.path);
    final target = await _resizeTarget(input, options);
    final outputDirectory =
        options.outputDirectory ??
        Directory(path.join(input.parent.path, 'compressed_images'));
    final outputPath = path.join(
      outputDirectory.path,
      '${path.basenameWithoutExtension(input.path)}_compressed_'
      '${DateTime.now().microsecondsSinceEpoch}.${format.fileExtension}',
    );
    final expectedOutput = File(outputPath);

    File? codecOutput;
    try {
      await outputDirectory.create(recursive: true);
      final outputPathFromCodec = await _compressor.compress(
        inputPath: input.path,
        outputPath: outputPath,
        quality: options.quality,
        format: format,
        targetWidth: target?.width,
        targetHeight: target?.height,
      );
      if (outputPathFromCodec == null) {
        throw const ImageProcessingException(
          ImageProcessingErrorCode.compressionFailed,
          'The native codec did not produce an output file.',
        );
      }
      final output = codecOutput = File(outputPathFromCodec);
      if (!await output.exists()) {
        throw const ImageProcessingException(
          ImageProcessingErrorCode.compressionFailed,
          'The native codec returned a path that does not exist.',
        );
      }
      if (path.equals(output.path, input.path)) {
        throw const ImageProcessingException(
          ImageProcessingErrorCode.compressionFailed,
          'The native codec returned the source file instead of a new '
          'output file.',
        );
      }
      final compressedSize = await output.length();
      if (compressedSize == 0) {
        throw const ImageProcessingException(
          ImageProcessingErrorCode.compressionFailed,
          'The native codec produced an empty output file.',
        );
      }
      final outputSize = await _readImageSize(output);
      return CompressionResult(
        originalFile: input,
        outputFile: output,
        originalSizeBytes: originalSize,
        compressedSizeBytes: compressedSize,
        outputFormat: format,
        outputWidth: outputSize?.width,
        outputHeight: outputSize?.height,
      );
    } on ImageProcessingException {
      await _discardPartialOutput(input, expectedOutput, codecOutput);
      rethrow;
    } catch (error) {
      await _discardPartialOutput(input, expectedOutput, codecOutput);
      throw ImageProcessingException(
        ImageProcessingErrorCode.compressionFailed,
        'Unable to compress the image.',
        cause: error,
      );
    }
  }

  /// The size to scale to, or null when no resize was requested.
  Future<ImageSize?> _resizeTarget(
    File input,
    ImageCompressionOptions options,
  ) async {
    final maxWidth = options.maxWidth;
    final maxHeight = options.maxHeight;
    if (maxWidth == null && maxHeight == null) return null;
    final source = await _readImageSize(input);
    if (source == null) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.compressionFailed,
        'Unable to read the image dimensions needed to resize it.',
      );
    }
    return fitWithin(source, maxWidth: maxWidth, maxHeight: maxHeight);
  }

  Future<int> _validateInput(File input) async {
    if (!await input.exists()) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'The input file does not exist.',
      );
    }
    final size = await input.length();
    if (size == 0) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'The input file is empty.',
      );
    }
    _formatForPath(input.path);
    return size;
  }

  void _validateOptions(ImageCompressionOptions options) {
    if (options.quality < 0 || options.quality > 100) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'Compression quality must be between 0 and 100.',
      );
    }
    final maxWidth = options.maxWidth;
    final maxHeight = options.maxHeight;
    if ((maxWidth != null && maxWidth <= 0) ||
        (maxHeight != null && maxHeight <= 0)) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'maxWidth and maxHeight must be positive when set.',
      );
    }
  }

  ImageOutputFormat _formatForPath(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return switch (extension) {
      '.jpg' || '.jpeg' => ImageOutputFormat.jpeg,
      '.png' => ImageOutputFormat.png,
      '.webp' => ImageOutputFormat.webp,
      '.heic' => ImageOutputFormat.heic,
      _ => throw ImageProcessingException(
        ImageProcessingErrorCode.unsupportedFormat,
        'Unsupported image format: ${extension.isEmpty ? '(none)' : extension}.',
      ),
    };
  }

  /// Removes anything the failed operation may have written.
  ///
  /// A codec can report a path other than the one it was given, so both are
  /// cleared. [input] is never removed: the source file must survive a
  /// failure even if the codec named it as its own output.
  Future<void> _discardPartialOutput(
    File input,
    File expectedOutput,
    File? codecOutput,
  ) async {
    await _deleteIfPresent(expectedOutput);
    if (codecOutput == null) return;
    if (path.equals(codecOutput.path, expectedOutput.path)) return;
    if (path.equals(codecOutput.path, input.path)) return;
    await _deleteIfPresent(codecOutput);
  }

  Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }
}
