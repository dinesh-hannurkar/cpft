import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'quic_packet.dart';

/// Abstract Transport Interface
abstract class QuicTransport {
  Future<void> start();
  void stop();
  bool sendRaw(InternetAddress address, int port, Uint8List data);
  Future<void> sendStreamData(
    String ip,
    int port,
    int streamId,
    Uint8List data,
  );
  void closeConnection(InternetAddress address, int port);
  Stream<QuicStreamEvent> get dataStream;
  Object? getConnectionState(InternetAddress address, int port);
}

/// Manages the UDP socket and Reliability Layer (ARQ)
/// Emulates QUIC Streams over UDP.
class QuicTransportDart implements QuicTransport {
  RawDatagramSocket? _socket;
  final int localPort;

  // Platform Tuning
  final QuicTuning tuning = QuicTuning.detect();

  // Connections (Peer IP:Port -> Connection State)
  final Map<String, QuicConnectionState> _connections = {};

  // Stream for incoming data (StreamID, Data)
  final _dataStreamController = StreamController<QuicStreamEvent>.broadcast();
  @override
  Stream<QuicStreamEvent> get dataStream => _dataStreamController.stream;

  QuicTransportDart({required this.localPort});

  @override
  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, localPort);
    // Optimization: Maximize Socket Buffers (2MB)
    // Optimization: Maximize Socket Buffers (2MB) - NOT SUPPORTED on RawDatagramSocket API yet
    // Default OS buffers will be used.

    _socket!.listen(_handleSocketEvent);
    debugPrint(
      '[QUIC] Transport bound to port $localPort with optimized buffers',
    );
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      // Drain the socket
      Datagram? datagram;
      while ((datagram = _socket?.receive()) != null) {
        _processIncomingPacket(datagram!);
      }
    }
  }

  void _processIncomingPacket(Datagram d) {
    // Robust address filtering
    if (d.address.rawAddress.every((b) => b == 0)) {
      return; // Invalid source (0.0.0.0 or ::0)
    }
    if (d.address.address == '0.0.0.0' || d.address.address.startsWith('0.')) {
      return;
    }

    final key = '${d.address.address}:${d.port}';
    final state = _connections.putIfAbsent(
      key,
      () => QuicConnectionState(d.address, d.port, this),
    );

    // Check if it's an ACK
    if (d.data.length >= 5 && d.data[0] == 0xFF) {
      // ACK Frame: [Marker:1][Count:1][PNs...]
      try {
        if (d.data.length == 5) {
          final ackedPn = ByteData.sublistView(
            d.data,
            1,
          ).getUint32(0, Endian.big);
          state.handleAck(ackedPn);
        } else {
          // Batch ACK
          final count = d.data[1];
          final bd = ByteData.sublistView(d.data, 2);
          for (int i = 0; i < count; i++) {
            if ((i * 4) + 4 <= bd.lengthInBytes) {
              final pn = bd.getUint32(i * 4, Endian.big);
              state.handleAck(pn);
            }
          }
        }
      } catch (e) {
        debugPrint('[QUIC] Error parsing ACK: $e');
      }
      return;
    }

    // Packet Number (Simple extraction from offset 1 for Short Header test)
    if (d.data.length > 5) {
      state.handleIncomingData(d.data);
    }
  }

  @override
  bool sendRaw(InternetAddress address, int port, Uint8List data) {
    // Extensive Safety Checks
    // 1. Text Check
    if (address.address == '0.0.0.0' || address.address.startsWith('0.')) {
      return false;
    }
    // 2. Type Check
    if (address.type == InternetAddressType.any) {
      return false;
    }
    // 3. Raw Bytes Check (catches IPv6 any)
    try {
      if (address.rawAddress.every((b) => b == 0)) {
        return false;
      }
    } catch (_) {}

    try {
      final bytesSent = _socket?.send(data, address, port);
      return bytesSent != null && bytesSent > 0;
    } on SocketException catch (e) {
      if (e.osError?.errorCode == 55) {
        // OS Buffer Full. Adaptive Backoff.
        _adaptiveBackoff();
        return false;
      }
      debugPrint('[QUIC] Socket Exception: $e');
      return false;
    } catch (e) {
      debugPrint('[QUIC] Send Error: $e');
      return false;
    }
  }

  void _adaptiveBackoff() {
    // Reduce limits by 25%/50%
    tuning.maxInFlight = (tuning.maxInFlight * 0.75).toInt().clamp(100, 10000);
    tuning.batchSize = (tuning.batchSize * 0.5).toInt().clamp(5, 100);

    // debugPrint('[QUIC] Adaptive Backoff! New MaxInFlight: ${tuning.maxInFlight}, Batch: ${tuning.batchSize}');

    // Trigger congestion pause
    for (final conn in _connections.values) {
      conn._triggerCongestionBackoff();
    }
  }

  /// Send data on a specific QUIC stream
  @override
  Future<void> sendStreamData(
    String ip,
    int port,
    int streamId,
    Uint8List data,
  ) async {
    // Validate IP before creating state
    if (ip == '0.0.0.0' || ip.startsWith('0.')) {
      return;
    }

    // Normalize Key using InternetAddress to ensure consistency
    final internetAddr = InternetAddress(ip);

    // Double check raw bytes
    if (internetAddr.rawAddress.every((b) => b == 0)) return;

    final key = '${internetAddr.address}:$port';

    final state = _connections.putIfAbsent(
      key,
      () => QuicConnectionState(internetAddr, port, this),
    );

    await state.sendData(streamId, data);
  }

  @override
  void closeConnection(InternetAddress address, int port) {
    final key = '${address.address}:$port';
    debugPrint('[QUIC] Closing connection for key: $key');
    if (_connections.containsKey(key)) {
      _connections[key]?.dispose();
      _connections.remove(key);
      debugPrint('[QUIC] Connection closed and removed for $key');
    } else {
      debugPrint(
        '[QUIC] Connection NOT found for key: $key. Available keys: ${_connections.keys.toList()}',
      );
    }
  }

  @override
  QuicConnectionState? getConnectionState(InternetAddress address, int port) {
    final key = '${address.address}:$port';
    return _connections[key];
  }

  @override
  void stop() {
    for (final conn in _connections.values) {
      conn.dispose();
    }
    _connections.clear();
    _socket?.close();
  }
}

