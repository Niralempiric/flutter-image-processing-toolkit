# Changelog

All notable changes to this project are documented in this file.

## Unreleased

- Added the opt-in `ImageCompressionOptions.fallbackFormat`: when a HEIC request fails, the operation is retried once in that format. `CompressionResult.usedFallbackFormat` reports it. The default behavior is unchanged.

## 0.1.0

- Initial Android and iOS image compression API.
- Added a compression demonstration application and automated checks.
