# Changelog

All notable changes to this project are documented in this file.

## Unreleased

- Added `ImageCompressionService.compressMany` and `BatchItemResult`: compress many files with bounded concurrency (`maxConcurrent`, default 2) and a progress callback. A file that fails is reported in its entry and does not stop the rest.

## 0.1.0

- Initial Android and iOS image compression API.
- Added a compression demonstration application and automated checks.
