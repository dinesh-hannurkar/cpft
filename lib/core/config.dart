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
    soRcvbuf: 8 * 1024 * 1024, // 8 MB
    soSndbuf: 8 * 1024 * 1024, // 8 MB
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

  // Configuration for macOS.
  // macOS has excellent TCP stack but needs large send buffers for high-throughput transfers.
  // Larger send buffer is critical for macOS→Android/Windows/Linux transfers.
  factory SocketConfig.macOS() => SocketConfig(
    soRcvbuf: 8 * 1024 * 1024, // 8 MB
    soSndbuf: 16 * 1024 * 1024, // 16 MB - Large buffer for sender role
    tcpNoDelay: true,
  );

  // Default configuration for mobile platforms (Android/iOS).
  // Modern Android devices (Pixel 7a+) have sufficient RAM for larger buffers.
  // Balanced send/receive buffers for both sending and receiving roles.
  factory SocketConfig.defaultMobile() => SocketConfig(
    soRcvbuf: 8 * 1024 * 1024, // 8 MB - Increased for receiving from desktop
    soSndbuf: 8 * 1024 * 1024, // 8 MB - Good for sending to desktop
    tcpNoDelay: true,
  );
}
