import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_image_processing_toolkit/flutter_image_processing_toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Bundled fixture, declared in the example app's pubspec assets.
const _fixtureAsset = 'assets/sample_photo.jpg';

/// 400x200 fixture used to check that resizing keeps the aspect ratio.
const _wideFixtureAsset = 'assets/sample_wide.jpg';

/// 400x200 JPEG with EXIF Make, Orientation 1 and a GPS block (10 N, 20 E).
const _gpsFixtureAsset = 'assets/sample_gps.jpg';

/// 400x200 stored pixels with EXIF orientation 6, so it is displayed as
/// 200x400. Blue on the stored left edge, green on the right, which makes a
/// correct 90 degree turn show blue at the top and green at the bottom.
const _rotatedFixtureAsset = 'assets/sample_rotated.jpg';

/// Exercises the real Android and iOS codecs, which the host-side unit tests
/// replace with an injected adapter.
///
/// Needs a connected device, emulator, or simulator:
///
/// ```sh
/// cd example
/// flutter test integration_test
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory workspace;

  setUp(() async {
    final documents = await getApplicationDocumentsDirectory();
    workspace = await Directory(
      '${documents.path}/compression-integration',
    ).create(recursive: true);
  });

  tearDown(() async {
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  testWidgets('compresses a bundled JPEG with the native codec', (
    tester,
  ) async {
    final source = await _copyFixtureInto(workspace);
    final sourceBytes = await source.readAsBytes();
    final exports = Directory('${workspace.path}/exports');

    final result = await ImageCompressionService().compress(
      source,
      options: ImageCompressionOptions(quality: 60, outputDirectory: exports),
    );

    // A separate file is produced in the requested directory.
    expect(result.outputFile.path, isNot(source.path));
    expect(result.outputFile.path, startsWith(exports.path));
    expect(await result.outputFile.exists(), isTrue);

    // The source is left exactly as it was.
    expect(await source.exists(), isTrue);
    expect(await source.readAsBytes(), sourceBytes);

    // Reported sizes match the files on disk, and the saved percentage stays
    // inside the documented range whichever way the codec sizes its output.
    expect(result.originalSizeBytes, sourceBytes.length);
    expect(result.compressedSizeBytes, greaterThan(0));
    expect(await result.outputFile.length(), result.compressedSizeBytes);
    expect(result.compressionPercentage, inInclusiveRange(0, 100));
    expect(result.outputFormat, ImageOutputFormat.jpeg);
  });

  group('EXIF metadata', () {
    Future<Uint8List> compressGps({
      bool keepExif = false,
      bool stripLocation = false,
    }) async {
      final source = await _copyFixtureInto(workspace, asset: _gpsFixtureAsset);
      final result = await ImageCompressionService().compress(
        source,
        options: ImageCompressionOptions(
          quality: 70,
          keepExif: keepExif,
          stripLocation: stripLocation,
          outputDirectory: Directory('${workspace.path}/exports'),
        ),
      );
      return result.outputFile.readAsBytes();
    }

    testWidgets('the fixture carries Make, orientation and GPS', (
      tester,
    ) async {
      final data = await rootBundle.load(_gpsFixtureAsset);
      final source = data.buffer.asUint8List();

      expect(_ifd0Tags(source), containsAll([0x010F, 0x0112, 0x8825]));
      expect(_hasCoordinates(source), isTrue);
    });

    testWidgets('writes no metadata by default', (tester) async {
      final output = await compressGps();

      expect(_ifd0Tags(output), isEmpty);
      expect(_hasCoordinates(output), isFalse);
    });

    testWidgets('keepExif keeps the metadata, including location', (
      tester,
    ) async {
      final output = await compressGps(keepExif: true);

      expect(_ifd0Tags(output), containsAll([0x010F, 0x0112, 0x8825]));
      expect(_hasCoordinates(output), isTrue);
      expect(_orientationOf(output), 1);
    });

    testWidgets('stripLocation removes only the GPS block', (tester) async {
      final output = await compressGps(keepExif: true, stripLocation: true);

      final tags = _ifd0Tags(output);
      expect(tags, containsAll([0x010F, 0x0112]));
      expect(tags, isNot(contains(0x8825)));
      expect(_hasCoordinates(output), isFalse);
      expect(_orientationOf(output), 1);
      // The result is still a valid image of the same size.
      final decoded = await ui.instantiateImageCodec(output);
      final image = (await decoded.getNextFrame()).image;
      expect((image.width, image.height), (400, 200));
    });
  });

  group('EXIF orientation', () {
    testWidgets('bakes the rotation into the output pixels', (tester) async {
      final source = await _copyFixtureInto(
        workspace,
        asset: _rotatedFixtureAsset,
      );
      // Flutter reports the displayed size, which is what a viewer shows.
      final stored = await _decode(source);
      expect((stored.width, stored.height), (200, 400));

      final result = await ImageCompressionService().compress(
        source,
        options: ImageCompressionOptions(
          quality: 70,
          outputDirectory: Directory('${workspace.path}/exports'),
        ),
      );

      // Same displayed size and the same way up as the source: not stored
      // sideways, and not turned a second time.
      final output = await _decode(result.outputFile);
      expect((output.width, output.height), (200, 400));
      expect(result.outputWidth, 200);
      expect(result.outputHeight, 400);
      expect(output.top.blue, greaterThan(output.top.green));
      expect(output.bottom.green, greaterThan(output.bottom.blue));
    });

    testWidgets('resizes a rotated photo as it is displayed', (tester) async {
      final source = await _copyFixtureInto(
        workspace,
        asset: _rotatedFixtureAsset,
      );

      final byWidth = await ImageCompressionService().compress(
        source,
        options: ImageCompressionOptions(
          quality: 70,
          maxWidth: 100,
          outputDirectory: Directory('${workspace.path}/by-width'),
        ),
      );
      final byHeight = await ImageCompressionService().compress(
        source,
        options: ImageCompressionOptions(
          quality: 70,
          maxHeight: 100,
          outputDirectory: Directory('${workspace.path}/by-height'),
        ),
      );

      expect((byWidth.outputWidth, byWidth.outputHeight), (100, 200));
      expect((byHeight.outputWidth, byHeight.outputHeight), (50, 100));
      final output = await _decode(byWidth.outputFile);
      expect(output.top.blue, greaterThan(output.top.green));
      expect(output.bottom.green, greaterThan(output.bottom.blue));
    });
  });

  group('resize', () {
    Future<CompressionResult> resize(
      File source, {
      int? maxWidth,
      int? maxHeight,
    }) => ImageCompressionService().compress(
      source,
      options: ImageCompressionOptions(
        quality: 70,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        outputDirectory: Directory('${workspace.path}/exports'),
      ),
    );

    testWidgets('limits the width and keeps the aspect ratio', (tester) async {
      final source = await _copyFixtureInto(
        workspace,
        asset: _wideFixtureAsset,
      );

      final result = await resize(source, maxWidth: 100);

      expect(result.outputWidth, 100);
      expect(result.outputHeight, 50);
    });

    testWidgets('limits the height and keeps the aspect ratio', (tester) async {
      final source = await _copyFixtureInto(
        workspace,
        asset: _wideFixtureAsset,
      );

      final result = await resize(source, maxHeight: 50);

      expect(result.outputWidth, 100);
      expect(result.outputHeight, 50);
    });

    testWidgets('fits inside both limits', (tester) async {
      final source = await _copyFixtureInto(
        workspace,
        asset: _wideFixtureAsset,
      );

      final result = await resize(source, maxWidth: 80, maxHeight: 80);

      expect(result.outputWidth, 80);
      expect(result.outputHeight, 40);
    });

    testWidgets('never upscales a smaller image', (tester) async {
      final source = await _copyFixtureInto(
        workspace,
        asset: _wideFixtureAsset,
      );

      final result = await resize(source, maxWidth: 1000, maxHeight: 1000);

      expect(result.outputWidth, 400);
      expect(result.outputHeight, 200);
    });
  });
}

Future<File> _copyFixtureInto(
  Directory directory, {
  String asset = _fixtureAsset,
}) async {
  final data = await rootBundle.load(asset);
  final file = File('${directory.path}/${asset.split('/').last}');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  return file;
}

/// A decoded image's displayed size and the colors at its top and bottom
/// middle, as Flutter's decoder (which applies EXIF orientation) sees it.
typedef _Decoded = ({
  int width,
  int height,
  ({int blue, int green}) top,
  ({int blue, int green}) bottom,
});

Future<_Decoded> _decode(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData())!;
  ({int blue, int green}) colorAt(int y) {
    final offset = (y * image.width + image.width ~/ 2) * 4;
    return (blue: data.getUint8(offset + 2), green: data.getUint8(offset + 1));
  }

  return (
    width: image.width,
    height: image.height,
    top: colorAt(1),
    bottom: colorAt(image.height - 2),
  );
}

