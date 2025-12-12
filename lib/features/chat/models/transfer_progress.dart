class TransferProgress {
  final String name;
  final int total; // 0 if unknown
  final String? mime;
  double progress; // bytes progressed (approx)
  DateTime lastUpdate;
  double lastBytes;
  double speed; // bytes per second
  bool isPending; // waiting for out-of-order chunks
  int pendingChunks; // number of buffered chunks waiting

  TransferProgress({required this.name, required this.total, this.mime})
      : progress = 0,
        lastUpdate = DateTime.now(),
        lastBytes = 0,
        speed = 0,
        isPending = false,
        pendingChunks = 0;

  void updateProgress(double newBytes) {
    final now = DateTime.now();
    final elapsed = now.difference(lastUpdate).inMilliseconds / 1000.0;
    if (elapsed > 0.1) {
      final delta = newBytes - lastBytes;
      speed = delta / elapsed;
      lastUpdate = now;
      lastBytes = newBytes;
    }
    progress = newBytes;
  }

  void pulsate() {
    if (total > 0) {
      progress = (progress + (total * 0.01)).clamp(0, total).toDouble();
    }
  }
}
