import 'dart:io' show Platform;

// Centralized configuration for the entire application.
// Allows for easy tweaking and platform-specific overrides.
class Config {
  // Socket configuration for DPFTP
  static final socket = SocketConfig.getForPlatform();
}

// Defines the TCP socket settings for DPFTP.
// These values are critical for achieving high performance, especially on desktop LANs.
class SocketConfig {
  // The size of the socket's receive buffer (SO_RCVBUF).
  final int soRcvbuf;

  // The size of the socket's send buffer (SO_SNDBUF).
  final int soSndbuf;

  // Whether to disable Nagle's algorithm (TCP_NODELAY).
  final bool tcpNoDelay;

  // (Linux specific) Whether to use TCP_QUICKACK.
  final bool quickAck;

  SocketConfig({
    required this.soRcvbuf,
    required this.soSndbuf,
    required this.tcpNoDelay,
    this.quickAck = false,
  });

  // Provides the optimal configuration based on the current operating system.
  factory SocketConfig.getForPlatform() {
    if (Platform.isWindows) {
      return SocketConfig.windows();
    }
    if (Platform.isLinux) {
      return SocketConfig.linux();
    }
    if (Platform.isMacOS) {
      return SocketConfig.macOS();
    }
    // Default for Android, iOS, and others.
    return SocketConfig.defaultMobile();
  }

  // Configuration for Windows Desktop.
  // Large buffers are essential for overcoming the default small buffer sizes
  // that severely limit LAN transfer speeds.
  factory SocketConfig.windows() => SocketConfig(
    soRcvbuf: 4 * 1024 * 1024, // 4 MB (Reduced from 16MB to fix Bufferbloat)
    soSndbuf: 4 * 1024 * 1024, // 4 MB
    tcpNoDelay: true,
  );

  // Configuration for Linux Desktop.
  // Similar to Windows, larger buffers are beneficial.
  // TCP_QUICKACK can also help reduce latency for ACK packets.
  factory SocketConfig.linux() => SocketConfig(
    soRcvbuf: 4 * 1024 * 1024, // 4 MB
    soSndbuf: 4 * 1024 * 1024, // 4 MB
    tcpNoDelay: true,
    quickAck: true,
  );

  // macOS - Balanced configuration
  // Large enough for high latency, not excessive
  factory SocketConfig.macOS() => SocketConfig(
    soRcvbuf: 16 * 1024 * 1024, // 16 MB
    soSndbuf: 32 * 1024 * 1024, // 32 MB
    tcpNoDelay: true,
  );

  // Mobile - Balanced configuration
  // Large enough for high latency, not excessive
  factory SocketConfig.defaultMobile() => SocketConfig(
    soRcvbuf: 16 * 1024 * 1024, // 16 MB
    soSndbuf: 16 * 1024 * 1024, // 16 MB
    tcpNoDelay: true,
  );
}
