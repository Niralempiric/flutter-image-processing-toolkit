# Changelog

All notable changes to this project are documented in this file.

## Unreleased

- Added `ImageCompressionOptions.maxWidth` and `maxHeight`: scale an image down to fit inside them, keeping the aspect ratio and never upscaling. Added `CompressionResult.outputWidth` and `outputHeight`. Without the new options, behavior is unchanged.
- Added a rotated (EXIF orientation 6) fixture and Android integration tests showing that output pixels are rotated into display orientation and that resize limits apply to the displayed size. No behavior change.

## 0.1.0

- Initial Android and iOS image compression API.
- Added a compression demonstration application and automated checks.