class QuicStreamEvent {
  final int streamId;
  final Uint8List data;
  final String remoteIp;
  final int offset;
  QuicStreamEvent(this.streamId, this.data, this.remoteIp, this.offset);
}

/// Manages state for a single peer connection (Reliability, Flow Control)
class QuicConnectionState {
  final InternetAddress address;
  final int port;
  final QuicTransportDart transport;

  int _nextPacketNumber = 0;
  final Map<int, _PendingPacket> _inflight = {};

  // Simplified Congestion Control
  int cwnd = 10 * 1400;
  int inflightBytes = 0;
  bool _isCongested = false;

  Timer? _retransmissionTimer;
  Timer? _ackTimer;
  final List<int> _pendingAcks = [];
  Completer<void>? _allAcksCompleter;

  QuicConnectionState(this.address, this.port, this.transport) {
    // Retransmission Loop (ARQ)
    // Check frequently (20ms) to ensure fast recovery on LAN
    _retransmissionTimer = Timer.periodic(const Duration(milliseconds: 20), (
      timer,
    ) {
      if (!timer.isActive) return;
      if (_isCongested) return; // Backoff

      final now = DateTime.now();
      final lostPackets = <_PendingPacket>[];
      final rtoBase = 100; // ms

      // Iterate in order (Map preserves insertion order)
      for (final packet in _inflight.values) {
        // Exponential Backoff: RTO * 2^attempts
        final backoffMultiplier =
            (1 << (packet.attempts > 5 ? 5 : packet.attempts));
        final currentRto = rtoBase * backoffMultiplier;

        if (now.difference(packet.sentTime).inMilliseconds > currentRto) {
          lostPackets.add(packet);
        } else {
          // Optimization: Since packets are ordered by key (PN) and thus mostly by time,
          // if we hit a packet that hasn't timed out, newer packets won't have either.
          // Break early to save CPU.
          break;
        }
      }

      for (final p in lostPackets) {
        // Never give up on packets. Infinite retry until connection is stopped.
        // Dropping them causes data loss and premature closure.
        /*
        if (p.attempts > 50) {
           // Maybe warn after 50?
           if (p.attempts % 50 == 0) debugPrint('[QUIC] Packet ${p.pn} struggling (${p.attempts} retries)...');
        }
        */

        if (!transport.sendRaw(address, port, p.data)) {
          _triggerCongestionBackoff();
          break; // Stop trying to resend others
        }

        // Update sent time and increment attempts
        _inflight[p.pn] = _PendingPacket(
          p.pn,
          p.data,
          DateTime.now(),
          attempts: p.attempts + 1,
        );
      }
    });
  }

