import 'dart:io';

import '../exceptions/image_processing_exception.dart';
import 'compression_result.dart';

/// The outcome for one file in a batch: either a [result] or an [error].
class BatchItemResult {
  const BatchItemResult.success(this.input, CompressionResult this.result)
    : error = null;

  const BatchItemResult.failure(this.input, ImageProcessingException this.error)
    : result = null;

  /// The source file this outcome belongs to.
  final File input;

  /// The compression result, or null when the file failed.
  final CompressionResult? result;

  /// Why the file failed, or null when it succeeded.
  final ImageProcessingException? error;

  bool get isSuccess => result != null;
}
