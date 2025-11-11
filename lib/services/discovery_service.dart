import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'multicast_service.dart';
import 'http_server_service.dart';
import 'http_discovery_client.dart';
import 'multicast_platform_helper.dart';
import 'bonjour_service.dart';
import 'incoming_connection_service.dart';
import 'connection_manager.dart';

/// Unified discovery service combining UDP multicast and HTTP
/// This matches LocalSend's architecture
class DiscoveryService {
  late final MulticastService _multicastService;
  late final HttpServerService _httpServer;
  late final HttpDiscoveryClient _httpClient;
  late final IncomingConnectionService _incomingConnectionService;
  late final ConnectionManager _connectionManager;
  BonjourService? _bonjourService;  // For iOS real devices

  final String alias;
  final int port;
  late final String fingerprint;
  final String deviceModel;

  final List<Function(String, String, int)> _discoveryListeners = [];
  final Map<String, DeviceInfo> _discoveredDevices = {};
  // Incoming connection request listeners (before acceptance)
  final List<Function(String deviceName, String ipAddress, int port, Future<void> Function() accept, Future<void> Function() decline)> _incomingRequestListeners = [];
  
  bool _isInitialized = false;
  
  // P2P connection port (different from discovery port)
  static const int p2pPort = 53318;

  DiscoveryService({
    required this.alias,
    required this.deviceModel,
    this.port = 53317,
  }) {
    // Generate fingerprint (simple hash of device info)
    fingerprint = _generateFingerprint();
  }

  String _generateFingerprint() {
    final data = '$alias-${Platform.localHostname}-${DateTime.now().millisecondsSinceEpoch}';
    return md5.convert(utf8.encode(data)).toString().substring(0, 16);
  }

  /// Add listener for device discoveries
  void addDiscoveryListener(Function(String deviceName, String ipAddress, int port) listener) {
    _discoveryListeners.add(listener);
  }

  /// Remove discovery listener
  void removeDiscoveryListener(Function(String, String, int) listener) {
    _discoveryListeners.remove(listener);
  }

  // Add/Remove incoming connection request listeners
  void addIncomingRequestListener(
    Function(String deviceName, String ipAddress, int port, Future<void> Function() accept, Future<void> Function() decline) listener,
  ) {
    _incomingRequestListeners.add(listener);
  }

  void removeIncomingRequestListener(
    Function(String, String, int, Future<void> Function(), Future<void> Function()) listener,
  ) {
    _incomingRequestListeners.remove(listener);
  }

  /// Check if VPN is detected (iOS specific issue)
  bool get isVpnDetected => _multicastService.isVpnDetected;

  /// Get the connection manager for managing P2P connections
  ConnectionManager? get connectionManager => _isInitialized ? _connectionManager : null;

