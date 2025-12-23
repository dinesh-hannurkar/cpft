import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:fylooo/core/logging/app_logger.dart';
import 'dart:convert';
import 'dart:io';

import '../models/multicast_dto.dart';

/// Helper class to store socket and interface pair (like LocalSend)
class _SocketResult {
  final NetworkInterface? interface;
  final RawDatagramSocket socket;
  _SocketResult(this.interface, this.socket);
}

/// UDP Multicast discovery service (LocalSend approach)
/// Uses raw UDP sockets instead of mDNS
class MulticastService {
  static const String defaultMulticastGroup = '224.0.0.167';
  static const int defaultPort = 53317;

  final String multicastGroup;
  final int port;
  final String alias;
  final String fingerprint;
  final String deviceModel;

  final List<_SocketResult> _sockets =
      []; // Store multiple sockets like LocalSend
  final List<Function(String, String, int)> _discoveryListeners = [];
  bool _isListening = false;
  Timer? _announceTimer;
  bool _vpnDetected = false;

  MulticastService({
    required this.alias,
    required this.fingerprint,
    required this.deviceModel,
    this.multicastGroup = defaultMulticastGroup,
    this.port = defaultPort,
  }) {
    AppLogger.d(
      'MulticastService CONSTRUCTOR called! Alias: $alias',
      tag: 'Multicast',
    );
  }

  /// Add a listener for discovered devices
  void addDiscoveryListener(
    Function(String deviceName, String ipAddress, int port) listener,
  ) {
    _discoveryListeners.add(listener);
    AppLogger.d(
      'Added discovery listener, total: ${_discoveryListeners.length}',
      tag: 'Multicast',
    );
  }

  /// Remove a discovery listener
  void removeDiscoveryListener(Function(String, String, int) listener) {
    _discoveryListeners.remove(listener);
  }

  /// Check if VPN or cellular is detected (iOS specific issue)
  bool get isVpnDetected => _vpnDetected;

