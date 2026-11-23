# Changelog

All notable changes to this project are documented in this file.

## Unreleased

- CI now runs `flutter test --coverage`, fails below 80% line coverage, shows a per-file table in the job summary, and publishes a coverage badge to the README from `main`. Added `tool/coverage_summary.dart` and `tool/publish_badge.sh`.

## 0.1.0

- Initial Android and iOS image compression API.
- Added a compression demonstration application and automated checks.
