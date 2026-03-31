class ReceivedFile {
  final String filename;
  final String path;
  final int sizeBytes;
  final DateTime receivedAt;
  ReceivedFile({
    required this.filename,
    required this.path,
    required this.sizeBytes,
    required this.receivedAt,
  });

  String get humanSize {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = sizeBytes.toDouble();
    int i = 0;
    while (size >= 1000 && i < units.length - 1) {
      size /= 1000;
      i++;
    }
    return '${size.toStringAsFixed((i == 0) ? 0 : 1)} ${units[i]}';
  }
}
