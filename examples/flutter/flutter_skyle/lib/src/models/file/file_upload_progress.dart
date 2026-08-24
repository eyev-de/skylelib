import 'file_upload_status.dart';

/// Tracks overall file upload progress (both local send progress and device feedback).
class FileUploadProgress {
  final int bytesSent;
  final int totalBytes;
  final int chunksSent;
  final int totalChunks;

  /// Device-reported progress percentage (from StatusFile responses).
  final int? deviceProgress;

  /// Device-reported status (from StatusFile responses).
  final FileTransferStatus? deviceStatus;

  /// Error message from device (when deviceStatus == failed).
  final String? errorMessage;

  const FileUploadProgress({
    required this.bytesSent,
    required this.totalBytes,
    required this.chunksSent,
    required this.totalChunks,
    this.deviceProgress,
    this.deviceStatus,
    this.errorMessage,
  });

  /// Local send progress as a fraction 0.0 to 1.0.
  double get sendProgress => totalBytes > 0 ? bytesSent / totalBytes : 0.0;

  /// Whether all chunks have been sent (doesn't mean device has finished processing).
  bool get allChunksSent => chunksSent >= totalChunks;

  /// Whether the device reported success.
  bool get isComplete => deviceStatus == FileTransferStatus.success;

  /// Whether the device reported failure.
  bool get isFailed => deviceStatus == FileTransferStatus.failed;

  @override
  String toString() =>
      'FileUploadProgress(chunks: $chunksSent/$totalChunks, bytes: $bytesSent/$totalBytes, device: $deviceStatus ${deviceProgress ?? ""}%)';
}
