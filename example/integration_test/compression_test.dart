import 'dart:io';
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
