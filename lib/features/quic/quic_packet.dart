import 'dart:typed_data';

/// Helper for parsing and building QUIC-like packets (RFC 9000)
///
/// Simplified for P2P file transfer:
/// - Supports Long Header (Initial) and Short Header (1-RTT)
/// - Connection IDs are implementation defined
/// - Packet Numbers are 32-bit for simplicity
class QuicPacket {
  static const int headerFormMask = 0x80; // 1 = Long, 0 = Short
  static const int fixedBitMask = 0x40; // Always 1

  static const int typeInitial = 0x00;
  static const int typeHandshake = 0x02;
  static const int typeRetry = 0x03;

  final bool isLongHeader;
  final int type; // For Long Header
  final Uint8List destConnId;
  final Uint8List srcConnId;
  final int packetNumber;
  final Uint8List payload;

  QuicPacket({
    required this.isLongHeader,
    this.type = 0,
    required this.destConnId,
    required this.srcConnId,
    required this.packetNumber,
    required this.payload,
  });

  /// Build a Short Header Packet (1-RTT)
  /// [0 | 1 | Spin | Res | KeyPhase | PN Len(2)]
  static Uint8List buildShortHeaderPacket({
    required Uint8List destConnId,
    required int packetNumber,
    required Uint8List payload,
  }) {
    final b = BytesBuilder();

    // First Byte: 0(Short) | 1(Fixed) | 0(Spin) | 0(Res) | 0(Key) | 10(PN Len=4 bytes) -> 0x42
    // We'll use 4-byte Packet Number for simplicity
    int firstByte =
        0x40 |
        0x02; // Fixed bit + PN Len=3 (4 bytes) - actually encoding is len-1?
    // RFC 9000: PN Len is encoded as (len - 1). So 3 means 4 bytes.
    b.addByte(firstByte);

    b.add(destConnId);

    // Packet Number (4 bytes)
    final pnBytes = ByteData(4)..setUint32(0, packetNumber, Endian.big);
    b.add(pnBytes.buffer.asUint8List());

    b.add(payload);

    return b.takeBytes();
  }

  /// Build a Long Header Packet (Initial)
  /// [1 | 1 | Type(2) | Res(4) | Version(4) | DCIL | SCIL | DCID | SCID | Token Len | Token | Len | PN | Payload]
  static Uint8List buildInitialPacket({
    required Uint8List destConnId,
    required Uint8List srcConnId,
    required int packetNumber,
    required Uint8List payload,
  }) {
    final b = BytesBuilder();

    // First Byte: 1(Long) | 1(Fixed) | Type(00=Initial) | Res(0000) -> 0xC0
    int firstByte = 0xC0;
    b.addByte(firstByte);

    // Version (4 bytes) - e.g. QUIC v1 = 0x00000001
    final version = ByteData(4)..setUint32(0, 1, Endian.big);
    b.add(version.buffer.asUint8List());

    // DCID Len (1 byte)
    b.addByte(destConnId.length);
    b.add(destConnId);

    // SCID Len (1 byte)
    b.addByte(srcConnId.length);
    b.add(srcConnId);

    // Token Length (VarInt) - 0 for now
    b.addByte(0);

    // Length (VarInt) - Remaining length (PN + Payload)
    // Simplified VarInt: Just use 2 bytes (up to 16k)
    // 0x40xx means 2 bytes length
    int remainingLen = 4 + payload.length; // PN(4) + Payload
    int lenCode = 0x4000 | remainingLen;
    b.addByte(lenCode >> 8);
    b.addByte(lenCode & 0xFF);

    // Packet Number (4 bytes)
    final pnBytes = ByteData(4)..setUint32(0, packetNumber, Endian.big);
    b.add(pnBytes.buffer.asUint8List());

    b.add(payload);

    return b.takeBytes();
  }
}
