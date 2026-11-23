# Flutter Image Processing Toolkit

[![Flutter checks](https://github.com/Niralempiric/flutter-image-processing-toolkit/actions/workflows/flutter.yml/badge.svg)](https://github.com/Niralempiric/flutter-image-processing-toolkit/actions/workflows/flutter.yml) ![line coverage](https://raw.githubusercontent.com/Niralempiric/flutter-image-processing-toolkit/badges/coverage.svg)

A reusable Flutter package for non-destructive image compression on Android and iOS. This first release intentionally implements compression only; resizing, cropping, metadata, and camera workflows are out of scope.

## Features

- Asynchronous native image compression.
- Quality from 0 through 100, optional output format, and configurable output directory.
- JPEG, PNG, WebP, and HEIC extension validation.
- A new output file for every operation; the original file is never changed.
- Typed failures and a result containing sizes, output path, format, and saved percentage.
- An Android/iOS example app with gallery selection, previews, progress, errors, and an app-documents export location.

## Installation

```yaml
dependencies:
  flutter_image_processing_toolkit: ^0.1.0
```

Run `flutter pub get`, then import the package:

```dart
import 'package:flutter_image_processing_toolkit/flutter_image_processing_toolkit.dart';
```

Flutter 3.50 or later (Dart 3.12 or later) is required.

## Usage

```dart
final compressor = ImageCompressionService();
final result = await compressor.compress(
  File('/path/to/source.jpg'),
  options: ImageCompressionOptions(
    quality: 75,
    outputFormat: ImageOutputFormat.jpeg,
    outputDirectory: Directory('/path/to/exports'),
  ),
);

print(result.outputFile.path);
print('${result.compressionPercentage.toStringAsFixed(1)}% saved');
```

To cap the dimensions, set `maxWidth`, `maxHeight`, or both. The image is scaled down to fit inside them with its aspect ratio kept, and is never upscaled:

```dart
final result = await compressor.compress(
  File('/path/to/photo.jpg'), // for example 4000x3000
  options: const ImageCompressionOptions(maxWidth: 1280, maxHeight: 1280),
);

print('${result.outputWidth}x${result.outputHeight}'); // 1280x960
```

Omit `outputFormat` to use the supported source format. Omit `outputDirectory` to create a `compressed_images` directory beside the input. Catch `ImageProcessingException` and inspect its `code` (`invalidInput`, `unsupportedFormat`, or `compressionFailed`).

## API

`ImageCompressionService.compress(File, {ImageCompressionOptions options})` returns a `Future<CompressionResult>`.

`CompressionResult` provides `originalFile`, `outputFile`, `originalSizeBytes`, `compressedSizeBytes`, `outputFormat`, `outputWidth`, `outputHeight`, and `compressionPercentage`. `outputWidth` and `outputHeight` are null when the output's dimensions cannot be read, for example a HEIC file on an engine that cannot decode it. The percentage is clamped to 0–100: an output that is larger than its source reports `0% saved` rather than a misleading negative value.

## Platforms and limitations

EXIF orientation is applied to the output pixels, so a photo stored rotated comes out the same way up as it is displayed, and the orientation tag is not copied across (it would turn the image a second time). This is checked on Android (API 35) with a rotated fixture; iOS is not verified.

`maxWidth` and `maxHeight` apply to the image as displayed, after its EXIF orientation is applied, so a portrait photo stored rotated is limited like an upright one. Resizing needs the source dimensions, so a source Flutter cannot decode (some HEIC files) fails with `compressionFailed` when a limit is set. Output sizes were verified with the real Android codec on an emulator (API 35); iOS is not verified.

Without `maxWidth` or `maxHeight`, the underlying `flutter_image_compress` plugin still applies its own default (1920x1080), which by reading its Android source scales an image larger than that down. That behavior predates the resize options and is unchanged here.

Android and iOS are supported through `flutter_image_compress`. Codec availability, notably HEIC and WebP output, depends on the platform and device; requests unavailable on the current device fail with `compressionFailed`. Files are validated by extension before native decoding, so a corrupt file with a supported extension may still fail during native compression. A failed operation leaves nothing behind: a partial or empty file written by the codec is removed, and the source file is never deleted, even if the codec reports the source as its own output. An empty codec output is reported as `compressionFailed` rather than as a result claiming 100% saved. The package does not target web, macOS, Windows, or Linux in this release.

### Codec capability matrix

Every entry below was measured on a physical device; nothing here is inferred.
Rows are the input file format, columns the requested `outputFormat`.

| Source | *(none: keep source)* | `jpeg` | `png` | `webp` | `heic` |
|---|---|---|---|---|---|
| JPEG | 86.6% saved | 86.6% saved | output 3.8x larger, 0% saved | 93.2% saved | **unsupported, `compressionFailed`** |
| PNG | 7.6% saved | 96.8% saved | not measured | 98.4% saved | not measured |

Measured on an OPPO CPH2337, Android 14 (API 34), arm64-v8a, with
`flutter_image_compress` 2.4.0, compressing a 256x256 JPEG (22,650 bytes) and a
256x256 PNG (94,457 bytes) at quality 60. **iOS is not verified yet**, so no iOS
row is claimed here.

What this means when choosing options:

- **HEIC output is not available on every Android device.** On the device above
  the request fails with `compressionFailed` instead of falling back, so request
  `heic` only if your app can retry with `jpeg`.
- **PNG output will not shrink a photograph.** PNG is lossless, so `quality` is
  ignored and a photographic source grows. Use `jpeg` or `webp` for photographs
  and `png` only when you need lossless output.
- **`webp` produced the smallest output in every case measured**, roughly half
  the JPEG size at the same quality.
- **Quality 100 can exceed the source.** Re-encoding an already-compressed JPEG
  at quality 100 produced 33,736 bytes from a 22,650 byte source. Because the
  percentage is clamped, that reports `0.0% saved` rather than a negative value,
  so do not read 0% as "nothing happened": compare `compressedSizeBytes` with
  `originalSizeBytes` when the difference matters.
- **Invalid bytes behind a supported extension fail uniformly.** Garbage in a
  `.jpg`, `.png`, `.webp` or `.heic` file all raised `compressionFailed` and left
  nothing in the output directory.

Compression is asynchronous and uses the native codec, but applications should still present a loading state for large images. Generated output remains under caller control; remove exported files when they are no longer needed.

## Example screenshots

The example app walks through the gallery-to-export flow: pick an image, tune the quality, choose an output format, and compare the original with the compressed result.

![Gallery-to-export compression flow in the example app](doc/screenshots/demo.gif)

| Choose an image | Tune quality and format | Compare the result |
|---|---|---|
| <img src="doc/screenshots/01-home.png" width="240" alt="Example app home screen"> | <img src="doc/screenshots/02-selected.png" width="240" alt="Selected image with the quality slider at 60"> | <img src="doc/screenshots/03-result.png" width="240" alt="Original 22.1 KB, compressed 3.0 KB, 86.6% saved"> |

Captured from a release build on an Android 15 (API 35) emulator, compressing the bundled 256x256 `sample_photo.jpg` at quality 60 with the source format kept: 22.1 KB became 3.0 KB (86.6% saved). iOS screenshots are not included because iOS is not verified yet.

To run the example yourself on an Android or iOS device:

```sh
cd example
flutter run
```

## Testing

Host-side checks, no device required:

```sh
dart format --output=none --set-exit-if-changed lib test example/lib example/test example/integration_test
flutter analyze
flutter test
cd example && flutter test
```

CI runs the same checks with `flutter test --coverage`, fails if line coverage is below 80%, shows a per-file table in the job summary, and publishes the badge above from `main`. To see the table locally:

```sh
flutter test --coverage
dart tool/coverage_summary.dart
```

Line coverage covers the host-side tests only. `native_image_compressor.dart` calls the real codec, so it is exercised by the device integration tests, which CI does not run, and shows as low here.

### Integration tests

`example/integration_test/compression_test.dart` drives the real Android and iOS
codecs, which the unit tests replace with an injected adapter. It needs a
connected device, emulator, or simulator:

```sh
cd example
flutter devices
flutter test integration_test
```

The test copies the bundled `assets/sample_photo.jpg` fixture into the app
documents directory, compresses it into a subdirectory there, and deletes
everything it wrote on teardown. It never reads the gallery and never writes to
external storage, so it needs no runtime storage permission. CI does not run it:
GitHub-hosted runners have no attached device.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Please open an issue before broad changes, use a focused branch such as `feature/compression-format-picker` or `fix/heic-output-error`, and submit a tested pull request.

## License

This project is released under the BSD 3-Clause License. See [LICENSE](LICENSE).
