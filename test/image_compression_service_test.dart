import 'dart:io';

import 'package:flutter_image_processing_toolkit/flutter_image_processing_toolkit.dart';
import 'package:flutter_image_processing_toolkit/src/compression/image_compressor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('image-toolkit-test-');
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('compresses to a new file and preserves the original', () async {
    final original = await _write(sandbox, 'photo.jpg', [1, 2, 3, 4, 5, 6]);
    final service = ImageCompressionService(
      compressor: _FakeCompressor([1, 2]),
    );
    final outputDirectory = Directory('${sandbox.path}/exports');

    final result = await service.compress(
      original,
      options: ImageCompressionOptions(
        quality: 40,
        outputDirectory: outputDirectory,
      ),
    );

    expect(await result.outputFile.exists(), isTrue);
    expect(result.outputFile.path, startsWith(outputDirectory.path));
    expect(await original.readAsBytes(), [1, 2, 3, 4, 5, 6]);
    expect(result.originalSizeBytes, 6);
    expect(result.compressedSizeBytes, 2);
    expect(result.compressionPercentage, closeTo(66.666, 0.01));
    expect(result.outputFormat, ImageOutputFormat.jpeg);
  });

  test('passes quality and requested output format to the codec', () async {
    final original = await _write(sandbox, 'photo.png', [1, 2, 3]);
    final compressor = _FakeCompressor([1]);

    await ImageCompressionService(compressor: compressor).compress(
      original,
      options: const ImageCompressionOptions(
        quality: 12,
        outputFormat: ImageOutputFormat.webp,
      ),
    );

    expect(compressor.quality, 12);
    expect(compressor.format, ImageOutputFormat.webp);
    expect(compressor.outputPath, endsWith('.webp'));
  });

  test('rejects missing, empty, and unsupported input files', () async {
    final service = ImageCompressionService(compressor: _FakeCompressor([1]));
    final missing = File('${sandbox.path}/missing.jpg');
    final empty = await _write(sandbox, 'empty.jpg', []);
    final text = await _write(sandbox, 'notes.txt', [1]);

    await expectLater(
      service.compress(missing),
      throwsA(isA<ImageProcessingException>()),
    );
    await expectLater(
      service.compress(empty),
      throwsA(isA<ImageProcessingException>()),
    );
    await expectLater(
      service.compress(text),
      throwsA(
        isA<ImageProcessingException>().having(
          (error) => error.code,
          'code',
          ImageProcessingErrorCode.unsupportedFormat,
        ),
      ),
    );
  });

  test('rejects an out-of-range compression quality', () async {
    final original = await _write(sandbox, 'photo.jpg', [1]);
    final service = ImageCompressionService(compressor: _FakeCompressor([1]));

    await expectLater(
      service.compress(
        original,
        options: const ImageCompressionOptions(quality: 101),
      ),
      throwsA(
        isA<ImageProcessingException>().having(
          (error) => error.code,
          'code',
          ImageProcessingErrorCode.invalidInput,
        ),
      ),
    );
  });

  test('clamps a size increase to zero percent saved', () {
    final result = CompressionResult(
      originalFile: File('source.jpg'),
      outputFile: File('output.jpg'),
      originalSizeBytes: 10,
      compressedSizeBytes: 20,
      outputFormat: ImageOutputFormat.jpeg,
    );

    expect(result.compressionPercentage, 0);
  });

  test(
    'turns codec failures into typed errors and removes partial output',
    () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final outputDirectory = Directory('${sandbox.path}/exports');
      final service = ImageCompressionService(
        compressor: _ThrowingCompressor(),
      );

      await expectLater(
        service.compress(
          original,
          options: ImageCompressionOptions(outputDirectory: outputDirectory),
        ),
        throwsA(
          isA<ImageProcessingException>().having(
            (error) => error.code,
            'code',
            ImageProcessingErrorCode.compressionFailed,
          ),
        ),
      );
      expect(await outputDirectory.list().isEmpty, isTrue);
    },
  );

  for (final extension in const ['jpg', 'png', 'webp', 'heic']) {
    test('reports invalid $extension bytes as a codec failure', () async {
      final original = await _write(sandbox, 'corrupt.$extension', const [
        0x00,
        0x01,
        0x02,
        0x03,
      ]);
      final outputDirectory = Directory('${sandbox.path}/exports');
      final service = ImageCompressionService(
        compressor: _PartialWriteThenNullCompressor(),
      );

      await expectLater(
        service.compress(
          original,
          options: ImageCompressionOptions(outputDirectory: outputDirectory),
        ),
        throwsA(
          isA<ImageProcessingException>().having(
            (error) => error.code,
            'code',
            ImageProcessingErrorCode.compressionFailed,
          ),
        ),
      );
      expect(await outputDirectory.list().isEmpty, isTrue);
      expect(await original.readAsBytes(), [0x00, 0x01, 0x02, 0x03]);
    });
  }

  test('treats an empty codec output as a failure and removes it', () async {
    final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
    final outputDirectory = Directory('${sandbox.path}/exports');
    final service = ImageCompressionService(compressor: _FakeCompressor([]));

    await expectLater(
      service.compress(
        original,
        options: ImageCompressionOptions(outputDirectory: outputDirectory),
      ),
      throwsA(
        isA<ImageProcessingException>().having(
          (error) => error.code,
          'code',
          ImageProcessingErrorCode.compressionFailed,
        ),
      ),
    );
    expect(await outputDirectory.list().isEmpty, isTrue);
    expect(await original.readAsBytes(), [1, 2, 3]);
  });

  test('removes a partial file written outside the expected path', () async {
    final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
    final outputDirectory = Directory('${sandbox.path}/exports');
    final service = ImageCompressionService(compressor: _StrayPathCompressor());

    await expectLater(
      service.compress(
        original,
        options: ImageCompressionOptions(outputDirectory: outputDirectory),
      ),
      throwsA(isA<ImageProcessingException>()),
    );
    expect(await outputDirectory.list().isEmpty, isTrue);
  });

  test('keeps the source file when the codec returns the input path', () async {
    final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
    final outputDirectory = Directory('${sandbox.path}/exports');
    final service = ImageCompressionService(
      compressor: _SourcePathCompressor(),
    );

    await expectLater(
      service.compress(
        original,
        options: ImageCompressionOptions(outputDirectory: outputDirectory),
      ),
      throwsA(
        isA<ImageProcessingException>().having(
          (error) => error.code,
          'code',
          ImageProcessingErrorCode.compressionFailed,
        ),
      ),
    );
    expect(await original.exists(), isTrue);
    expect(await original.readAsBytes(), [1, 2, 3]);
    expect(await outputDirectory.list().isEmpty, isTrue);
  });

  group('fallbackFormat', () {
    test('retries a failed HEIC request in the fallback format', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3, 4]);
      final compressor = _HeicUnavailableCompressor([9]);

      final result = await ImageCompressionService(compressor: compressor)
          .compress(
            original,
            options: const ImageCompressionOptions(
              outputFormat: ImageOutputFormat.heic,
              fallbackFormat: ImageOutputFormat.jpeg,
            ),
          );

      expect(compressor.requestedFormats, [
        ImageOutputFormat.heic,
        ImageOutputFormat.jpeg,
      ]);
      expect(result.outputFormat, ImageOutputFormat.jpeg);
      expect(result.usedFallbackFormat, isTrue);
      expect(result.outputFile.path, endsWith('.jpg'));
      expect(await result.outputFile.exists(), isTrue);
      expect(await original.readAsBytes(), [1, 2, 3, 4]);
    });

    test('keeps the old behavior when no fallback is requested', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final compressor = _HeicUnavailableCompressor([9]);

      await expectLater(
        ImageCompressionService(compressor: compressor).compress(
          original,
          options: const ImageCompressionOptions(
            outputFormat: ImageOutputFormat.heic,
          ),
        ),
        throwsA(
          isA<ImageProcessingException>().having(
            (error) => error.code,
            'code',
            ImageProcessingErrorCode.compressionFailed,
          ),
        ),
      );
      expect(compressor.requestedFormats, [ImageOutputFormat.heic]);
    });

    test('is not used when the HEIC request succeeds', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final compressor = _FakeCompressor([1]);

      final result = await ImageCompressionService(compressor: compressor)
          .compress(
            original,
            options: const ImageCompressionOptions(
              outputFormat: ImageOutputFormat.heic,
              fallbackFormat: ImageOutputFormat.jpeg,
            ),
          );

      expect(result.outputFormat, ImageOutputFormat.heic);
      expect(result.usedFallbackFormat, isFalse);
    });

    test('does not retry failures of non-HEIC requests', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);

      await expectLater(
        ImageCompressionService(compressor: _ThrowingCompressor()).compress(
          original,
          options: const ImageCompressionOptions(
            outputFormat: ImageOutputFormat.webp,
            fallbackFormat: ImageOutputFormat.jpeg,
          ),
        ),
        throwsA(isA<ImageProcessingException>()),
      );
    });

    test('retries a source-format HEIC file that cannot be encoded', () async {
      final original = await _write(sandbox, 'photo.heic', [1, 2, 3]);
      final compressor = _HeicUnavailableCompressor([9]);

      final result = await ImageCompressionService(compressor: compressor)
          .compress(
            original,
            options: const ImageCompressionOptions(
              fallbackFormat: ImageOutputFormat.webp,
            ),
          );

      expect(result.outputFormat, ImageOutputFormat.webp);
      expect(result.usedFallbackFormat, isTrue);
    });

    test('rejects HEIC as the fallback format', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);

      await expectLater(
        ImageCompressionService(compressor: _FakeCompressor([1])).compress(
          original,
          options: const ImageCompressionOptions(
            fallbackFormat: ImageOutputFormat.heic,
          ),
        ),
        throwsA(
          isA<ImageProcessingException>().having(
            (error) => error.code,
            'code',
            ImageProcessingErrorCode.invalidInput,
          ),
        ),
      );
    });

    test('leaves no files behind when the fallback also fails', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final outputDirectory = Directory('${sandbox.path}/exports');

      await expectLater(
        ImageCompressionService(
          compressor: _PartialWriteThenNullCompressor(),
        ).compress(
          original,
          options: ImageCompressionOptions(
            outputFormat: ImageOutputFormat.heic,
            fallbackFormat: ImageOutputFormat.jpeg,
            outputDirectory: outputDirectory,
          ),
        ),
        throwsA(isA<ImageProcessingException>()),
      );

      expect(outputDirectory.listSync(), isEmpty);
      expect(await original.readAsBytes(), [1, 2, 3]);
    });
  });
}

