import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/multicast_dto.dart';

/// Helper class to store socket and interface pair (like LocalSend)
class _SocketResult {
  final NetworkInterface interface;
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

  final List<_SocketResult> _sockets = [];  // Store multiple sockets like LocalSend
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
    print('╔═══════════════════════════════════════════════════════════╗');
    print('║ MulticastService CONSTRUCTOR called!                      ║');
    print('║ Alias: $alias                                            ║');
    print('╚═══════════════════════════════════════════════════════════╝');
  }

  /// Add a listener for discovered devices
  void addDiscoveryListener(Function(String deviceName, String ipAddress, int port) listener) {
    _discoveryListeners.add(listener);
    print('[MulticastService] Added discovery listener, total: ${_discoveryListeners.length}');
  }

  /// Remove a discovery listener
  void removeDiscoveryListener(Function(String, String, int) listener) {
    _discoveryListeners.remove(listener);
  }

  /// Check if VPN or cellular is detected (iOS specific issue)
  bool get isVpnDetected => _vpnDetected;

  /// Start listening for multicast announcements
  Future<void> startListening() async {
    print('[MulticastService] ========================================');
    print('[MulticastService] 🚀🚀🚀 startListening() ENTRY 🚀🚀🚀');
    print('[MulticastService] _isListening state: $_isListening');
    print('[MulticastService] ========================================');
    
    if (_isListening) {
      print('[MulticastService] ❌ Already listening - EXITING EARLY');
      print('[MulticastService] This should NOT happen on first launch!');
      return;
    }

    print('[MulticastService] ✅ Proceeding with initialization...');
    print('[MulticastService] Platform: ${Platform.operatingSystem}');

    try {
      // Platform-specific handling
      if (Platform.isAndroid) {
        print('[MulticastService] Android detected - using special multicast configuration');
      }
      if (Platform.isIOS) {
        print('[MulticastService] iOS detected - raw multicast mode');
      }

      // CRITICAL: LocalSend creates MULTIPLE sockets, one per interface
      // This is the key difference - we need one socket per network interface
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      if (interfaces.isEmpty) {
        throw Exception('No network interfaces found');
      }

      print('[MulticastService] Available interfaces:');
      for (var interface in interfaces) {
        print('  ${interface.name}: ${interface.addresses.map((a) => a.address).join(", ")}');
        
        // Detect VPN/cellular interfaces (iOS specific) - More accurate detection
        if (Platform.isIOS) {
          // Only flag as VPN if we have strong indicators
          bool isVpnInterface = false;
          
          // Check for known VPN interface patterns
          if (interface.name.startsWith('ipsec') || 
              interface.name.startsWith('ppp') ||
              (interface.name.startsWith('utun') && interface.addresses.isNotEmpty)) {
            // Additional check: VPN interfaces usually have specific IP patterns
            // or are explicitly named VPN interfaces
            if (interface.name.contains('vpn') || 
                interface.name.contains('tunnel') ||
                interface.addresses.any((addr) => 
                  addr.address.startsWith('10.') ||  // VPN often uses 10.x.x.x
                  addr.address.startsWith('172.') || // VPN often uses 172.x.x.x  
                  addr.address.startsWith('192.168.') // VPN can use private ranges
                )) {
              isVpnInterface = true;
              print('[MulticastService] Detected VPN interface: ${interface.name}');
            }
          }
          
          // Check for cellular IP ranges (100.x.x.x is common for carrier NAT)
          // But only if this interface is actually active/being used
          for (var addr in interface.addresses) {
            if (addr.address.startsWith('100.')) {
              // 100.x.x.x is used by carrier NAT, but only flag if it's the primary interface
              // or if we have multiple addresses suggesting cellular is active
              if (interface.addresses.length > 1 || interface.name.startsWith('pdp_ip')) {
                isVpnInterface = true;
                print('[MulticastService] Detected cellular/carrier interface: ${interface.name} (${addr.address})');
              }
            }
          }
          
          if (isVpnInterface) {
            _vpnDetected = true;
          }
        }
      }

      print('[MulticastService] Filtering interfaces for socket creation...');
      
      if (_vpnDetected && Platform.isIOS) {
        print('[MulticastService] ⚠️  WARNING: VPN or cellular network detected on iOS!');
        print('[MulticastService] iOS blocks multicast when VPN/cellular is active.');
        print('[MulticastService] Multicast send may fail (0 bytes sent).');
        print('[MulticastService] Please disconnect VPN or switch to WiFi only.');
        print('[MulticastService] If using WiFi, try forgetting/reconnecting to network.');
      }

      // CRITICAL: Create MULTIPLE sockets like LocalSend does
      // LocalSend creates one socket per interface and joins multicast on each
      _sockets.clear();  // Clear any existing sockets
      
      for (final interface in interfaces) {
        // Skip VPN and virtual interfaces - comprehensive filtering
        bool skipInterface = false;
        if (interface.name.contains('tun') || 
            interface.name.contains('ppp') ||
            interface.name.contains('virtual') ||
            interface.name.startsWith('ipsec') ||
            interface.name.startsWith('utun') ||
            interface.name.startsWith('ppp') ||
            interface.name.contains('vpn')) {
          skipInterface = true;
          print('[MulticastService] Skipping VPN/virtual interface: ${interface.name}');
        }
        
        // On iOS, also skip cellular interfaces (pdp_ip0, etc.)
        if (Platform.isIOS && interface.name.startsWith('pdp_ip')) {
          skipInterface = true;
          print('[MulticastService] Skipping cellular interface: ${interface.name}');
        }
        
        if (skipInterface) {
          print('[MulticastService] Skipping interface: ${interface.name}');
          continue;
        }
        
        try {
          print('[MulticastService] Creating socket for interface: ${interface.name}');
          final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
          socket.joinMulticast(InternetAddress(multicastGroup), interface);
          _sockets.add(_SocketResult(interface, socket));
          print('[MulticastService] ✅ Socket created and joined multicast for ${interface.name}');
        } catch (e) {
          print('[MulticastService] ❌ Failed to create socket for ${interface.name}: $e');
        }
      }

      if (_sockets.isEmpty) {
        throw Exception('No suitable network interfaces found. Please ensure WiFi is connected.');
      }

      print('[MulticastService] Created ${_sockets.length} multicast sockets');

      _isListening = true;

      // Listen for incoming packets on ALL sockets
      for (final socketResult in _sockets) {
        print('[MulticastService] 👂 Setting up listener for ${socketResult.interface.name}');
        socketResult.socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = socketResult.socket.receive();
            if (datagram != null) {
              print('[MulticastService] 📨 Received packet on ${socketResult.interface.name} from ${datagram.address.address}');
              _handleIncomingPacket(datagram);
            }
          } else if (event == RawSocketEvent.write) {
            // Socket ready for writing
          } else if (event == RawSocketEvent.closed) {
            print('[MulticastService] ⚠️  Socket closed for ${socketResult.interface.name}');
          }
        }, onError: (error) {
          print('[MulticastService] ❌ Socket error on ${socketResult.interface.name}: $error');
        });
      }

      print('[MulticastService] Listening on $multicastGroup:$port');

      // Send initial announcement
      await sendAnnouncement();

      // Send periodic announcements
      _announceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        sendAnnouncement();
      });

    } catch (e) {
      print('[MulticastService] Error starting listener: $e');
      rethrow;
    }
  }

  /// Handle incoming multicast packet
  void _handleIncomingPacket(Datagram datagram) {
    try {
      print('[MulticastService] 🔍 Processing packet from ${datagram.address.address}:${datagram.port}, size: ${datagram.data.length} bytes');
      final message = utf8.decode(datagram.data);
      print('[MulticastService] 📄 Packet content: $message');
      final dto = MulticastDto.fromJsonString(message);

      // Ignore self-discovery
      if (dto.fingerprint == fingerprint) {
        print('[MulticastService] ⏭️  Ignoring self-discovery (same fingerprint)');
        return;
      }

      final deviceIp = datagram.address.address;
      
      print('[MulticastService] ✅ Received ${dto.announce ? "announcement" : "response"} from ${dto.alias} ($deviceIp:${dto.port})');
      print('[MulticastService] 📢 Notifying ${_discoveryListeners.length} listeners...');

      // Notify listeners
      int notifiedCount = 0;
      for (var listener in _discoveryListeners) {
        try {
          listener(dto.alias, deviceIp, dto.port);
          notifiedCount++;
        } catch (e) {
          print('[MulticastService] ❌ Error notifying listener: $e');
        }
      }
      
      print('[MulticastService] ✅ Successfully notified $notifiedCount listeners');

      // If it's an announcement, we should respond via HTTP (handled by HTTP server)
      // The HTTP server will handle /register endpoint

    } catch (e) {
      print('[MulticastService] ❌ Error parsing packet: $e');
    }
  }

  /// Send multicast announcement
  Future<void> sendAnnouncement() async {
    // Skip multicast announcements on iOS - Bonjour handles discovery
    if (Platform.isIOS) {
      print('[MulticastService] Skipping multicast announcement on iOS (using Bonjour instead)');
      return;
    }

    if (_sockets.isEmpty) {
      print('[MulticastService] No sockets initialized');
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
            print('[MulticastService] Sent announcement on ${socketResult.interface.name}: $bytesSent bytes');
          } else {
            print('[MulticastService] Warning: Failed to send on ${socketResult.interface.name} (0 bytes sent)');
          }
        } catch (e) {
          print('[MulticastService] Error sending on ${socketResult.interface.name}: $e');
        }
      }

      if (successfulSockets > 0) {
        print('[MulticastService] Sent announcement: $alias ($totalBytesSent bytes on $successfulSockets sockets)');
      } else {
        print('[MulticastService] Warning: Failed to send announcement on any socket (0 bytes sent)');
        if (Platform.isIOS) {
          print('[MulticastService] iOS troubleshooting:');
          print('  1. Check Settings → Privacy → Local Network → cpft (must be ON)');
          print('  2. Ensure WiFi is connected (not cellular)');
          print('  3. Disable VPN if active');
          print('  4. Try deleting and reinstalling the app');
          print('  5. iOS may require Local Network permission prompt on first launch');
        }
      }
    } catch (e) {
      print('[MulticastService] Error sending announcement: $e');
      if (e is SocketException) {
        print('[MulticastService] SocketException details: ${e.message}');
        print('[MulticastService] OS Error: ${e.osError}');
        
        if (Platform.isAndroid) {
          print('[MulticastService] Android troubleshooting:');
          print('  1. Ensure WiFi is connected (not mobile data)');
          print('  2. Location permission must be granted');
          print('  3. WiFi multicast must be enabled');
          print('  4. Some Android devices/networks block multicast');
        }
      }
    }
  }

  /// Send response to a specific device
  Future<void> sendResponse(String targetIp, int targetPort) async {
    if (_sockets.isEmpty) {
      print('[MulticastService] No sockets initialized');
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
      print('[MulticastService] Sent response to $targetIp:$targetPort via ${socketResult.interface.name}');
    } catch (e) {
      print('[MulticastService] Error sending response: $e');
    }
  }

  /// Stop listening
  void dispose() {
    print('[MulticastService] Disposing...');
    _announceTimer?.cancel();
    
    // Close all sockets
    for (final socketResult in _sockets) {
      try {
        socketResult.socket.close();
        print('[MulticastService] Closed socket for ${socketResult.interface.name}');
      } catch (e) {
        print('[MulticastService] Error closing socket for ${socketResult.interface.name}: $e');
      }
    }
    _sockets.clear();
    
    _isListening = false;
    _discoveryListeners.clear();
  }
}
