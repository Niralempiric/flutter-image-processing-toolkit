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

  group('compressMany', () {
    Future<List<File>> photos(int count) => Future.wait([
      for (var i = 0; i < count; i++)
        _write(sandbox, 'photo$i.jpg', [1, 2, 3, i]),
    ]);

    test('returns one result per input, in input order', () async {
      final inputs = await photos(5);

      final results = await ImageCompressionService(
        compressor: _SlowCompressor([9]),
      ).compressMany(inputs);

      expect(results.map((r) => r.input.path), inputs.map((f) => f.path));
      expect(results.every((r) => r.isSuccess), isTrue);
      for (final r in results) {
        expect(await r.result!.outputFile.exists(), isTrue);
        expect(r.error, isNull);
      }
    });

    test('reports a failed file without stopping the others', () async {
      final inputs = await photos(3);
      final missing = File('${sandbox.path}/missing.jpg');
      final mixed = [inputs[0], missing, inputs[1], inputs[2]];

      final results = await ImageCompressionService(
        compressor: _SlowCompressor([9]),
      ).compressMany(mixed);

      expect(results.map((r) => r.isSuccess), [true, false, true, true]);
      expect(results[1].result, isNull);
      expect(results[1].error!.code, ImageProcessingErrorCode.invalidInput);
    });

    test('turns an unexpected codec error into a failed entry', () async {
      final inputs = await photos(2);

      final results = await ImageCompressionService(
        compressor: _ThrowingCompressor(),
      ).compressMany(inputs);

      expect(results.every((r) => !r.isSuccess), isTrue);
      expect(
        results.first.error!.code,
        ImageProcessingErrorCode.compressionFailed,
      );
    });

    test('never runs more than maxConcurrent files at once', () async {
      for (final limit in [1, 2, 3]) {
        final inputs = await photos(7);
        final compressor = _SlowCompressor([9]);

        await ImageCompressionService(
          compressor: compressor,
        ).compressMany(inputs, maxConcurrent: limit);

        expect(compressor.maxInFlight, limit, reason: 'limit $limit');
        expect(compressor.calls, 7);
      }
    });

    test('works when maxConcurrent exceeds the number of files', () async {
      final inputs = await photos(2);
      final compressor = _SlowCompressor([9]);

      final results = await ImageCompressionService(
        compressor: compressor,
      ).compressMany(inputs, maxConcurrent: 10);

      expect(results, hasLength(2));
      expect(compressor.maxInFlight, 2);
    });

    test('reports progress after each file with a running count', () async {
      final inputs = await photos(4);
      final seen = <(int, int, String)>[];

      await ImageCompressionService(
        compressor: _SlowCompressor([9]),
      ).compressMany(
        inputs,
        onProgress: (done, total, latest) =>
            seen.add((done, total, latest.input.path)),
      );

      expect(seen.map((e) => e.$1), [1, 2, 3, 4]);
      expect(seen.every((e) => e.$2 == 4), isTrue);
      expect(seen.map((e) => e.$3).toSet(), inputs.map((f) => f.path).toSet());
    });

    test('progress includes failed files', () async {
      final inputs = await photos(1);
      final failures = <bool>[];

      await ImageCompressionService(
        compressor: _SlowCompressor([9]),
      ).compressMany([
        File('${sandbox.path}/missing.jpg'),
        ...inputs,
      ], onProgress: (_, _, latest) => failures.add(!latest.isSuccess));

      expect(failures, unorderedEquals([false, true]));
    });

    test('an empty list returns an empty list and no progress', () async {
      var calls = 0;

      final results = await ImageCompressionService(
        compressor: _SlowCompressor([9]),
      ).compressMany(const [], onProgress: (_, _, _) => calls++);

      expect(results, isEmpty);
      expect(calls, 0);
    });

    test('rejects a bad call before processing anything', () async {
      final inputs = await photos(2);
      final compressor = _SlowCompressor([9]);
      final service = ImageCompressionService(compressor: compressor);

      await expectLater(
        service.compressMany(inputs, maxConcurrent: 0),
        throwsA(
          isA<ImageProcessingException>().having(
            (error) => error.code,
            'code',
            ImageProcessingErrorCode.invalidInput,
          ),
        ),
      );
      await expectLater(
        service.compressMany(
          inputs,
          options: const ImageCompressionOptions(quality: 101),
        ),
        throwsA(isA<ImageProcessingException>()),
      );
      expect(compressor.calls, 0);
    });

    test('a throwing progress callback does not stop the batch', () async {
      final inputs = await photos(4);
      final compressor = _SlowCompressor([9]);

      await expectLater(
        ImageCompressionService(compressor: compressor).compressMany(
          inputs,
          onProgress: (done, _, _) {
            if (done == 1) throw StateError('callback failed');
          },
        ),
        throwsStateError,
      );

      expect(compressor.calls, 4);
    });

    test('applies the same options to every file', () async {
      final inputs = await photos(3);
      final compressor = _SlowCompressor([9]);

      await ImageCompressionService(compressor: compressor).compressMany(
        inputs,
        options: const ImageCompressionOptions(
          quality: 33,
          outputFormat: ImageOutputFormat.webp,
        ),
      );

      expect(compressor.qualities, [33, 33, 33]);
      expect(compressor.formats.toSet(), {ImageOutputFormat.webp});
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

/// Takes a moment per file and records how many run at once.
class _SlowCompressor implements ImageCompressor {
  _SlowCompressor(this.bytes);

  final List<int> bytes;
  int calls = 0;
  int _inFlight = 0;
  int maxInFlight = 0;
  final qualities = <int>[];
  final formats = <ImageOutputFormat>[];

  @override
  Future<String?> compress({
    required String inputPath,
    required String outputPath,
    required int quality,
    required ImageOutputFormat format,
  }) async {
    calls++;
    qualities.add(quality);
    formats.add(format);
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await File(outputPath).writeAsBytes(bytes);
    _inFlight--;
    return outputPath;
  }
}
