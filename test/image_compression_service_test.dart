import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_processing_toolkit/flutter_image_processing_toolkit.dart';
import 'package:flutter_image_processing_toolkit/src/compression/exif_gps.dart';
import 'package:flutter_image_processing_toolkit/src/compression/image_compressor.dart';
import 'package:flutter_image_processing_toolkit/src/compression/resize.dart';
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

  group('fitWithin', () {
    const wide = (width: 4000, height: 2000);

    test('limits the width and keeps the aspect ratio', () {
      expect(fitWithin(wide, maxWidth: 1000), (width: 1000, height: 500));
    });

    test('limits the height and keeps the aspect ratio', () {
      expect(fitWithin(wide, maxHeight: 500), (width: 1000, height: 500));
    });

    test('uses the tighter of two limits', () {
      expect(fitWithin(wide, maxWidth: 2000, maxHeight: 250), (
        width: 500,
        height: 250,
      ));
    });

    test('never upscales an image that already fits', () {
      expect(fitWithin(wide, maxWidth: 8000, maxHeight: 8000), wide);
      expect(fitWithin(wide), wide);
    });

    test('keeps every side at least one pixel', () {
      expect(fitWithin((width: 10000, height: 10), maxWidth: 100), (
        width: 100,
        height: 1,
      ));
    });
  });

  group('resize', () {
    // A fake reader that "decodes" the source as 400x200 and the output as
    // whatever size the test says the codec produced.
    ImageSizeReader readerFor(File source, ImageSize? output) {
      return (file) async =>
          file.path == source.path ? (width: 400, height: 200) : output;
    }

    test(
      'passes the fitted size to the codec and reports the output size',
      () async {
        final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
        final compressor = _FakeCompressor([1]);

        final result =
            await ImageCompressionService(
              compressor: compressor,
              imageSizeReader: readerFor(original, (width: 100, height: 50)),
            ).compress(
              original,
              options: const ImageCompressionOptions(maxWidth: 100),
            );

        expect(compressor.targetWidth, 100);
        expect(compressor.targetHeight, 50);
        expect(result.outputWidth, 100);
        expect(result.outputHeight, 50);
      },
    );

    test('combines both limits', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final compressor = _FakeCompressor([1]);

      await ImageCompressionService(
        compressor: compressor,
        imageSizeReader: readerFor(original, null),
      ).compress(
        original,
        options: const ImageCompressionOptions(maxWidth: 300, maxHeight: 50),
      );

      expect(compressor.targetWidth, 100);
      expect(compressor.targetHeight, 50);
    });

    test('does not resize an image that already fits', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final compressor = _FakeCompressor([1]);

      await ImageCompressionService(
        compressor: compressor,
        imageSizeReader: readerFor(original, null),
      ).compress(
        original,
        options: const ImageCompressionOptions(maxWidth: 800, maxHeight: 800),
      );

      expect(compressor.targetWidth, 400);
      expect(compressor.targetHeight, 200);
    });

    test('asks the codec for no target when no limit is set', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final compressor = _FakeCompressor([1]);
      var sourceReads = 0;

      await ImageCompressionService(
        compressor: compressor,
        imageSizeReader: (file) async {
          if (file.path == original.path) sourceReads++;
          return null;
        },
      ).compress(original);

      expect(compressor.targetWidth, isNull);
      expect(compressor.targetHeight, isNull);
      expect(sourceReads, 0);
    });

    test('rejects non-positive limits', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final service = ImageCompressionService(compressor: _FakeCompressor([1]));

      for (final options in const [
        ImageCompressionOptions(maxWidth: 0),
        ImageCompressionOptions(maxHeight: -5),
      ]) {
        await expectLater(
          service.compress(original, options: options),
          throwsA(
            isA<ImageProcessingException>().having(
              (error) => error.code,
              'code',
              ImageProcessingErrorCode.invalidInput,
            ),
          ),
        );
      }
    });

    test('fails cleanly when the source size cannot be read', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final outputDirectory = Directory('${sandbox.path}/exports');

      await expectLater(
        ImageCompressionService(
          compressor: _FakeCompressor([1]),
          imageSizeReader: (_) async => null,
        ).compress(
          original,
          options: ImageCompressionOptions(
            maxWidth: 100,
            outputDirectory: outputDirectory,
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
      expect(outputDirectory.existsSync(), isFalse);
    });

    test('reports no output size when the output cannot be decoded', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);

      final result = await ImageCompressionService(
        compressor: _FakeCompressor([1]),
      ).compress(original);

      expect(result.outputWidth, isNull);
      expect(result.outputHeight, isNull);
    });
  });

  group('removeGpsFromJpeg', () {
    for (final littleEndian in [true, false]) {
      final order = littleEndian ? 'little-endian' : 'big-endian';

      test('removes the GPS block and keeps other tags ($order)', () {
        final jpeg = _jpegWithExif(littleEndian: littleEndian);
        expect(_ifd0Tags(jpeg), [0x010F, 0x0112, 0x8825, 0x9C9B]);
        expect(_containsCoordinates(jpeg, littleEndian), isTrue);

        final stripped = removeGpsFromJpeg(jpeg)!;

        expect(stripped.length, jpeg.length);
        expect(_ifd0Tags(stripped), [0x010F, 0x0112, 0x9C9B]);
        expect(_containsCoordinates(stripped, littleEndian), isFalse);
        expect(_makeOf(stripped), 'ToolkitTest');
        expect(_orientationOf(stripped), 1);
        expect(_trailingEntryValue(stripped), [0x41, 0x42]);
        // Only the EXIF segment changes; the rest of the file is identical.
        expect(stripped.sublist(0, 20), jpeg.sublist(0, 20));
        expect(
          stripped.sublist(stripped.length - 4),
          jpeg.sublist(jpeg.length - 4),
        );
      });

      test('removes a GPS pointer that is the last IFD0 entry ($order)', () {
        final jpeg = _jpegWithExif(
          littleEndian: littleEndian,
          trailingEntry: false,
        );
        final stripped = removeGpsFromJpeg(jpeg)!;

        expect(_ifd0Tags(stripped), [0x010F, 0x0112]);
        expect(_containsCoordinates(stripped, littleEndian), isFalse);
      });
    }

    test('returns null when there is no GPS data', () {
      expect(
        removeGpsFromJpeg(_jpegWithExif(littleEndian: true, gps: false)),
        isNull,
      );
    });

    test('returns null when there is no EXIF segment', () {
      final plain = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
      expect(removeGpsFromJpeg(plain), isNull);
    });

    test('does not modify the bytes it is given', () {
      final jpeg = _jpegWithExif(littleEndian: true);
      final before = Uint8List.fromList(jpeg);

      removeGpsFromJpeg(jpeg);

      expect(jpeg, before);
    });

    test('throws on malformed input instead of returning it unchanged', () {
      expect(
        () => removeGpsFromJpeg(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsFormatException,
      );
      final corrupt = _jpegWithExif(littleEndian: true);
      // Point the GPS IFD far outside the file.
      final gpsPointer = _ifd0EntryOffset(corrupt, 0x8825);
      corrupt.setRange(gpsPointer + 8, gpsPointer + 12, [0xFF, 0xFF, 0, 0]);
      expect(() => removeGpsFromJpeg(corrupt), throwsFormatException);
    });
  });

  group('keepExif and stripLocation', () {
    test('keepExif is off by default and passed to the codec', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final defaults = _FakeCompressor([1]);
      final keeping = _FakeCompressor([1]);

      await ImageCompressionService(compressor: defaults).compress(original);
      await ImageCompressionService(compressor: keeping).compress(
        original,
        options: const ImageCompressionOptions(keepExif: true),
      );

      expect(defaults.keepExif, isFalse);
      expect(keeping.keepExif, isTrue);
    });

    test('stripLocation removes GPS from the kept metadata', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final withGps = _jpegWithExif(littleEndian: true);

      final result =
          await ImageCompressionService(
            compressor: _FakeCompressor(withGps),
          ).compress(
            original,
            options: const ImageCompressionOptions(
              keepExif: true,
              stripLocation: true,
            ),
          );

      final output = Uint8List.fromList(await result.outputFile.readAsBytes());
      expect(_ifd0Tags(output), [0x010F, 0x0112, 0x9C9B]);
      expect(_containsCoordinates(output, true), isFalse);
      expect(result.compressedSizeBytes, withGps.length);
    });

    test('keepExif alone leaves the location in place', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final withGps = _jpegWithExif(littleEndian: true);

      final result =
          await ImageCompressionService(
            compressor: _FakeCompressor(withGps),
          ).compress(
            original,
            options: const ImageCompressionOptions(keepExif: true),
          );

      expect(await result.outputFile.readAsBytes(), withGps);
    });

    test('stripLocation without keepExif does not touch the output', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
      final compressor = _FakeCompressor([7, 8, 9]);

      final result = await ImageCompressionService(compressor: compressor)
          .compress(
            original,
            options: const ImageCompressionOptions(stripLocation: true),
          );

      expect(compressor.keepExif, isFalse);
      expect(await result.outputFile.readAsBytes(), [7, 8, 9]);
    });

    test('rejects stripLocation with keepExif for non-JPEG output', () async {
      final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);

      await expectLater(
        ImageCompressionService(compressor: _FakeCompressor([1])).compress(
          original,
          options: const ImageCompressionOptions(
            keepExif: true,
            stripLocation: true,
            outputFormat: ImageOutputFormat.webp,
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

    test(
      'fails closed and leaves no file when GPS cannot be removed',
      () async {
        final original = await _write(sandbox, 'photo.jpg', [1, 2, 3]);
        final outputDirectory = Directory('${sandbox.path}/exports');
        final corrupt = _jpegWithExif(littleEndian: true);
        final gpsPointer = _ifd0EntryOffset(corrupt, 0x8825);
        corrupt.setRange(gpsPointer + 8, gpsPointer + 12, [0xFF, 0xFF, 0, 0]);

        await expectLater(
          ImageCompressionService(
            compressor: _FakeCompressor(corrupt),
          ).compress(
            original,
            options: ImageCompressionOptions(
              keepExif: true,
              stripLocation: true,
              outputDirectory: outputDirectory,
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
        expect(outputDirectory.listSync(), isEmpty);
      },
    );
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
  int? targetWidth;
  int? targetHeight;
  bool? keepExif;

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
    this.quality = quality;
    this.format = format;
    this.outputPath = outputPath;
    this.targetWidth = targetWidth;
    this.targetHeight = targetHeight;
    this.keepExif = keepExif;
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
    int? targetWidth,
    int? targetHeight,
    bool keepExif = false,
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
    int? targetWidth,
    int? targetHeight,
    bool keepExif = false,
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
    int? targetWidth,
    int? targetHeight,
    bool keepExif = false,
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
    int? targetWidth,
    int? targetHeight,
    bool keepExif = false,
  }) async => inputPath;
}

// --- EXIF test helpers -----------------------------------------------------

/// Latitude 10 deg and longitude 20 deg as EXIF rationals, arbitrary values.
const _coordinates = [10, 1, 0, 1, 0, 1, 20, 1, 0, 1, 0, 1];

/// A minimal JPEG whose EXIF IFD0 holds Make (stored out of line),
/// Orientation, optionally a GPS pointer, and optionally a tag after it.
Uint8List _jpegWithExif({
  required bool littleEndian,
  bool gps = true,
  bool trailingEntry = true,
}) {
  final endian = littleEndian ? Endian.little : Endian.big;
  Uint8List u16(int v) =>
      (ByteData(2)..setUint16(0, v, endian)).buffer.asUint8List();
  Uint8List u32(int v) =>
      (ByteData(4)..setUint32(0, v, endian)).buffer.asUint8List();

  final make = [...'ToolkitTest'.codeUnits, 0];
  final entryCount = 2 + (gps ? 1 : 0) + (trailingEntry ? 1 : 0);
  final ifd0Size = 2 + entryCount * 12 + 4;
  final makeOffset = 8 + ifd0Size;
  final gpsIfdOffset = makeOffset + make.length;
  const gpsIfdSize = 2 + 4 * 12 + 4;
  final latOffset = gpsIfdOffset + gpsIfdSize;
  final lonOffset = latOffset + 24;

  final entries = <int>[
    ...u16(0x010F),
    ...u16(2),
    ...u32(make.length),
    ...u32(makeOffset),
    ...u16(0x0112),
    ...u16(3),
    ...u32(1),
    ...u16(1),
    0,
    0,
    if (gps) ...[...u16(0x8825), ...u16(4), ...u32(1), ...u32(gpsIfdOffset)],
    if (trailingEntry) ...[
      ...u16(0x9C9B),
      ...u16(1),
      ...u32(2),
      0x41,
      0x42,
      0,
      0,
    ],
  ];
  final tiff = <int>[
    littleEndian ? 0x49 : 0x4D,
    littleEndian ? 0x49 : 0x4D,
    ...u16(42),
    ...u32(8),
    ...u16(entryCount),
    ...entries,
    ...u32(0),
    ...make,
    if (gps) ...[
      ...u16(4),
      ...u16(1), ...u16(2), ...u32(2), 0x4E, 0, 0, 0, // N
      ...u16(2), ...u16(5), ...u32(3), ...u32(latOffset),
      ...u16(3), ...u16(2), ...u32(2), 0x45, 0, 0, 0, // E
      ...u16(4), ...u16(5), ...u32(3), ...u32(lonOffset),
      ...u32(0),
      for (final v in _coordinates) ...u32(v),
    ],
  ];
  final segment = [0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff];
  final length = segment.length + 2;
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0,
    0, // APP0
    0xFF, 0xE1, length >> 8, length & 0xFF, ...segment, // APP1 (EXIF)
    0xFF, 0xDA, 0x00, 0x02, 0xAB, 0xCD, // SOS and a little scan data
    0xFF, 0xD9, // EOI
  ]);
}

int _tiffStart(Uint8List jpeg) {
  for (var i = 2; i + 10 < jpeg.length; i++) {
    if (jpeg[i] == 0xFF && jpeg[i + 1] == 0xE1) return i + 10;
  }
  throw StateError('no EXIF segment');
}

Endian _endianOf(Uint8List jpeg) =>
    jpeg[_tiffStart(jpeg)] == 0x49 ? Endian.little : Endian.big;

int _ifd0(Uint8List jpeg) {
  final view = ByteData.sublistView(jpeg);
  final tiff = _tiffStart(jpeg);
  return tiff + view.getUint32(tiff + 4, _endianOf(jpeg));
}

List<int> _ifd0Tags(Uint8List jpeg) {
  final view = ByteData.sublistView(jpeg);
  final ifd0 = _ifd0(jpeg);
  final count = view.getUint16(ifd0, _endianOf(jpeg));
  return [
    for (var i = 0; i < count; i++)
      view.getUint16(ifd0 + 2 + i * 12, _endianOf(jpeg)),
  ];
}

int _ifd0EntryOffset(Uint8List jpeg, int tag) =>
    _ifd0(jpeg) + 2 + _ifd0Tags(jpeg).indexOf(tag) * 12;

String _makeOf(Uint8List jpeg) {
  final view = ByteData.sublistView(jpeg);
  final entry = _ifd0EntryOffset(jpeg, 0x010F);
  final length = view.getUint32(entry + 4, _endianOf(jpeg));
  final at = _tiffStart(jpeg) + view.getUint32(entry + 8, _endianOf(jpeg));
  return String.fromCharCodes(jpeg.sublist(at, at + length - 1));
}

int _orientationOf(Uint8List jpeg) {
  final entry = _ifd0EntryOffset(jpeg, 0x0112);
  return ByteData.sublistView(jpeg).getUint16(entry + 8, _endianOf(jpeg));
}

List<int> _trailingEntryValue(Uint8List jpeg) {
  final entry = _ifd0EntryOffset(jpeg, 0x9C9B);
  return jpeg.sublist(entry + 8, entry + 10);
}

bool _containsCoordinates(Uint8List jpeg, bool littleEndian) {
  final endian = littleEndian ? Endian.little : Endian.big;
  final pattern = <int>[
    for (final v in _coordinates)
      ...(ByteData(4)..setUint32(0, v, endian)).buffer.asUint8List(),
  ];
  for (var i = 0; i + pattern.length <= jpeg.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length && match; j++) {
      match = jpeg[i + j] == pattern[j];
    }
    if (match) return true;
  }
  return false;
}
