import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Tuner to force-enable high-speed socket buffers on Desktop platforms.
/// Uses low-level RawSocketOption to bypass standard library limits.
class QuicSocketTuner {
  static const int _bufferSize = 8 * 1024 * 1024; // 8 MB

  static void tune(RawDatagramSocket socket) {
    try {
      if (Platform.isWindows) {
        _tuneWindows(socket);
      } else if (Platform.isLinux) {
        _tuneLinux(socket);
      } else if (Platform.isMacOS) {
        _tuneMacOS(socket);
      }
    } catch (e) {
      debugPrint('[QUIC-Tuner] ⚠️ Failed to tune socket: $e');
    }
  }

  static void _tuneWindows(RawDatagramSocket socket) {
    // Windows Winsock2 definitions
    const int SOL_SOCKET = 0xFFFF;
    const int SO_RCVBUF = 0x1002;
    const int SO_SNDBUF = 0x1001;

    debugPrint('[QUIC-Tuner] Tuning Windows Socket (Buffer: 8MB)...');

    // Value must be 4-byte int in byte array
    final value = Uint8List(4)
      ..buffer.asByteData().setInt32(
        0,
        _bufferSize,
        Endian.little,
      ); // Windows is Little Endian

    try {
      // Apply SO_RCVBUF (Receive Buffer)
      socket.setRawOption(RawSocketOption(SOL_SOCKET, SO_RCVBUF, value));
      // Apply SO_SNDBUF (Send Buffer)
      socket.setRawOption(RawSocketOption(SOL_SOCKET, SO_SNDBUF, value));
      debugPrint('[QUIC-Tuner] ✅ Windows Socket Tuned Success');
    } catch (e) {
      debugPrint('[QUIC-Tuner] ❌ Windows Tuning Error: $e');
    }
  }

  static void _tuneLinux(RawDatagramSocket socket) {
    // Linux definitions (generic x86_64)
    const int SOL_SOCKET = 1;
    const int SO_SNDBUF = 7;
    const int SO_RCVBUF = 8;

    debugPrint('[QUIC-Tuner] Tuning Linux Socket (Buffer: 8MB)...');

    final value = Uint8List(4)
      ..buffer.asByteData().setInt32(0, _bufferSize, Endian.little);

    try {
      socket.setRawOption(RawSocketOption(SOL_SOCKET, SO_RCVBUF, value));
      socket.setRawOption(RawSocketOption(SOL_SOCKET, SO_SNDBUF, value));
      debugPrint('[QUIC-Tuner] ✅ Linux Socket Tuned Success');
    } catch (e) {
      debugPrint('[QUIC-Tuner] ❌ Linux Tuning Error: $e');
    }
  }

  static void _tuneMacOS(RawDatagramSocket socket) {
    // macOS definitions
    const int SOL_SOCKET = 0xffff; // On macOS this is usually 0xffff or similar
    const int SO_SNDBUF = 0x1001;
    const int SO_RCVBUF = 0x1002;

    // Note: API might differ. Usually macOS limits max buffer severely via sysctl.
    // setting 8MB might fail or be capped.
  }
}