  /// Initialize and start all services
  Future<void> initialize() async {
    if (_isInitialized) {
      print('[DiscoveryService] Already initialized');
      return;
    }

    print('[DiscoveryService] Initializing...');
    print('[DiscoveryService] Alias: $alias');
    print('[DiscoveryService] Port: $port');
    print('[DiscoveryService] Fingerprint: $fingerprint');
    print('[DiscoveryService] Device Model: $deviceModel');

    try {
      // Acquire multicast lock on Android
      if (Platform.isAndroid) {
        print('[DiscoveryService] Acquiring Android multicast lock...');
        final lockAcquired = await MulticastPlatformHelper.acquireMulticastLock();
        if (!lockAcquired) {
          print('[DiscoveryService] Warning: Failed to acquire multicast lock');
          print('[DiscoveryService] Multicast discovery may not work properly');
        }
      }

      // Initialize HTTP client
      _httpClient = HttpDiscoveryClient(
        fingerprint: fingerprint,
        alias: alias,
        port: port,
        deviceModel: deviceModel,
      );

      // Initialize and start HTTP server
      _httpServer = HttpServerService(
        port: port,
        alias: alias,
        fingerprint: fingerprint,
        deviceModel: deviceModel,
        onDeviceRegistered: _onDeviceDiscovered,
      );
      await _httpServer.start();

      // Initialize ConnectionManager for handling P2P connections
      print('[DiscoveryService] Initializing ConnectionManager');
      _connectionManager = ConnectionManager();
      _connectionManager.initialize(alias);

      // Initialize and start P2P incoming connection listener
      print('[DiscoveryService] Starting P2P connection listener on port $p2pPort');
      _incomingConnectionService = IncomingConnectionService(
        port: p2pPort,
        deviceName: alias,
      );
      _incomingConnectionService.addConnectionListener(_onIncomingConnection);
      await _incomingConnectionService.startListening();

      // Initialize and start multicast listener
      _multicastService = MulticastService(
        alias: alias,
        fingerprint: fingerprint,
        port: port,
        deviceModel: deviceModel,
      );
      _multicastService.addDiscoveryListener(_onMulticastDiscovery);
      await _multicastService.startListening();

      // iOS real devices: Use Bonjour/mDNS instead of multicast
      if (Platform.isIOS && !Platform.environment.containsKey('FLUTTER_TEST')) {
        print('[DiscoveryService] iOS detected - starting Bonjour service');
        print('[DiscoveryService] ⚠️  IMPORTANT: iOS requires Local Network permission');
        print('[DiscoveryService] If discovery doesn\'t work:');
        print('[DiscoveryService]   1. Go to iPhone Settings → Privacy → Local Network');
        print('[DiscoveryService]   2. Find "cpft" and toggle it ON');
        print('[DiscoveryService]   3. Restart the app');
        
        try {
          _bonjourService = BonjourService(
            alias: alias,
            fingerprint: fingerprint,
            port: port,
            deviceModel: deviceModel,
          );
          _bonjourService!.addDiscoveryListener(_onBonjourDiscovery);
          await _bonjourService!.start();
        } catch (e) {
          print('[DiscoveryService] ⚠️  Bonjour failed to start: $e');
          print('[DiscoveryService] This usually means Local Network permission is denied');
        }
      }

      _isInitialized = true;
      print('[DiscoveryService] Initialization complete!');
      print('[DiscoveryService] Listening for devices...');
    } catch (e) {
      print('[DiscoveryService] Initialization failed: $e');
      rethrow;
    }
  }

  /// Handle incoming P2P connection
  void _onIncomingConnection(Socket socket, String remoteName) async {
    final ip = socket.remoteAddress.address;
    final port = socket.remotePort;
    print('[DiscoveryService] 📞 Incoming P2P connection from $remoteName');
    print('[DiscoveryService] Remote address: $ip:$port');

    // Determine display name (try match discovered devices by IP)
    String displayName = remoteName;
    try {
      for (final entry in _discoveredDevices.entries) {
        if (entry.value.ip == ip) {
          displayName = entry.value.name;
          break;
        }
      }
    } catch (_) {}

    // Build accept/decline closures
    Future<void> accept() async {
      print('[DiscoveryService] ✅ Accepting incoming connection from $displayName');
      await _connectionManager.handleIncomingConnection(socket, displayName);
    }

    Future<void> decline() async {
      print('[DiscoveryService] ❌ Declining incoming connection from $displayName');
      try { await socket.close(); } catch (_) {}
    }

    // Notify UI listeners to prompt user
    for (final listener in _incomingRequestListeners) {
      try {
        listener(displayName, ip, p2pPort, accept, decline);
      } catch (e) {
        print('[DiscoveryService] Error notifying incoming request listener: $e');
      }
    }
  }

  /// Handle device discovered via multicast
  void _onMulticastDiscovery(String deviceName, String ipAddress, int port) {
    print('[DiscoveryService] 🔵 MULTICAST DISCOVERY CALLBACK FIRED!');
    print('[DiscoveryService] Device: $deviceName at $ipAddress:$port');
    print('[DiscoveryService] Platform: ${Platform.operatingSystem}');
    
    // Try to register with the device via HTTP
    print('[DiscoveryService] Attempting HTTP registration with $deviceName...');
    _httpClient.registerWithDevice(ipAddress, port).then((success) {
      print('[DiscoveryService] 📡 HTTP registration ${success ? "SUCCESS" : "FAILED"} for $deviceName');
      if (success) {
        print('[DiscoveryService] ✅ Calling _onDeviceDiscovered for $deviceName');
        _onDeviceDiscovered(deviceName, ipAddress, port);
      } else {
        print('[DiscoveryService] ⚠️  Registration failed for $deviceName, not adding to discovered devices');
      }
    }).catchError((error) {
      print('[DiscoveryService] ❌ HTTP registration error: $error');
    });
  }

