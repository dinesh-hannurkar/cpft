import 'dart:typed_data';

class WebReceivedCache {
  static String put(String filename, List<int> bytes) => '';
  static Uint8List? get(String id) => null;
  static String putParts(String filename, List<Uint8List> parts, int totalBytes) => '';
  static List<Uint8List>? getParts(String id) => null;
  static int length(String id) => 0;
  static void remove(String id) {}
  static bool has(String id) => false;
}
