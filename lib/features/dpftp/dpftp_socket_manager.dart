import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../core/socket_helper.dart';
import 'dpftp_socket.dart';
import 'dpftp_types.dart';

/// Manages the pool of sockets for a DPFTP transfer.
/// Strictly separates Control (Socket 0) from Data (Sockets 1..N).
class DpftpSocketManager {
  DpftpSocket? _controlSocket;
  final List<DpftpSocket> _dataSockets = [];

  bool _isDisposed = false;

  StreamController<DpftpMessage> _controlStream = StreamController.broadcast();
  StreamController<DpftpMessage> _dataStream = StreamController.broadcast();

  Stream<DpftpMessage> get controlMessages => _controlStream.stream;
  Stream<DpftpMessage> get dataMessages => _dataStream.stream;

  int get dataConnectionCount => _dataSockets.length;

  /// Register a socket. First socket becomes Control, subsequent are Data.
  void addSocket(Socket rawSocket) {
    // Apply platform-specific TCP tuning for performance.
    RawSocketTuner.tune(rawSocket);

    final socket = DpftpSocket(rawSocket);

    if (_controlSocket == null) {
      debugPrint(
        '[DPFTP] Control Connection Assigned: ${rawSocket.remoteAddress.address}',
      );
      _controlSocket = socket;
      socket.messages.listen(
        (msg) {
          if (!_isDisposed) _controlStream.add(msg);
        },
        onError: (e) => _handleError('Control socket error: $e'),
        onDone: () {
          _controlSocket = null; // Allow new control connection
          _handleError('Control socket closed');
        },
      );
    } else {
      debugPrint('[DPFTP] Data Connection ${_dataSockets.length + 1} Assigned');
      _dataSockets.add(socket);
      socket.messages.listen(
        (msg) {
          if (!_isDisposed) _dataStream.add(msg);
        },
        onError: (e) => debugPrint('[DPFTP] Data socket error: $e'),
        onDone: () {
          debugPrint('[DPFTP] Data socket closed');
          _dataSockets.remove(socket);
        },
      );
    }
  }

  /// Send control message
  Future<void> sendControl(int type, Uint8List payload) async {
    if (_controlSocket == null)
      throw Exception('Control socket not established');
    await _controlSocket!.sendMessage(type, payload);
  }

  /// Send data chunk on the least-busy or next variable socket
  /// For V1, we just Round-Robin or use simple index
  Future<void> sendDataChunk(
    int socketIndex,
    int chunkId,
    int length,
    Uint8List payload,
  ) async {
    if (_dataSockets.isEmpty) throw Exception('No data sockets available');

    // Pick socket (Modulus)
    final socket = _dataSockets[socketIndex % _dataSockets.length];

    // Create Frame: [ChunkId:4][Len:4][Payload]
    // Wait, DpftpSocket already adds [Magic][Len][Type] wrapper.
    // The "Payload" of the frame IS [ChunkId][Len][Data].
    // Note: Protocol Design 4.1 "Data Frame Format": |chunk_id|length|payload|

    // PERF: Single buffer allocation - no BytesBuilder copy
    final frameSize = 8 + payload.length; // 4 (chunkId) + 4 (length) + payload
    final frame = Uint8List(frameSize);
    final bd = ByteData.view(frame.buffer);
    bd.setUint32(0, chunkId, Endian.big);
    bd.setUint32(4, payload.length, Endian.big);
    frame.setRange(8, frameSize, payload);

    await socket.sendMessage(0x08, frame);
  }

  void dispose() {
    _isDisposed = true;
    _controlSocket?.dispose();
    for (var s in _dataSockets) {
      s.dispose();
    }
    _controlStream.close();
    _dataStream.close();
  }

  void _handleError(String msg) {
    if (_isDisposed) return;
    debugPrint('[DPFTP] SocketManager Error: $msg');
    // Notify upstream logic to abort transfer
    // _controlStream.addError(msg);
  }
}
