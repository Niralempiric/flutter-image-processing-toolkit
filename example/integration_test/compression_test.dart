import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_image_processing_toolkit/flutter_image_processing_toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Bundled fixture, declared in the example app's pubspec assets.
const _fixtureAsset = 'assets/sample_photo.jpg';

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

  testWidgets('compressMany reports a corrupt file and finishes the rest', (
    tester,
  ) async {
    final good = [
      for (var i = 0; i < 3; i++)
        await _copyFixtureInto(workspace, name: 'photo$i.jpg'),
    ];
    final corrupt = File('${workspace.path}/corrupt.jpg')
      ..writeAsBytesSync(List.filled(64, 7));
    final inputs = [good[0], corrupt, good[1], good[2]];
    final progress = <int>[];

    final results = await ImageCompressionService().compressMany(
      inputs,
      options: ImageCompressionOptions(
        quality: 60,
        outputDirectory: Directory('${workspace.path}/exports'),
      ),
      onProgress: (done, total, _) {
        expect(total, 4);
        progress.add(done);
      },
    );

    expect(results.map((r) => r.input.path), inputs.map((f) => f.path));
    expect(results.map((r) => r.isSuccess), [true, false, true, true]);
    expect(results[1].error!.code, ImageProcessingErrorCode.compressionFailed);
    expect(progress, [1, 2, 3, 4]);
    for (final r in results.where((r) => r.isSuccess)) {
      expect(await r.result!.outputFile.length(), greaterThan(0));
      expect(r.result!.outputFormat, ImageOutputFormat.jpeg);
    }
    // The failed file left nothing behind in the export directory.
    final exported = Directory('${workspace.path}/exports').listSync();
    expect(exported, hasLength(3));
  });
}

Future<File> _copyFixtureInto(
  Directory directory, {
  String name = 'sample_photo.jpg',
}) async {
  final data = await rootBundle.load(_fixtureAsset);
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  return file;
}
