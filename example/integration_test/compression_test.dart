import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_image_processing_toolkit/flutter_image_processing_toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Bundled fixture, declared in the example app's pubspec assets.
const _fixtureAsset = 'assets/sample_photo.jpg';

/// 400x200 fixture used to check that resizing keeps the aspect ratio.
const _wideFixtureAsset = 'assets/sample_wide.jpg';

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
