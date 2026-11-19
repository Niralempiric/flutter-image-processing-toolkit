import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_image_processing_toolkit/flutter_image_processing_toolkit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const CompressionDemoApp());

class CompressionDemoApp extends StatelessWidget {
  const CompressionDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Image Compression Toolkit',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3659e3)),
      useMaterial3: true,
    ),
    home: const CompressionDemoPage(),
  );
}

class CompressionDemoPage extends StatefulWidget {
  const CompressionDemoPage({super.key, this.imagePicker, this.compressor});

  final ImagePicker? imagePicker;
  final ImageCompressionService? compressor;

  @override
  State<CompressionDemoPage> createState() => _CompressionDemoPageState();
}

class _CompressionDemoPageState extends State<CompressionDemoPage> {
  late final ImagePicker _imagePicker = widget.imagePicker ?? ImagePicker();
  late final ImageCompressionService _compressor =
      widget.compressor ?? ImageCompressionService();
  File? _original;
  CompressionResult? _result;
  int _quality = 80;
  ImageOutputFormat? _outputFormat;
  bool _isWorking = false;
  String? _error;

  Future<void> _selectImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() {
      _original = File(picked.path);
      _result = null;
      _error = null;
    });
  }

  Future<void> _compress() async {
    final source = _original;
    if (source == null) return;
    setState(() {
      _isWorking = true;
      _error = null;
    });
    try {
      final documents = await getApplicationDocumentsDirectory();
      final result = await _compressor.compress(
        source,
        options: ImageCompressionOptions(
          quality: _quality,
          outputFormat: _outputFormat,
          outputDirectory: Directory('${documents.path}/compressed-images'),
        ),
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on ImageProcessingException catch (error) {
      final message = describeCompressionFailure(error, _outputFormat);
      if (mounted) setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final original = _original;
    return Scaffold(
      appBar: AppBar(title: const Text('Image compression')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Native, non-destructive compression',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose an image, tune quality, then export a new file.',
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _isWorking ? null : _selectImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                original == null ? 'Select image' : 'Choose another image',
              ),
            ),
            if (original != null) ...[
              const SizedBox(height: 24),
              Text(
                'Quality: $_quality',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: _quality.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '$_quality',
                onChanged: _isWorking
                    ? null
                    : (value) => setState(() => _quality = value.round()),
              ),
              const SizedBox(height: 8),
              OutputFormatSelector(
                value: _outputFormat,
                onChanged: _isWorking
                    ? null
                    : (format) => setState(() => _outputFormat = format),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isWorking ? null : _compress,
                icon: _isWorking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.compress),
                label: Text(
                  _isWorking ? 'Compressing…' : 'Compress and export',
                ),
              ),
              const SizedBox(height: 24),
              _ImagePanel(title: 'Original', file: original),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 24),
              _ImagePanel(title: 'Compressed', file: result.outputFile),
              const SizedBox(height: 12),
              _ResultCard(result: result),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImagePanel extends StatelessWidget {
  const _ImagePanel({required this.title, required this.file});

  final String title;
  final File file;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const Center(child: Text('Preview unavailable')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_formatBytes(file.lengthSync())),
        ),
      ],
    ),
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final CompressionResult result;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${result.compressionPercentage.toStringAsFixed(1)}% saved',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text('Original: ${_formatBytes(result.originalSizeBytes)}'),
          Text('Compressed: ${_formatBytes(result.compressedSizeBytes)}'),
          Text('Format: ${result.outputFormat.name.toUpperCase()}'),
          const SizedBox(height: 8),
          SelectableText('Exported to: ${result.outputFile.path}'),
        ],
      ),
    ),
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class OutputFormatSelector extends StatelessWidget {
  const OutputFormatSelector({super.key, required this.value, this.onChanged});

  final ImageOutputFormat? value;
  final ValueChanged<ImageOutputFormat?>? onChanged;

  @override
  Widget build(BuildContext context) =>
      DropdownButtonFormField<ImageOutputFormat?>(
        key: ValueKey(value),
        initialValue: value,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Output format',
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('Keep input format')),
          ...ImageOutputFormat.values.map(
            (format) => DropdownMenuItem(
              value: format,
              child: Text(_menuLabel(format)),
            ),
          ),
        ],
        onChanged: onChanged,
      );
}

/// Formats whose native codec is not present on every device.
///
/// The device pass in issue #1 measured HEIC output failing on Android 14
/// (API 34). See the codec capability matrix in the README.
const _unevenlySupportedFormats = {ImageOutputFormat.heic};

/// Label for the dropdown, flagging formats that may not be available.
String _menuLabel(ImageOutputFormat format) =>
    _unevenlySupportedFormats.contains(format)
    ? '${_formatLabel(format)} (may be unavailable)'
    : _formatLabel(format);

/// Message shown when a compression request fails.
///
/// A `compressionFailed` error for a request that named [requestedFormat] is
/// reported with that format, because native codec availability varies by
/// device and OS version rather than being a property of the input. Every
/// other error code already carries an actionable message and is passed
/// through unchanged.
String describeCompressionFailure(
  ImageProcessingException error,
  ImageOutputFormat? requestedFormat,
) {
  if (error.code != ImageProcessingErrorCode.compressionFailed ||
      requestedFormat == null) {
    return error.message;
  }
  return '${_formatLabel(requestedFormat)} output failed on this device. '
      'Native codec support varies by device and OS version. Try '
      '"Keep input format", or another format.';
}

String _formatLabel(ImageOutputFormat format) => switch (format) {
  ImageOutputFormat.jpeg => 'JPEG',
  ImageOutputFormat.png => 'PNG',
  ImageOutputFormat.webp => 'WebP',
  ImageOutputFormat.heic => 'HEIC',
};
