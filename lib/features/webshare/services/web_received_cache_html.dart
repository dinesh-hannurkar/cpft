import 'dart:typed_data';

class WebReceivedCache {
  static final Map<String, Uint8List> _store = <String, Uint8List>{};
  static final Map<String, List<Uint8List>> _partsStore = <String, List<Uint8List>>{};
  static final Map<String, int> _lengthStore = <String, int>{};
  static int _counter = 0;

  static String put(String filename, List<int> bytes) {
    final id = '${DateTime.now().millisecondsSinceEpoch}_${_counter++}';
    _store[id] = Uint8List.fromList(bytes);
    return id;
  }

  static Uint8List? get(String id) => _store[id];

  static String putParts(String filename, List<Uint8List> parts, int totalBytes) {
    final id = '${DateTime.now().millisecondsSinceEpoch}_${_counter++}';
    _partsStore[id] = parts;
    _lengthStore[id] = totalBytes;
    return id;
  }

  static List<Uint8List>? getParts(String id) => _partsStore[id];
  static int length(String id) => _lengthStore[id] ?? 0;

  static void remove(String id) {
    _store.remove(id);
    _partsStore.remove(id);
    _lengthStore.remove(id);
  }

  static bool has(String id) => _store.containsKey(id);
}
