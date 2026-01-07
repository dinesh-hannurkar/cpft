class QuicProgress {
  final String transferId;
  final int bytesTransferred;
  final int totalBytes;
  final bool isOutgoing;
  final String? filePath;
  final bool isComplete;
  final String? error;
  final int durationMs;

  QuicProgress({
    required this.transferId,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.isOutgoing,
    this.filePath,
    this.isComplete = false,
    this.error,
    this.durationMs = 0,
  });
}
