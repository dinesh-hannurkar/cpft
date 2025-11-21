// Utility helpers for file-related display formatting.
String extensionTrim(String ext) {
  ext = ext.trim();
  if (ext.length > 6) ext = ext.substring(0, 6);
  return ext.toUpperCase();
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
}

String readableMime(String mime) {
  final lower = mime.toLowerCase();
  if (lower.startsWith('image/')) return 'Image (${lower.split('/').last})';
  if (lower.startsWith('video/')) return 'Video (${lower.split('/').last})';
  if (lower.startsWith('audio/')) return 'Audio (${lower.split('/').last})';
  if (lower == 'application/pdf') return 'PDF document';
  if (lower.contains('zip') || lower.contains('compressed')) return 'Archive';
  if (lower.contains('text')) return 'Text';
  return mime;
}

String formatSpeed(double bytesPerSecond) {
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  double speed = bytesPerSecond;
  int unit = 0;
  while (speed >= 1024 && unit < units.length - 1) {
    speed /= 1024;
    unit++;
  }
  return '${speed.toStringAsFixed(speed < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
}

String formatTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