  /// Start listening for multicast announcements
  Future<void> startListening() async {
    if (_isListening) {
      AppLogger.w(
        'Already listening - EXITING EARLY (should not happen first launch)',
        tag: 'Multicast',
      );
      return;
    }
    try {
      // Platform-specific handling
      if (Platform.isAndroid) {
        AppLogger.d(
          'Android detected - special multicast configuration',
          tag: 'Multicast',
        );
      }
      if (Platform.isIOS) {
        AppLogger.d('iOS detected - raw multicast mode', tag: 'Multicast');
      }

      // CRITICAL: Get network interfaces
      var interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      AppLogger.d(
        'Raw interface list (${interfaces.length} found):',
        tag: 'Multicast',
      );
      for (var interface in interfaces) {
        AppLogger.v(
          '  ${interface.name}: ${interface.addresses.map((a) => a.address).join(', ')}',
          tag: 'Multicast',
        );
      }

      if (interfaces.isEmpty) {
        AppLogger.w(
          'No network interfaces found. Possible causes: no network, no permissions, airplane mode.',
          tag: 'Multicast',
        );

        // Try with loopback included as last resort
        AppLogger.d(
          'Trying with loopback interfaces included...',
          tag: 'Multicast',
        );
        final interfacesWithLoopback = await NetworkInterface.list(
          includeLoopback: true,
          type: InternetAddressType.IPv4,
        );

        if (interfacesWithLoopback.isNotEmpty) {
          AppLogger.d(
            'Found ${interfacesWithLoopback.length} interfaces with loopback:',
            tag: 'Multicast',
          );
          for (var interface in interfacesWithLoopback) {
            AppLogger.v(
              '  ${interface.name}: ${interface.addresses.map((a) => a.address).join(', ')}',
              tag: 'Multicast',
            );
          }
          // Use loopback interfaces as fallback
          interfaces = interfacesWithLoopback
              .where(
                (i) => i.addresses.any(
                  (addr) => !addr.isLoopback || i.name == 'lo0',
                ),
              )
              .toList();
        }

        if (interfaces.isEmpty) {
          throw Exception(
            'No network interfaces found. Check network and permissions.',
          );
        }
      }

      AppLogger.d('Available interfaces:', tag: 'Multicast');
      for (var interface in interfaces) {
        AppLogger.v(
          '  ${interface.name}: ${interface.addresses.map((a) => a.address).join(", ")}',
          tag: 'Multicast',
        );

        // Detect VPN/cellular interfaces (iOS specific) - More accurate detection
        if (Platform.isIOS) {
          // Only flag as VPN if we have strong indicators
          bool isVpnInterface = false;

          // Check for known VPN interface patterns
          if (interface.name.startsWith('ipsec') ||
              interface.name.startsWith('ppp') ||
              (interface.name.startsWith('utun') &&
                  interface.addresses.isNotEmpty)) {
            // Additional check: VPN interfaces usually have specific IP patterns
            // or are explicitly named VPN interfaces
            if (interface.name.contains('vpn') ||
                interface.name.contains('tunnel') ||
                interface.addresses.any(
                  (addr) =>
                      addr.address.startsWith(
                        '10.',
                      ) || // VPN often uses 10.x.x.x
                      addr.address.startsWith(
                        '172.',
                      ) || // VPN often uses 172.x.x.x
                      addr.address.startsWith(
                        '192.168.',
                      ), // VPN can use private ranges
                )) {
              isVpnInterface = true;
              AppLogger.w(
                'Detected VPN interface: ${interface.name}',
                tag: 'Multicast',
              );
            }
          }

          // Check for cellular IP ranges (100.x.x.x is common for carrier NAT)
          // But only if this interface is actually active/being used
          for (var addr in interface.addresses) {
            if (addr.address.startsWith('100.')) {
              // 100.x.x.x is used by carrier NAT, but only flag if it's the primary interface
              // or if we have multiple addresses suggesting cellular is active
              if (interface.addresses.length > 1 ||
                  interface.name.startsWith('pdp_ip')) {
                isVpnInterface = true;
                debugPrint(
                  '[MulticastService] Detected cellular/carrier interface: ${interface.name} (${addr.address})',
                );
              }
            }
          }

          if (isVpnInterface) {
            _vpnDetected = true;
          }
        }
      }

      debugPrint(
        '[MulticastService] Filtering interfaces for socket creation...',
      );

      if (_vpnDetected && Platform.isIOS) {
        debugPrint(
          '[MulticastService] ⚠️  WARNING: VPN or cellular network detected on iOS!',
        );
        debugPrint(
          '[MulticastService] iOS blocks multicast when VPN/cellular is active.',
        );
        debugPrint(
          '[MulticastService] Multicast send may fail (0 bytes sent).',
        );
        debugPrint(
          '[MulticastService] Please disconnect VPN or switch to WiFi only.',
        );
        debugPrint(
          '[MulticastService] If using WiFi, try forgetting/reconnecting to network.',
        );
      }

      // CRITICAL: Create MULTIPLE sockets like LocalSend does
      // LocalSend creates one socket per interface and joins multicast on each
      _sockets.clear(); // Clear any existing sockets

      for (final interface in interfaces) {
        // Less aggressive filtering - only skip obvious VPN/virtual interfaces
        bool skipInterface = false;
        if (interface.name.contains('tun') ||
            interface.name.contains('ppp') ||
            interface.name.startsWith('ipsec') ||
            (interface.name.startsWith('utun') &&
                interface.addresses.isEmpty)) {
          skipInterface = true;
          debugPrint(
            '[MulticastService] Skipping likely VPN interface: ${interface.name}',
          );
        }

        if (skipInterface) {
          continue;
        }

        try {
          debugPrint(
            '[MulticastService] Creating socket for interface: ${interface.name}',
          );
          final socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            port,
            reuseAddress: true,
          );

          // Try to join multicast group
          try {
            socket.joinMulticast(InternetAddress(multicastGroup), interface);
            debugPrint(
              '[MulticastService] ✅ Socket created and joined multicast for ${interface.name}',
            );
          } catch (multicastError) {
            debugPrint(
              '[MulticastService] ⚠️  Multicast join failed for ${interface.name}: $multicastError',
            );
            debugPrint(
              '[MulticastService] Socket created but multicast may not work',
            );
            // Still add the socket - it might work for sending at least
          }

          _sockets.add(_SocketResult(interface, socket));
        } catch (e) {
          debugPrint(
            '[MulticastService] ❌ Failed to create socket for ${interface.name}: $e',
          );
        }
      }

      if (_sockets.isEmpty) {
        debugPrint(
          '[MulticastService] ❌ No sockets created. Available interfaces:',
        );
        for (var interface in interfaces) {
          debugPrint(
            '[MulticastService]   - ${interface.name}: ${interface.addresses.map((a) => a.address).join(", ")}',
          );
        }
        debugPrint('[MulticastService] This usually means:');
        debugPrint('[MulticastService]   1. No WiFi connection');
        debugPrint('[MulticastService]   2. VPN is active (try disabling it)');
        debugPrint(
          '[MulticastService]   3. Cellular data only (multicast needs WiFi)',
        );
        debugPrint(
          '[MulticastService]   4. Firewall/antivirus blocking multicast',
        );

        // Try to create at least one socket with any available interface as fallback
        if (interfaces.isNotEmpty) {
          debugPrint(
            '[MulticastService] Attempting fallback: trying first available interface...',
          );
          try {
            final interface = interfaces.first;
            debugPrint(
              '[MulticastService] Creating fallback socket for interface: ${interface.name}',
            );
            final socket = await RawDatagramSocket.bind(
              InternetAddress.anyIPv4,
              port,
              reuseAddress: true,
            );
            socket.joinMulticast(InternetAddress(multicastGroup), interface);
            _sockets.add(_SocketResult(interface, socket));
            debugPrint(
              '[MulticastService] ✅ Fallback socket created for ${interface.name}',
            );
          } catch (e) {
            debugPrint(
              '[MulticastService] ❌ Fallback socket creation failed: $e',
            );
            // LAST RESORT: Try binding without specifying interface
            debugPrint(
              '[MulticastService] Attempting last resort: binding to any IPv4 address...',
            );
            try {
              final socket = await RawDatagramSocket.bind(
                InternetAddress.anyIPv4,
                port,
                reuseAddress: true,
              );
              socket.joinMulticast(InternetAddress(multicastGroup));
              _sockets.add(
                _SocketResult(null, socket),
              ); // null interface means any
              debugPrint(
                '[MulticastService] ✅ Last resort socket created (bound to any interface)',
              );
            } catch (lastResortError) {
              debugPrint(
                '[MulticastService] ❌ Last resort socket creation failed: $lastResortError',
              );
              throw Exception(
                'Unable to create any multicast sockets. Network may be unavailable or permissions missing.',
              );
            }
          }
        } else {
          // No interfaces found at all - try binding to any IPv4
          debugPrint(
            '[MulticastService] No interfaces found. Attempting direct IPv4 binding...',
          );
          try {
            final socket = await RawDatagramSocket.bind(
              InternetAddress.anyIPv4,
              port,
              reuseAddress: true,
            );
            socket.joinMulticast(InternetAddress(multicastGroup));
            _sockets.add(
              _SocketResult(null, socket),
            ); // null interface means any
            debugPrint(
              '[MulticastService] ✅ Socket created with direct IPv4 binding',
            );
          } catch (e) {
            debugPrint('[MulticastService] ❌ Direct IPv4 binding failed: $e');
            throw Exception(
              'No network interfaces found and direct binding failed. Please check your network connection.',
            );
          }
        }
      }

      debugPrint(
        '[MulticastService] Created ${_sockets.length} multicast sockets',
      );

      _isListening = true;

      // Listen for incoming packets on ALL sockets
      for (final socketResult in _sockets) {
        debugPrint(
          '[MulticastService] 👂 Setting up listener for ${socketResult.interface?.name ?? 'any interface'}',
        );
        socketResult.socket.listen(
          (event) {
            if (event == RawSocketEvent.read) {
              final datagram = socketResult.socket.receive();
              if (datagram != null) {
                debugPrint(
                  '[MulticastService] 📨 Received packet on ${socketResult.interface?.name ?? 'any interface'} from ${datagram.address.address}',
                );
                _handleIncomingPacket(datagram);
              }
            } else if (event == RawSocketEvent.write) {
              // Socket ready for writing
            } else if (event == RawSocketEvent.closed) {
              debugPrint(
                '[MulticastService] ⚠️  Socket closed for ${socketResult.interface?.name ?? 'any interface'}',
              );
            }
          },
          onError: (error) {
            debugPrint(
              '[MulticastService] ❌ Socket error on ${socketResult.interface?.name ?? 'any interface'}: $error',
            );
          },
        );
      }

      debugPrint('[MulticastService] Listening on $multicastGroup:$port');

      // Send initial announcement
      await sendAnnouncement();

      // Send periodic announcements
      _announceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        sendAnnouncement();
      });
    } catch (e) {
      debugPrint('[MulticastService] Error starting listener: $e');
      rethrow;
    }
  }

  /// Handle incoming multicast packet
  void _handleIncomingPacket(Datagram datagram) {
    try {
      debugPrint(
        '[MulticastService] 🔍 Processing packet from ${datagram.address.address}:${datagram.port}, size: ${datagram.data.length} bytes',
      );
      final message = utf8.decode(datagram.data);
      debugPrint('[MulticastService] 📄 Packet content: $message');
      final dto = MulticastDto.fromJsonString(message);

      // Ignore self-discovery
      if (dto.fingerprint == fingerprint) {
        debugPrint(
          '[MulticastService] ⏭️  Ignoring self-discovery (same fingerprint)',
        );
        return;
      }

      final deviceIp = datagram.address.address;

      // Notify listeners
      int notifiedCount = 0;
      for (var listener in _discoveryListeners) {
        try {
          listener(dto.alias, deviceIp, dto.port);
          notifiedCount++;
        } catch (e) {
          debugPrint('[MulticastService] ❌ Error notifying listener: $e');
        }
      }

      debugPrint(
        '[MulticastService] ✅ Successfully notified $notifiedCount listeners',
      );

      // If it's an announcement, we should respond via HTTP (handled by HTTP server)
      // The HTTP server will handle /register endpoint
    } catch (e) {
      debugPrint('[MulticastService] ❌ Error parsing packet: $e');
    }
  }

  /// Send multicast announcement
  Future<void> sendAnnouncement() async {
    if (Platform.isIOS) {
      debugPrint(
        '[MulticastService] Skipping multicast announcement on iOS (using Bonjour instead)',
      );
      return;
    }

    if (_sockets.isEmpty) {
      debugPrint('[MulticastService] No sockets initialized');
      return;
    }

    try {
      final dto = MulticastDto(
        alias: alias,
        fingerprint: fingerprint,
        port: port,
        deviceModel: deviceModel,
        announce: true,
      );

      final data = utf8.encode(dto.toJsonString());
      final address = InternetAddress(multicastGroup);

      int totalBytesSent = 0;
      int successfulSockets = 0;

      // Send on ALL sockets like LocalSend does
      for (final socketResult in _sockets) {
        try {
          final bytesSent = socketResult.socket.send(data, address, port);
          if (bytesSent > 0) {
            totalBytesSent += bytesSent;
            successfulSockets++;
            debugPrint(
              '[MulticastService] Sent announcement on ${socketResult.interface?.name ?? 'any interface'}: $bytesSent bytes',
            );
          } else {
            debugPrint(
              '[MulticastService] Warning: Failed to send on ${socketResult.interface?.name ?? 'any interface'} (0 bytes sent)',
            );
          }
        } catch (e) {
          debugPrint(
            '[MulticastService] Error sending on ${socketResult.interface?.name ?? 'any interface'}: $e',
          );
        }
      }

      if (successfulSockets > 0) {
        debugPrint(
          '[MulticastService] Sent announcement: $alias ($totalBytesSent bytes on $successfulSockets sockets)',
        );
      } else {
        debugPrint(
          '[MulticastService] Warning: Failed to send announcement on any socket (0 bytes sent)',
        );
        if (Platform.isIOS) {
          debugPrint('[MulticastService] iOS troubleshooting:');
          debugPrint(
            '  1. Check Settings → Privacy → Local Network → cpft (must be ON)',
          );
          debugPrint('  2. Ensure WiFi is connected (not cellular)');
          debugPrint('  3. Disable VPN if active');
          debugPrint('  4. Try deleting and reinstalling the app');
          debugPrint(
            '  5. iOS may require Local Network permission prompt on first launch',
          );
        }
      }
    } catch (e) {
      debugPrint('[MulticastService] Error sending announcement: $e');
      if (e is SocketException) {
        debugPrint('[MulticastService] SocketException details: ${e.message}');
        debugPrint('[MulticastService] OS Error: ${e.osError}');

        if (Platform.isAndroid) {
          debugPrint('[MulticastService] Android troubleshooting:');
          debugPrint('  1. Ensure WiFi is connected (not mobile data)');
          debugPrint('  2. Location permission must be granted');
          debugPrint('  3. WiFi multicast must be enabled');
          debugPrint('  4. Some Android devices/networks block multicast');
        }
      }
    }
  }

  /// Send response to a specific device
  Future<void> sendResponse(String targetIp, int targetPort) async {
    if (_sockets.isEmpty) {
      debugPrint('[MulticastService] No sockets initialized');
      return;
    }

    try {
      final dto = MulticastDto(
        alias: alias,
        fingerprint: fingerprint,
        port: port,
        deviceModel: deviceModel,
        announce: false,
      );

      final data = utf8.encode(dto.toJsonString());
      final address = InternetAddress(targetIp);

      // Send on first available socket (responses are unicast, not multicast)
      final socketResult = _sockets.first;
      socketResult.socket.send(data, address, targetPort);
      debugPrint(
        '[MulticastService] Sent response to $targetIp:$targetPort via ${socketResult.interface?.name ?? 'any interface'}',
      );
    } catch (e) {
      debugPrint('[MulticastService] Error sending response: $e');
    }
  }

  /// Stop listening
  void dispose() {
    debugPrint('[MulticastService] Disposing...');
    _announceTimer?.cancel();

    // Close all sockets
    for (final socketResult in _sockets) {
      try {
        socketResult.socket.close();
        debugPrint(
          '[MulticastService] Closed socket for ${socketResult.interface?.name ?? 'any interface'}',
        );
      } catch (e) {
        debugPrint(
          '[MulticastService] Error closing socket for ${socketResult.interface?.name ?? 'any interface'}: $e',
        );
      }
    }
    _sockets.clear();

    _isListening = false;
    _discoveryListeners.clear();
  }
}
