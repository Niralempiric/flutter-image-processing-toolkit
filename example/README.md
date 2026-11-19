# Compression example

This Android/iOS app demonstrates the public `flutter_image_processing_toolkit` API. It selects an image from the gallery, chooses a quality and optional output format, previews both files, and writes the new file to the app documents directory under `compressed-images`.

```sh
flutter pub get
flutter run
```

Formats whose native codec is missing on some devices are marked in the format
dropdown, and a failure for a request that named a format reports that format
instead of the generic compression error. HEIC output is the current case: it
was measured as unavailable on Android 14 (API 34). See the codec capability
matrix in the root README.

The app does not implement image processing itself; all compression is delegated to `ImageCompressionService` from the package root. Device capability is not probed: the package reports `compressionFailed` and the app decides how to present it.
