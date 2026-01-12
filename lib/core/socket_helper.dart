import 'dart:io';
import 'package:flutter/foundation.dart';
import 'config.dart';

// Provides a standardized way to apply performance-critical socket options.
class RawSocketTuner {
  // Applies the platform-optimal socket configuration.
  static void tune(Socket socket) {
    // Load the appropriate configuration for the current OS.
    final config = Config.socket;

    // debugPrint(
    //   'dpftp-new-file: 🔧 Tuning socket → Send: ${config.soSndbuf ~/ (1024 * 1024)}MB, Recv: ${config.soRcvbuf ~/ (1024 * 1024)}MB, NoDelay: ${config.tcpNoDelay}',
    // );

    // Platform-specific constants for raw socket options.
    // SOL_SOCKET, SO_RCVBUF, SO_SNDBUF have different integer values on Windows.
    final int solSocket = Platform.isWindows ? 0xFFFF : 1;
    final int soRcvbuf = Platform.isWindows ? 0x1002 : 8;
    final int soSndbuf = Platform.isWindows ? 0x1001 : 7;

    // Set SO_RCVBUF (Receive Buffer Size)
    // This is crucial for high-throughput receivers, allowing them to buffer
    // more data from the network before the application can read it.
    try {
      socket.setRawOption(
        RawSocketOption.fromInt(solSocket, soRcvbuf, config.soRcvbuf),
      );
      // debugPrint(
      //   'dpftp-new-file: ✅ SO_RCVBUF set to ${config.soRcvbuf ~/ (1024 * 1024)}MB',
      // );
    } catch (e) {
      debugPrint('[SocketTuner] Failed to set SO_RCVBUF: $e');
    }

    // Set SO_SNDBUF (Send Buffer Size)
    // Critical for high-throughput senders, allowing them to write more data
    // to the socket buffer without blocking.
    try {
      socket.setRawOption(
        RawSocketOption.fromInt(solSocket, soSndbuf, config.soSndbuf),
      );
      // debugPrint(
      //   'dpftp-new-file: ✅ SO_SNDBUF set to ${config.soSndbuf ~/ (1024 * 1024)}MB',
      // );
    } catch (e) {
      debugPrint('[SocketTuner] Failed to set SO_SNDBUF: $e');
    }

    // Set TCP_NODELAY (Disable Nagle's Algorithm)
    // This is important for reducing latency, especially for small, frequent
    // control messages. For bulk data transfer, its effect is less pronounced
    // but is generally considered a good practice for responsive applications.
    try {
      socket.setOption(SocketOption.tcpNoDelay, config.tcpNoDelay);
    } catch (e) {
      debugPrint('[SocketTuner] Failed to set TCP_NODELAY: $e');
    }

    // (Linux Only) Set TCP_QUICKACK
    // This can help in scenarios where ACKs need to be sent immediately,
    // reducing round-trip times for certain communication patterns.
    if (Platform.isLinux && config.quickAck) {
      try {
        // TCP_QUICKACK is not a standard Dart SocketOption.
        // We use raw values from the Linux headers:
        // level 6 = IPPROTO_TCP from netinet/in.h
        // option 12 = TCP_QUICKACK from linux/tcp.h
        socket.setRawOption(RawSocketOption.fromInt(6, 12, 1));
      } catch (e) {
        debugPrint('[SocketTuner] Failed to set TCP_QUICKACK: $e');
      }
    }
  }
}
