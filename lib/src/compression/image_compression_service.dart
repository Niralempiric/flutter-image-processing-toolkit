import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as path;

import '../exceptions/image_processing_exception.dart';
import '../models/compression_result.dart';
import '../models/image_compression_options.dart';
import '../models/image_output_format.dart';
import 'image_compressor.dart';
import 'exif_gps.dart';
import 'image_cropper.dart';
import 'native_image_compressor.dart';
import 'resize.dart';

/// Compresses image files using the native Android and iOS codecs.
class ImageCompressionService {
  ImageCompressionService({
    ImageCompressor? compressor,
    ImageSizeReader imageSizeReader = readImageSize,
    ImageCropper imageCropper = const UiImageCropper(),
  }) : _compressor = compressor ?? const NativeImageCompressor(),
       _readImageSize = imageSizeReader,
       _cropper = imageCropper;

  final ImageCompressor _compressor;
  final ImageSizeReader _readImageSize;
  final ImageCropper _cropper;

  /// Creates a new compressed file and leaves [input] unchanged.
  ///
  /// When [ImageCompressionOptions.cropRect] is set, that part of the image is
  /// cut out first and the rest of the options apply to the cropped image.
  Future<CompressionResult> compress(
    File input, {
    ImageCompressionOptions options = const ImageCompressionOptions(),
  }) async {
    _validateOptions(options);
    final originalSize = await _validateInput(input);
    final format = options.outputFormat ?? _formatForPath(input.path);
    if (options.keepExif &&
        options.stripLocation &&
        format != ImageOutputFormat.jpeg) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'stripLocation with keepExif is supported for JPEG output only.',
      );
    }
    final cropRect = options.cropRect;
    if (cropRect == null) {
      return _compressWithFallback(input, input, originalSize, format, options);
    }
    if (options.keepExif) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'keepExif cannot be combined with cropRect: the cropped image does '
        'not carry the source metadata.',
      );
    }
    final area = await _cropArea(input, cropRect);
    final scratch = await Directory.systemTemp.createTemp(
      'image_toolkit_crop_',
    );
    try {
      final cropped = File(path.join(scratch.path, 'cropped.png'));
      try {
        await _cropper.cropToPng(
          input: input,
          left: area.left,
          top: area.top,
          width: area.width,
          height: area.height,
          output: cropped,
        );
      } catch (error) {
        throw ImageProcessingException(
          ImageProcessingErrorCode.compressionFailed,
          'Unable to crop the image.',
          cause: error,
        );
      }
      return await _compressWithFallback(
        input,
        cropped,
        originalSize,
        format,
        options,
      );
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  /// Validates [rect] against the displayed size of [input] and rounds it to
  /// whole pixels.
  Future<({int left, int top, int width, int height})> _cropArea(
    File input,
    Rect rect,
  ) async {
    if (!rect.isFinite) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'The crop rectangle must have finite coordinates.',
      );
    }
    final size = await _readImageSize(input);
    if (size == null) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.compressionFailed,
        'Unable to read the image dimensions needed to crop it.',
      );
    }
    final left = rect.left.round();
    final top = rect.top.round();
    final right = rect.right.round();
    final bottom = rect.bottom.round();
    if (left < 0 ||
        top < 0 ||
        right > size.width ||
        bottom > size.height ||
        right <= left ||
        bottom <= top) {
      throw ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'The crop rectangle ($left, $top)-($right, $bottom) must be '
        'non-empty and inside the ${size.width}x${size.height} image.',
      );
    }
    return (left: left, top: top, width: right - left, height: bottom - top);
  }

  /// Compresses [source] as [format]. When that is a HEIC request that fails
  /// and [ImageCompressionOptions.fallbackFormat] is set, retries once in the
  /// fallback format. A cropped [source] is reused for the retry.
  Future<CompressionResult> _compressWithFallback(
    File input,
    File source,
    int originalSize,
    ImageOutputFormat format,
    ImageCompressionOptions options,
  ) async {
    final fallback = options.fallbackFormat;
    try {
      return await _compressSource(
        input,
        source,
        originalSize,
        format,
        options,
      );
    } on ImageProcessingException catch (error) {
      final canFallBack =
          fallback != null &&
          format == ImageOutputFormat.heic &&
          error.code == ImageProcessingErrorCode.compressionFailed;
      if (!canFallBack) rethrow;
      return _compressSource(
        input,
        source,
        originalSize,
        fallback,
        options,
        usedFallbackFormat: true,
      );
    }
  }

  /// Compresses [source], which is [input] itself or a cropped copy of it.
  /// Results and file names refer to [input].
  Future<CompressionResult> _compressSource(
    File input,
    File source,
    int originalSize,
    ImageOutputFormat format,
    ImageCompressionOptions options, {
    bool usedFallbackFormat = false,
  }) async {
    final target = await _resizeTarget(source, options);
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
        inputPath: source.path,
        outputPath: outputPath,
        quality: options.quality,
        format: format,
        targetWidth: target?.width,
        targetHeight: target?.height,
        keepExif: options.keepExif,
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
      if (options.keepExif && options.stripLocation) {
        final withoutGps = removeGpsFromJpeg(await output.readAsBytes());
        if (withoutGps != null) await output.writeAsBytes(withoutGps);
      }
      final outputSize = await _readImageSize(output);
      return CompressionResult(
        originalFile: input,
        outputFile: output,
        originalSizeBytes: originalSize,
        compressedSizeBytes: compressedSize,
        outputFormat: format,
        usedFallbackFormat: usedFallbackFormat,
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
    if (options.fallbackFormat == ImageOutputFormat.heic) {
      throw const ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'fallbackFormat must be a format other than HEIC.',
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
