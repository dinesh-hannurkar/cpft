import 'dart:typed_data';

class WebDownload {
  static void saveBytes(String filename, List<int> bytes, {String? contentType}) {
    // No-op on non-web platforms
  }

  static void saveParts(String filename, List<Uint8List> parts, {String? contentType}) {
    // No-op on non-web platforms
  }
}
