import 'dart:io';
import 'package:flutter/foundation.dart';
import 'config.dart';

// Provides a standardized way to apply performance-critical socket options.
class RawSocketTuner {
  // Applies the platform-optimal socket configuration.
  static void tune(Socket socket) {
    // Load the appropriate configuration for the current OS.
    final config = Config.socket;

    // Set SO_RCVBUF (Receive Buffer Size)
    // This is crucial for high-throughput receivers, allowing them to buffer
    // more data from the network before the application can read it.
    try {
      socket.setOption(
        RawSocketOption.fromInt(
          RawSocketOption.levelSocket,
          RawSocketOption.soRcvbuf,
        ),
        config.soRcvbuf,
      );
    } catch (e) {
      debugPrint('[SocketTuner] Failed to set SO_RCVBUF: $e');
    }

    // Set SO_SNDBUF (Send Buffer Size)
    // Critical for high-throughput senders, allowing them to write more data
    // to the socket buffer without blocking.
    try {
      socket.setOption(
        RawSocketOption.fromInt(
          RawSocketOption.levelSocket,
          RawSocketOption.soSndbuf,
        ),
        config.soSndbuf,
      );
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
        // TCP_QUICKACK is not a standard Dart SocketOption, so we use raw values.
        // IPPROTO_TCP = 6, TCP_QUICKACK = 12
        socket.setOption(
          RawSocketOption.fromInt(6, 12),
          1, // Enable
        );
      } catch (e) {
        debugPrint('[SocketTuner] Failed to set TCP_QUICKACK: $e');
      }
    }
  }
}
