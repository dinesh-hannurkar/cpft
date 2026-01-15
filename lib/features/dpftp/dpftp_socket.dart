import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dpftp_types.dart';

/// Wraps a raw TCP Socket to provide framed messaging.
/// Handles:
/// 1. Buffering incoming data
/// 2. Parsing [Magic][Len][Type][Payload] frames
/// 3. Sending framed messages
class DpftpSocket {
  final Socket _socket;
  final StreamController<DpftpMessage> _controller =
      StreamController.broadcast();

  // Buffering
  final Uint8List _buf = Uint8List(
    20 * 1024 * 1024,
  ); // 20MB buffer for 8MB chunks + overhead
  int _start = 0;
  int _end = 0;

  bool _disposed = false;

  Stream<DpftpMessage> get messages => _controller.stream;
  String get remoteAddress => _socket.remoteAddress.address;
  int get remotePort => _socket.remotePort;

  DpftpSocket(this._socket) {
    try {
      _socket.setOption(SocketOption.tcpNoDelay, true);

      // Tune buffers for Android/Linux to absorb scheduling jitter (especially for Redmi as GO)
      if (Platform.isAndroid || Platform.isLinux) {
        // SO_SNDBUF = 7, SO_RCVBUF = 8 (Standard Linux constants)
        // Set to 2MB to ensure kernel has plenty of data to send even if app thread is preempted
        const int bufferSize = 2 * 1024 * 1024;

        _socket.setRawOption(
          RawSocketOption.fromInt(
            RawSocketOption.levelSocket,
            7, // SO_SNDBUF
            bufferSize,
          ),
        );

        _socket.setRawOption(
          RawSocketOption.fromInt(
            RawSocketOption.levelSocket,
            8, // SO_RCVBUF
            bufferSize,
          ),
        );
      }
    } catch (e) {
      debugPrint('[DPFTP] Failed to set socket options: $e');
    }
    _socket.listen(
      _onData,
      onError: (e) {
        debugPrint('[DPFTP] Socket error: $e');
        dispose();
      },
      onDone: () {
        debugPrint('[DPFTP] Socket closed');
        dispose();
      },
    );
  }

  void _onData(Uint8List data) {
    if (_disposed) return;

    // Buffer management
    int remaining = _buf.length - _end;
    if (remaining < data.length) {
      _compact();
      remaining = _buf.length - _end;
      // If still not enough, expand buffer (rare for control messages)
      if (remaining < data.length) {
        debugPrint('[DPFTP] Buffer overflow, dropping connection');
        dispose();
        return;
      }
    }

    _buf.setRange(_end, _end + data.length, data);
    _end += data.length;

    _processBuffer();
  }

  void _compact() {
    if (_start == 0) return;
    final len = _end - _start;
    // Copy active data to start
    _buf.setRange(0, len, _buf, _start);
    _start = 0;
    _end = len;
  }

  void _processBuffer() {
    while (true) {
      final available = _end - _start;
      // Base Header: Magic(4) + Len(4) + Type(1) = 9 bytes
      if (available < 9) break;

      // Check Magic
      final magic = Dpftp.readInt32(_buf, _start);
      if (magic != Dpftp.magicByte) {
        debugPrint(
          '[DPFTP] ❌ Invalid Magic Byte: ${magic.toRadixString(16)}. Disconnecting.',
        );
        dispose();
        return;
      }

      final payloadLen = Dpftp.readInt32(_buf, _start + 4);
      // Safety check
      if (payloadLen < 0 || payloadLen > Dpftp.defaultChunkSize + 1024) {
        // 16MB + overhead
        debugPrint(
          '[DPFTP] ❌ Invalid Payload Length: $payloadLen. Disconnecting.',
        );
        dispose();
        return;
      }

      final frameSize = 9 + payloadLen;
      if (available < frameSize) break; // Wait for more data

      // Extract Frame
      final type = _buf[_start + 8];
      final payload = Uint8List.fromList(
        _buf.sublist(_start + 9, _start + 9 + payloadLen),
      );

      _controller.add(DpftpMessage(type, payload));

      _start += frameSize;

      // If buffer empty, reset pointers
      if (_start == _end) {
        _start = 0;
        _end = 0;
        break;
      }
    }

    // Auto-compact if we are near end
    if (_end > _buf.length * 0.8) {
      _compact();
    }
  }

  /// Sends a control message
  Future<void> sendMessage(int type, Uint8List payload) async {
    if (_disposed) return;
    final len = payload.length;
    final header = BytesBuilder(copy: false);
    header.add(Dpftp.int32(Dpftp.magicByte));
    header.add(Dpftp.int32(len));
    header.addByte(type);
    header.add(payload);

    try {
      _socket.add(header.takeBytes());
      if (type != Dpftp.typeAssignChunks) {
        // Flush important messages immediately? No, OS handles it.
        // await _socket.flush(); // Generally avoid await flush in Dart unless closing
      }
    } catch (e) {
      debugPrint('[DPFTP] Send error: $e');
      dispose();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _socket.destroy();
    _controller.close();
  }
}

class DpftpMessage {
  final int type;
  final Uint8List payload;
  DpftpMessage(this.type, this.payload);
}
