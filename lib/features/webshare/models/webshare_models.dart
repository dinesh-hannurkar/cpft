/// Model for files received from web
class ReceivedFileInfo {
  final String filename;
  final String path;
  final DateTime receivedAt;

  ReceivedFileInfo({
    required this.filename,
    required this.path,
    required this.receivedAt,
  });
}

/// Model for files shared to web (mirrors the one in DiscoveryService)
class SharedFileInfo {
  final String id;
  final String filename;
  final String path;
  final int size;
  final DateTime sharedAt;

  SharedFileInfo({
    required this.id,
    required this.filename,
    required this.path,
    required this.size,
    required this.sharedAt,
  });
}