// --- EXIF helpers ----------------------------------------------------------

/// The IFD0 tag ids of the JPEG's EXIF segment, or empty when it has none.
List<int> _ifd0Tags(Uint8List jpeg) {
  final tiff = _tiffStart(jpeg);
  if (tiff == null) return const [];
  final endian = jpeg[tiff] == 0x49 ? Endian.little : Endian.big;
  final view = ByteData.sublistView(jpeg);
  final ifd0 = tiff + view.getUint32(tiff + 4, endian);
  final count = view.getUint16(ifd0, endian);
  return [
    for (var i = 0; i < count; i++) view.getUint16(ifd0 + 2 + i * 12, endian),
  ];
}

int _orientationOf(Uint8List jpeg) {
  final tiff = _tiffStart(jpeg)!;
  final endian = jpeg[tiff] == 0x49 ? Endian.little : Endian.big;
  final view = ByteData.sublistView(jpeg);
  final ifd0 = tiff + view.getUint32(tiff + 4, endian);
  final count = view.getUint16(ifd0, endian);
  for (var i = 0; i < count; i++) {
    final entry = ifd0 + 2 + i * 12;
    if (view.getUint16(entry, endian) == 0x0112) {
      return view.getUint16(entry + 8, endian);
    }
  }
  throw StateError('no orientation tag');
}

int? _tiffStart(Uint8List jpeg) {
  var offset = 2;
  while (offset + 4 <= jpeg.length && jpeg[offset] == 0xFF) {
    final marker = jpeg[offset + 1];
    if (marker == 0xDA) return null;
    final length = (jpeg[offset + 2] << 8) | jpeg[offset + 3];
    if (marker == 0xE1 &&
        jpeg[offset + 4] == 0x45 &&
        jpeg[offset + 5] == 0x78) {
      return offset + 10;
    }
    offset += 2 + length;
  }
  return null;
}

/// Whether the fixture's coordinates (10, 0, 0 and 20, 0, 0 as rationals)
/// appear anywhere in the file, in either byte order.
bool _hasCoordinates(Uint8List jpeg) {
  const values = [10, 1, 0, 1, 0, 1, 20, 1, 0, 1, 0, 1];
  for (final endian in [Endian.big, Endian.little]) {
    final pattern = <int>[
      for (final v in values)
        ...(ByteData(4)..setUint32(0, v, endian)).buffer.asUint8List(),
    ];
    for (var i = 0; i + pattern.length <= jpeg.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length && match; j++) {
        match = jpeg[i + j] == pattern[j];
      }
      if (match) return true;
    }
  }
  return false;
}
