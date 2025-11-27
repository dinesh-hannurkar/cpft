class UploadProgress {
  final String filename;
  final int received;
  final int total;
  final DateTime startedAt;

  UploadProgress({
    required this.filename,
    required this.received,
    required this.total,
    required this.startedAt,
  });

  double? get progress => total > 0 ? received / total : null;
  bool get isIndeterminate => total <= 0;
  bool get isComplete => received >= total && total > 0;
}
