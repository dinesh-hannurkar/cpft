class SharedFile {
  final String id;
  final String filename;
  final int sizeBytes;
  final DateTime sharedAt;
  SharedFile({
    required this.id,
    required this.filename,
    required this.sizeBytes,
    required this.sharedAt,
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