Future<File> _write(Directory directory, String name, List<int> bytes) async {
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes);
  return file;
}

class _FakeCompressor implements ImageCompressor {
  _FakeCompressor(this.bytes);

  final List<int> bytes;
  int? quality;
  ImageOutputFormat? format;
  String? outputPath;

  @override
  Future<String?> compress({
    required String inputPath,
    required String outputPath,
    required int quality,
    required ImageOutputFormat format,
  }) async {
    this.quality = quality;
    this.format = format;
    this.outputPath = outputPath;
    await File(outputPath).writeAsBytes(bytes);
    return outputPath;
  }
}

class _ThrowingCompressor implements ImageCompressor {
  @override
  Future<String?> compress({
    required String inputPath,
    required String outputPath,
    required int quality,
    required ImageOutputFormat format,
  }) {
    throw StateError('native failure');
  }
}

/// Writes to the path it was given and then reports failure, the way a native
/// codec can when it aborts partway through encoding.
class _PartialWriteThenNullCompressor implements ImageCompressor {
  @override
  Future<String?> compress({
    required String inputPath,
    required String outputPath,
    required int quality,
    required ImageOutputFormat format,
  }) async {
    await File(outputPath).writeAsBytes(const [0xFF, 0xD8]);
    return null;
  }
}

