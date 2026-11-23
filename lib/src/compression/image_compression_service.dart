import 'dart:io';

import 'package:path/path.dart' as path;

import '../exceptions/image_processing_exception.dart';
import '../models/batch_item_result.dart';
import '../models/compression_result.dart';
import '../models/image_compression_options.dart';
import '../models/image_output_format.dart';
import 'image_compressor.dart';
import 'native_image_compressor.dart';

/// Compresses image files using the native Android and iOS codecs.
class ImageCompressionService {
  ImageCompressionService({ImageCompressor? compressor})
    : _compressor = compressor ?? const NativeImageCompressor();

  final ImageCompressor _compressor;

  /// Creates a new compressed file and leaves [input] unchanged.
  Future<CompressionResult> compress(
    File input, {
    ImageCompressionOptions options = const ImageCompressionOptions(),
  }) async {
    _validateOptions(options);
    final originalSize = await _validateInput(input);
    final format = options.outputFormat ?? _formatForPath(input.path);
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
      return CompressionResult(
        originalFile: input,
        outputFile: output,
        originalSizeBytes: originalSize,
        compressedSizeBytes: compressedSize,
        outputFormat: format,
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

  /// Compresses many files, a few at a time, and reports each outcome.
  ///
  /// Returns one [BatchItemResult] per entry of [inputs], in the same order.
  /// A file that fails is reported in its entry and does not stop the others,
  /// so this only throws for a problem with the call itself: invalid
  /// [options] or [maxConcurrent] below one, both checked before any work
  /// starts.
  ///
  /// At most [maxConcurrent] files are compressed at the same time. After each
  /// file finishes, [onProgress] is called with the number finished so far,
  /// the total, and that file's outcome; calls arrive in completion order,
  /// not input order. An exception thrown by [onProgress] does not stop the
  /// batch: the remaining files are processed and the first such exception is
  /// rethrown once every file has finished.
  Future<List<BatchItemResult>> compressMany(
    List<File> inputs, {
    ImageCompressionOptions options = const ImageCompressionOptions(),
    int maxConcurrent = 2,
    void Function(int completed, int total, BatchItemResult latest)? onProgress,
  }) async {
    _validateOptions(options);
    if (maxConcurrent < 1) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'maxConcurrent must be at least 1.',
      );
    }
    final total = inputs.length;
    final results = List<BatchItemResult?>.filled(total, null);
    var next = 0;
    var completed = 0;
    Object? callbackError;
    StackTrace? callbackStack;

    Future<void> worker() async {
      while (next < total) {
        final index = next++;
        final input = inputs[index];
        BatchItemResult outcome;
        try {
          outcome = BatchItemResult.success(
            input,
            await compress(input, options: options),
          );
        } on ImageProcessingException catch (error) {
          outcome = BatchItemResult.failure(input, error);
        } catch (error) {
          outcome = BatchItemResult.failure(
            input,
            ImageProcessingException(
              ImageProcessingErrorCode.compressionFailed,
              'Unable to compress the image.',
              cause: error,
            ),
          );
        }
        results[index] = outcome;
        completed++;
        try {
          onProgress?.call(completed, total, outcome);
        } catch (error, stack) {
          callbackError ??= error;
          callbackStack ??= stack;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < maxConcurrent && i < total; i++) worker(),
    ]);
    if (callbackError != null) {
      Error.throwWithStackTrace(callbackError!, callbackStack!);
    }
    return List<BatchItemResult>.unmodifiable(results);
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