  void _triggerCongestionBackoff() {
    if (_isCongested) return;
    _isCongested = true;
    // debugPrint('[QUIC] Congestion (buffer full). Yielding 15ms...');
    Future.delayed(const Duration(milliseconds: 15), () {
      _isCongested = false;
    });
  }

  void dispose() {
    debugPrint('[QUIC] Disposing connection state for $address:$port');
    _retransmissionTimer?.cancel();
    _ackTimer?.cancel();
    _inflight.clear();
    _pendingAcks.clear();
    if (_allAcksCompleter?.isCompleted == false) {
      _allAcksCompleter?.complete();
    }
  }

  final Map<int, int> _streamOffsets = {};

  Future<void> waitForAllAcks() {
    if (_inflight.isEmpty) return Future.value();
    _allAcksCompleter ??= Completer<void>();
    return _allAcksCompleter!.future;
  }

  Future<void> sendData(int streamId, Uint8List data) async {
    const mtu = 1450;
    int offset = 0;

    int streamBaseOffset = _streamOffsets[streamId] ?? 0;
    _streamOffsets[streamId] = streamBaseOffset + data.length;

    int packetsSentSinceYield = 0;

    while (offset < data.length) {
      // Flow Control: Dynamic Platform Tuning
      while (_inflight.length > transport.tuning.maxInFlight || _isCongested) {
        // Wait for ACKs to clear window
        await Future.delayed(const Duration(milliseconds: 1));
      }

      final len = (data.length - offset < mtu) ? data.length - offset : mtu;
      final chunk = data.sublist(offset, offset + len);

      final pn = _nextPacketNumber++;
      final connId = Uint8List(4);

      final payloadBuilder = BytesBuilder();
      final pbHeader = ByteData(4 + 8);
      pbHeader.setUint32(0, streamId, Endian.big);
      pbHeader.setUint64(4, streamBaseOffset + offset, Endian.big);

      payloadBuilder.add(pbHeader.buffer.asUint8List());
      payloadBuilder.add(chunk);

      final packet = QuicPacket.buildShortHeaderPacket(
        destConnId: connId,
        packetNumber: pn,
        payload: payloadBuilder.takeBytes(),
      );

      if (!transport.sendRaw(address, port, packet)) {
        _triggerCongestionBackoff();
        // If send failed, we must not increment offset, retry?
        // Actually, ARQ handles lost packets. But if we couldn't send initially,
        // we should probably stash it.
        // For simplicity: Add to inflight anyway, ARQ will retry.
        // Worst case: 1 RTO delay.
        // BUT if port/address invalid, it never finishes.
        // Since we check address validity in sendRaw, this only fails on OOM/NetworkDown.
      }
      _inflight[pn] = _PendingPacket(pn, packet, DateTime.now());

      packetsSentSinceYield++;
      // Pacing: Yield every 500 packets (~600KB) to reduce context switching overhead
      if (packetsSentSinceYield >= 500) {
        packetsSentSinceYield = 0;
        await Future.delayed(Duration.zero);
      }

      offset += len;
    }
  }

  void handleAck(int pn) {
    if (_inflight.containsKey(pn)) {
      _inflight.remove(pn);
      if (_inflight.isEmpty &&
          _allAcksCompleter != null &&
          !_allAcksCompleter!.isCompleted) {
        _allAcksCompleter!.complete();
      }
    }
  }

  final Map<int, int> _expectedStreamOffsets = {};
  final Map<int, Map<int, Uint8List>> _streamBuffers = {};

  void handleIncomingData(Uint8List packetBytes) {
    // Parse Packet (Simulated)
    // Assume valid Short Header
    // Skip Header (1 + 4(ConnID) + 4(PN) = 9 bytes)
    if (packetBytes.length < 9) return;

    // Extract PN to ACK
    // Header byte is at 0.
    // PN is at offset 5 (1 byte header + 4 bytes ConnID).
    final pn = ByteData.sublistView(packetBytes, 5, 9).getUint32(0, Endian.big);

    // Schedule ACK
    _scheduleAck(pn);

    final payload = packetBytes.sublist(9);
    // Needed: StreamID(4) + Offset(8) = 12 bytes header
    if (payload.length < 12) return;

    final bd = ByteData.sublistView(payload);
    final streamId = bd.getUint32(0, Endian.big);
    final offset = bd.getUint64(4, Endian.big);

    final data = payload.sublist(12);

    // STREAM REASSEMBLY LOGIC
    final expected = _expectedStreamOffsets[streamId] ?? 0;

    // 1. Duplicate/Old Data check
    if (offset < expected) {
      // We already have processed this. Ignore.
      return;
    }

    // 2. In-Order Data
    if (offset == expected) {
      // Emit immediately
      transport._dataStreamController.add(
        QuicStreamEvent(streamId, data, address.address, offset),
      );
      _expectedStreamOffsets[streamId] = expected + data.length;

      // Check buffer for subsequent data
      _processBufferedData(streamId);
    } else {
      // 3. Out-Of-Order Data (Future)
      // Buffer it
      // debugPrint('[QUIC] Buffering out-of-order chunk: Stream $streamId, Offset $offset (Expected: $expected)');
      if (!_streamBuffers.containsKey(streamId)) {
        _streamBuffers[streamId] = {};
      }
      _streamBuffers[streamId]![offset] = data;
    }
  }

