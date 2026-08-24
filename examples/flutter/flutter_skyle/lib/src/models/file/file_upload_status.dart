/// Status codes for file transfer responses from the device.
enum FileTransferStatus {
  success(0),
  progress(1),
  failed(2);

  final int value;
  const FileTransferStatus(this.value);

  factory FileTransferStatus.fromValue(int value) {
    return FileTransferStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => FileTransferStatus.failed,
    );
  }
}

/// A file transfer status message received from the device.
class FileUploadStatus {
  final FileTransferStatus status;

  /// Progress percentage 0-100 (valid when status == progress).
  final int progress;

  /// Error message from device (valid when status == failed).
  final String? errorMessage;

  const FileUploadStatus({
    required this.status,
    this.progress = 0,
    this.errorMessage,
  });

  bool get isSuccess => status == FileTransferStatus.success;
  bool get isFailed => status == FileTransferStatus.failed;
  bool get isProgress => status == FileTransferStatus.progress;

  @override
  String toString() => switch (status) {
        FileTransferStatus.success => 'FileUploadStatus(success)',
        FileTransferStatus.progress => 'FileUploadStatus(progress: $progress%)',
        FileTransferStatus.failed => 'FileUploadStatus(failed: $errorMessage)',
      };
}