/// Reports an empty file at a path other than the one it was given.
class _StrayPathCompressor implements ImageCompressor {
  @override
  Future<String?> compress({
    required String inputPath,
    required String outputPath,
    required int quality,
    required ImageOutputFormat format,
  }) async {
    final stray = File('${File(outputPath).parent.path}/stray-output.jpg');
    await stray.writeAsBytes(const []);
    return stray.path;
  }
}

/// Reports the source file as its own output.
class _SourcePathCompressor implements ImageCompressor {
  @override
  Future<String?> compress({
    required String inputPath,
    required String outputPath,
    required int quality,
    required ImageOutputFormat format,
  }) async => inputPath;
}

/// Fails every HEIC request the way a device without a HEIC encoder does, and
/// writes the requested bytes for any other format.
class _HeicUnavailableCompressor implements ImageCompressor {
  _HeicUnavailableCompressor(this.bytes);

  final List<int> bytes;
  final requestedFormats = <ImageOutputFormat>[];

  @override
  Future<String?> compress({
    required String inputPath,
    required String outputPath,
    required int quality,
    required ImageOutputFormat format,
  }) async {
    requestedFormats.add(format);
    if (format == ImageOutputFormat.heic) {
      throw StateError('HEIC encoding is not available');
    }
    await File(outputPath).writeAsBytes(bytes);
    return outputPath;
  }
}