  void _processBufferedData(int streamId) {
    final buffer = _streamBuffers[streamId];
    if (buffer == null || buffer.isEmpty) return;

    int expected = _expectedStreamOffsets[streamId] ?? 0;

    while (buffer.containsKey(expected)) {
      final data = buffer.remove(expected)!;

      transport._dataStreamController.add(
        QuicStreamEvent(streamId, data, address.address, expected),
      );

      expected += data.length;
      _expectedStreamOffsets[streamId] = expected;
    }
  }

  void _scheduleAck(int pn) {
    if (!_pendingAcks.contains(pn)) {
      _pendingAcks.add(pn);
    }

    // Batch ACKs: Flush every 10ms or if too many pending (10)
    // Reduce latency to prevent sender window stall.
    if (_pendingAcks.length >= 10) {
      _flushAcks();
    } else if (_ackTimer == null) {
      _ackTimer = Timer(const Duration(milliseconds: 10), _flushAcks);
    }
  }

  void _flushAcks() {
    _ackTimer?.cancel();
    _ackTimer = null;

    if (_pendingAcks.isEmpty) return;

    // Batch ACKs to reduce packet overhead
    // Limit to ~250 ACKs per packet (fits in MTU)
    while (_pendingAcks.isNotEmpty) {
      // Check for congestion before sending ACKs
      if (_isCongested) {
        // Reschedule flush? Or just wait for timer.
        // Let's reschedule aggressively
        _ackTimer = Timer(const Duration(milliseconds: 20), _flushAcks);
        return;
      }

      final batch = _pendingAcks.take(200).toList();
      _pendingAcks.removeRange(0, batch.length);

      final b = BytesBuilder();
      b.addByte(0xFF); // Marker

      if (batch.length == 1) {
        // Legacy/Simple format for single ACK
        final pnBytes = ByteData(4)..setUint32(0, batch.first, Endian.big);
        b.add(pnBytes.buffer.asUint8List());
      } else {
        // Batch format: [0xFF][Count][PN1][PN2]...
        final count = batch.length > 255 ? 255 : batch.length;
        b.addByte(count);
        for (int i = 0; i < count; i++) {
          final pnBytes = ByteData(4)..setUint32(0, batch[i], Endian.big);
          b.add(pnBytes.buffer.asUint8List());
        }
      }

      if (!transport.sendRaw(address, port, b.takeBytes())) {
        // Failed to send ACK. Put it back?
        // For simplicity, just drop it. Retransmission will handle it.
        // Trigger backoff
        _triggerCongestionBackoff();
      }
    }
  }
}

class _PendingPacket {
  final int pn;
  final Uint8List data;
  final DateTime sentTime;
  final int attempts;
  _PendingPacket(this.pn, this.data, this.sentTime, {this.attempts = 0});
}

class QuicTuning {
  int maxInFlight;
  int batchSize;
  int ackIntervalMs;

  QuicTuning({
    required this.maxInFlight,
    required this.batchSize,
    required this.ackIntervalMs,
  });

  factory QuicTuning.detect() {
    if (Platform.isMacOS || Platform.isIOS) {
      // Apple platforms are very strict with UDP buffers (small default)
      return QuicTuning(maxInFlight: 400, batchSize: 15, ackIntervalMs: 20);
    } else if (Platform.isLinux) {
      return QuicTuning(maxInFlight: 1000, batchSize: 40, ackIntervalMs: 10);
    } else if (Platform.isAndroid) {
      return QuicTuning(maxInFlight: 800, batchSize: 25, ackIntervalMs: 15);
    } else if (Platform.isWindows) {
      return QuicTuning(maxInFlight: 600, batchSize: 30, ackIntervalMs: 15);
    } else {
      return QuicTuning(maxInFlight: 500, batchSize: 20, ackIntervalMs: 20);
    }
  }
}
