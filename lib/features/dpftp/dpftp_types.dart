import 'dart:typed_data';

/// DPFTP Protocol Constants and Types
class Dpftp {
  // --- Framing Constants ---
  static const int magicByte = 0xACDC1234;

  // Standard chunk size (4 MB) - optimized for fast ACKs and flow control
  // Smaller chunks provide better granularity and faster turnaround
  static const int defaultChunkSize = 4 * 1024 * 1024;

  // Max control payload (1 MB) prevents memory exhaustion
  static const int maxControlPayloadInfo = 1024 * 1024;

  // --- Message Types ---
  static const int typeHello = 0x01; // Client -> Server
  static const int typeFileInfo = 0x02; // Server -> Client
  static const int typeRequestChunks = 0x03; // Client -> Server
  static const int typeAssignChunks = 0x04; // Server -> Client
  static const int typeChunkDone = 0x05; // Client -> Server
  static const int typeTransferComplete = 0x06; // Server -> Client
  static const int typeError = 0x07; // Bidirectional
  static const int typeData = 0x08; // Data Channels
  static const int typeChunkAck = 0x0A; // Sender <- Receiver (Flow Control)

  // --- Helpers ---

  /// Convert int to big-endian 4-byte array
  static Uint8List int32(int value) {
    final b = ByteData(4);
    b.setUint32(0, value, Endian.big);
    return b.buffer.asUint8List();
  }

  /// Read big-endian int from byte array
  static int readInt32(Uint8List data, int offset) {
    return ByteData.sublistView(
      data,
      offset,
      offset + 4,
    ).getUint32(0, Endian.big);
  }

  /// Convert int to big-endian 2-byte array (uint16)
  static Uint8List int16(int value) {
    final b = ByteData(2);
    b.setUint16(0, value, Endian.big);
    return b.buffer.asUint8List();
  }

  static int readInt16(Uint8List data, int offset) {
    return ByteData.sublistView(
      data,
      offset,
      offset + 2,
    ).getUint16(0, Endian.big);
  }
}

class DpftpFileInfo {
  final int fileSize;
  final int chunkSize;
  final int totalChunks;
  final ChunkBitmap bitmap;

  DpftpFileInfo({
    required this.fileSize,
    required this.chunkSize,
    required this.totalChunks,
    required this.bitmap,
  });

  // Serialize to bytes: [Size:8][ChunkSize:4][Total:4][BitmapLen:4][BitmapBytes...]
  Uint8List toBytes() {
    final b = BytesBuilder();
    final bd = ByteData(16);
    bd.setUint64(0, fileSize, Endian.big);
    bd.setUint32(8, chunkSize, Endian.big);
    bd.setUint32(12, totalChunks, Endian.big);
    b.add(bd.buffer.asUint8List());

    final bitmapBytes = bitmap.toBytes();
    b.add(Dpftp.int32(bitmapBytes.length));
    b.add(bitmapBytes);
    return b.takeBytes();
  }

  static DpftpFileInfo fromBytes(Uint8List data) {
    final bd = ByteData.sublistView(data, 0, 16);
    final fileSize = bd.getUint64(0, Endian.big);
    final chunkSize = bd.getUint32(8, Endian.big);
    final totalChunks = bd.getUint32(12, Endian.big);

    final bitmapLen = Dpftp.readInt32(data, 16);
    final bitmapBytes = data.sublist(20, 20 + bitmapLen);

    return DpftpFileInfo(
      fileSize: fileSize,
      chunkSize: chunkSize,
      totalChunks: totalChunks,
      bitmap: ChunkBitmap.fromBytes(bitmapBytes, totalChunks),
    );
  }
}

class ChunkBitmap {
  final Uint8List _bits;
  final int totalChunks;

  ChunkBitmap(this.totalChunks) : _bits = Uint8List((totalChunks + 7) ~/ 8);

  ChunkBitmap.fromBytes(Uint8List bytes, this.totalChunks)
    : _bits = Uint8List.fromList(bytes);

  bool hasChunk(int index) {
    if (index >= totalChunks) return false;
    final byteIndex = index ~/ 8;
    final bitIndex = index % 8;
    return (_bits[byteIndex] & (1 << bitIndex)) != 0;
  }

  void markReceived(int index) {
    if (index >= totalChunks) return;
    final byteIndex = index ~/ 8;
    final bitIndex = index % 8;
    _bits[byteIndex] |= (1 << bitIndex);
  }

  bool get isComplete {
    // Check all full bytes
    int fullBytes = totalChunks ~/ 8;
    for (int i = 0; i < fullBytes; i++) {
      if (_bits[i] != 0xFF) return false;
    }
    // Check remaining bits
    int remaining = totalChunks % 8;
    if (remaining > 0) {
      final mask = (1 << remaining) - 1;
      if ((_bits[fullBytes] & mask) != mask) return false;
    }
    return true;
  }

  /// Returns list of MISSING chunk indices (up to limit)
  List<int> getMissingChunks(int limit) {
    final missing = <int>[];
    for (int i = 0; i < totalChunks; i++) {
      if (!hasChunk(i)) {
        missing.add(i);
        if (missing.length >= limit) break;
      }
    }
    return missing;
  }

  Uint8List toBytes() => _bits;
}

/// Progress update for a DPFTP transfer
class DpftpProgress {
  final String transferId;
  final int bytesTransferred;
  final int totalBytes;
  final bool isOutgoing;
  final String? filePath;
  final bool isComplete;
  final String? error;
  final int? durationMs; // Actual transfer duration in milliseconds

  DpftpProgress({
    required this.transferId,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.isOutgoing,
    this.filePath,
    this.isComplete = false,
    this.error,
    this.durationMs,
  });

  double get fraction => totalBytes > 0 ? bytesTransferred / totalBytes : 0.0;
}
