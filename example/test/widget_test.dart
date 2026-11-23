import 'package:material_ui/material_ui.dart';
import 'package:flutter_image_processing_toolkit/flutter_image_processing_toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  testWidgets('shows the compression entry point', (tester) async {
    await tester.pumpWidget(const CompressionDemoApp());

    expect(find.text('Image compression'), findsOneWidget);
    expect(find.text('Select image'), findsOneWidget);
    expect(find.text('Native, non-destructive compression'), findsOneWidget);
  });

  testWidgets('selects an output format', (tester) async {
    ImageOutputFormat? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OutputFormatSelector(
            value: selection,
            onChanged: (format) => selection = format,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<ImageOutputFormat?>));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('WebP').last);
    await tester.pump();

    expect(selection, ImageOutputFormat.webp);
  });

  testWidgets('flags formats that are not available on every device', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OutputFormatSelector(value: null, onChanged: (_) {}),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<ImageOutputFormat?>));
    await tester.pumpAndSettle();

    expect(find.text('HEIC (may be unavailable)'), findsWidgets);
    expect(find.text('JPEG'), findsWidgets);
    expect(find.text('HEIC'), findsNothing);
  });

  testWidgets('selects a crop preset', (tester) async {
    var selection = CropPreset.none;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CropPresetSelector(
            value: selection,
            onChanged: (preset) => selection = preset,
          ),
        ),
      ),
    );

    expect(find.text('No crop'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<CropPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Centre square').last);
    await tester.pump();

    expect(selection, CropPreset.centreSquare);
  });

  group('cropRectFor', () {
    const landscape = Size(400, 200);

    test('is null when there is no crop', () {
      expect(cropRectFor(CropPreset.none, landscape), isNull);
    });

    test('centres a square on the shorter side', () {
      expect(
        cropRectFor(CropPreset.centreSquare, landscape),
        const Rect.fromLTWH(100, 0, 200, 200),
      );
      expect(
        cropRectFor(CropPreset.centreSquare, const Size(200, 400)),
        const Rect.fromLTWH(0, 100, 200, 200),
      );
    });

    test('takes the middle half and the top-left quarter', () {
      expect(
        cropRectFor(CropPreset.centreHalf, landscape),
        const Rect.fromLTWH(100, 50, 200, 100),
      );
      expect(
        cropRectFor(CropPreset.topLeftQuarter, landscape),
        const Rect.fromLTWH(0, 0, 200, 100),
      );
    });

    test('every preset stays inside the image', () {
      for (final size in const [
        Size(400, 200),
        Size(200, 400),
        Size(333, 111),
      ]) {
        for (final preset in CropPreset.values) {
          final rect = cropRectFor(preset, size);
          if (rect == null) continue;
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
        }
      }
    });
  });

  group('describeCompressionFailure', () {
    const generic = ImageProcessingException(
      ImageProcessingErrorCode.compressionFailed,
      'Unable to compress the image.',
    );

    test('names the requested format when the codec failed', () {
      final message = describeCompressionFailure(
        generic,
        ImageOutputFormat.heic,
      );

      expect(message, contains('HEIC'));
      expect(message, contains('Keep input format'));
      expect(message, isNot(contains('Unable to compress the image.')));
    });

    test('passes the error through when no format was requested', () {
      expect(
        describeCompressionFailure(generic, null),
        'Unable to compress the image.',
      );
    });

    test('passes other error codes through unchanged', () {
      const invalid = ImageProcessingException(
        ImageProcessingErrorCode.invalidInput,
        'The input file is empty.',
      );

      expect(
        describeCompressionFailure(invalid, ImageOutputFormat.heic),
        'The input file is empty.',
      );
    });
  });
}
