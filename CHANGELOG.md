# Changelog

All notable changes to this project are documented in this file.

## Unreleased

- Added `ImageCompressionOptions.cropRect`: keep only a rectangle of the image, in pixels of the displayed image, before resizing and compression. An empty or out-of-bounds rectangle fails with `invalidInput`; it cannot be combined with `keepExif`. The example app gained a crop selector and shows the output size.
- Added `ImageCompressionOptions.maxWidth` and `maxHeight`: scale an image down to fit inside them, keeping the aspect ratio and never upscaling. Added `CompressionResult.outputWidth` and `outputHeight`. Without the new options, behavior is unchanged.
- Added a rotated (EXIF orientation 6) fixture and Android integration tests showing that output pixels are rotated into display orientation and that resize limits apply to the displayed size. No behavior change.
- Added `ImageCompressionOptions.keepExif` and `stripLocation`. `keepExif` copies the source's EXIF metadata into JPEG output (default false, so output has no metadata, as before). `stripLocation` removes only the GPS block from kept metadata and fails closed if it cannot.
- CI now runs `flutter test --coverage`, fails below 80% line coverage, shows a per-file table in the job summary, and publishes a coverage badge to the README from `main`. Added `tool/coverage_summary.dart` and `tool/publish_badge.sh`.

## 0.1.0

- Initial Android and iOS image compression API.
- Added a compression demonstration application and automated checks.