  /// Handle device discovered via Bonjour (iOS)
  void _onBonjourDiscovery(String deviceName, String ipAddress, int port) {
    print('[DiscoveryService] 🎯 Bonjour discovery: $deviceName at $ipAddress:$port');
    
    // Try to register with the device via HTTP
    _httpClient.registerWithDevice(ipAddress, port).then((success) {
      print('[DiscoveryService] HTTP registration result (Bonjour): $success for $deviceName');
      if (success) {
        _onDeviceDiscovered(deviceName, ipAddress, port);
      } else {
        print('[DiscoveryService] ⚠️  Bonjour registration failed for $deviceName');
      }
    }).catchError((error) {
      print('[DiscoveryService] ❌ Bonjour HTTP registration error: $error');
    });
  }

  /// Handle device discovered/registered
  void _onDeviceDiscovered(String deviceName, String ipAddress, int port) {
    print('[DiscoveryService] 🎯 _onDeviceDiscovered called for $deviceName at $ipAddress:$port');
    final key = '$ipAddress:$port';
    
    // Check if this is a new device or an update
    final isNewDevice = !_discoveredDevices.containsKey(key);

    // Update or add the device
    _discoveredDevices[key] = DeviceInfo(
      name: deviceName,
      ip: ipAddress,
      port: port,
      lastSeen: DateTime.now(),
    );

    if (isNewDevice) {
      print('[DiscoveryService] 🆕 New device discovered: $deviceName ($ipAddress:$port)');
    } else {
      print('[DiscoveryService] 🔄 Device updated: $deviceName ($ipAddress:$port)');
    }

    print('[DiscoveryService] 📢 Notifying ${_discoveryListeners.length} UI listeners...');
    // Always notify listeners (even for duplicates, so UI can update)
    int notifiedCount = 0;
    for (var listener in _discoveryListeners) {
      try {
        listener(deviceName, ipAddress, port);
        notifiedCount++;
      } catch (e) {
        print('[DiscoveryService] ❌ Error notifying listener: $e');
      }
    }
    print('[DiscoveryService] ✅ Successfully notified $notifiedCount UI listeners');
  }

  /// Send announcement (trigger discovery)
  Future<void> announce() async {
    if (!_isInitialized) {
      print('[DiscoveryService] Not initialized');
      return;
    }

    print('[DiscoveryService] Sending announcement...');
    await _multicastService.sendAnnouncement();
    
    // On iOS, also trigger Bonjour refresh
    if (Platform.isIOS && _bonjourService != null) {
      print('[DiscoveryService] Triggering Bonjour refresh...');
      _bonjourService!.refreshDiscovery();
    }
  }

  /// Get list of discovered devices
  Map<String, DeviceInfo> get discoveredDevices => Map.unmodifiable(_discoveredDevices);

  /// Clear discovered devices
  void clearDevices() {
    _discoveredDevices.clear();
  }

  /// Dispose all services
  void dispose() {
    print('[DiscoveryService] Disposing...');
    _multicastService.dispose();
    _bonjourService?.dispose();
    _httpServer.dispose();
    _incomingConnectionService.dispose();
    _discoveryListeners.clear();
    _discoveredDevices.clear();
    _isInitialized = false;
    
    // Release multicast lock on Android
    if (Platform.isAndroid) {
      MulticastPlatformHelper.releaseMulticastLock();
    }
  }
}

/// Device information model
class DeviceInfo {
  final String name;
  final String ip;
  final int port;
  final DateTime lastSeen;

  DeviceInfo({
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });
}
