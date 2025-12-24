import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fylooo/core/logging/app_logger.dart';
import 'package:fylooo/features/webshare/services/web_server.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'multicast_service.dart';
import 'http_server_service.dart';
import 'http_discovery_client.dart';
import 'multicast_platform_helper.dart';
import 'bonjour_service.dart';
import 'incoming_connection_service.dart';
import '../../features/chat/services/connection_manager.dart';
import 'background_service.dart';

class DiscoveryService {
  MulticastService? _multicastService;
  HttpServerService? _httpServer;
  HttpDiscoveryClient? _httpClient;
  IncomingConnectionService? _incomingConnectionService;
  static ConnectionManager? _sharedConnectionManager;
  BonjourService? _bonjourService;
  WebServer? _webServer;
  final String alias;
  final int port;
  late final String fingerprint;
  final String deviceModel;
  final List<Function(String, String, int)> _discoveryListeners = [];
  final Map<String, DeviceInfo> _discoveredDevices = {};
  final List<
    Function(
      String deviceName,
      String ipAddress,
      int port,
      Future<void> Function() accept,
      Future<void> Function() decline,
    )
  >
  _incomingRequestListeners = [];
  final List<_QueuedIncoming> _queuedIncoming = [];

  bool _isInitialized = false;
  Timer? _cleanupTimer;
  Timer? _networkScanTimer;
  Timer? _healthCheckTimer;
  Completer<void>? _readyCompleter;
  static const int p2pPort = 53318;

  DiscoveryService({
    required this.alias,
    required this.deviceModel,
    this.port = 53317,
  }) {
    fingerprint = _generateFingerprint();
  }

  String _generateFingerprint() {
    final hostPart = kIsWeb ? 'web' : Platform.localHostname;
    final data = '$alias-$hostPart-${DateTime.now().millisecondsSinceEpoch}';
    return md5.convert(utf8.encode(data)).toString().substring(0, 16);
  }

  /// Add listener for device discoveries
  void addDiscoveryListener(
    Function(String deviceName, String ipAddress, int port) listener,
  ) {
    _discoveryListeners.add(listener);
  }

  /// Remove discovery listener
  void removeDiscoveryListener(Function(String, String, int) listener) {
    _discoveryListeners.remove(listener);
  }

  // Add/Remove incoming connection request listeners
  void addIncomingRequestListener(
    Function(
      String deviceName,
      String ipAddress,
      int port,
      Future<void> Function() accept,
      Future<void> Function() decline,
    )
    listener,
  ) {
    _incomingRequestListeners.add(listener);
    // Drain any queued incoming requests now that a listener exists
    _drainQueuedIncoming();
  }

  void removeIncomingRequestListener(
    Function(
      String,
      String,
      int,
      Future<void> Function(),
      Future<void> Function(),
    )
    listener,
  ) {
    _incomingRequestListeners.remove(listener);
  }

  /// Check if VPN is detected (iOS specific issue)
  bool get isVpnDetected => _multicastService!.isVpnDetected;

  /// Get the connection manager for managing P2P connections
  /// Returns the manager even if discovery isn't fully initialized, as connections can work independently
  ConnectionManager? get connectionManager {
    // Ensure ConnectionManager exists even if discovery had issues
    if (_sharedConnectionManager == null && alias.isNotEmpty) {
      _sharedConnectionManager = ConnectionManager();
      _sharedConnectionManager!.initialize(alias);
    }
    return _sharedConnectionManager;
  }

  /// Initialize and start all services
  Future<void> initialize() async {
    if (_isInitialized) {
      AppLogger.d('[DiscoveryService] Already initialized');
      return;
    }

    AppLogger.i('[DiscoveryService] Initializing...');
    AppLogger.d('[DiscoveryService] Alias: $alias');
    AppLogger.d('[DiscoveryService] Port: $port');
    AppLogger.d('[DiscoveryService] Fingerprint: $fingerprint');
    AppLogger.d('[DiscoveryService] Device Model: $deviceModel');

    try {
      // Acquire multicast lock on Android
      if (Platform.isAndroid) {
        AppLogger.d('[DiscoveryService] Acquiring Android multicast lock...');
        final lockAcquired =
            await MulticastPlatformHelper.acquireMulticastLock();
        if (!lockAcquired) {
          AppLogger.w(
            '[DiscoveryService] Warning: Failed to acquire multicast lock',
          );
          AppLogger.w(
            '[DiscoveryService] Multicast discovery may not work properly',
          );
        }
      }

      // Initialize HTTP client
      if (_httpClient == null) {
        _httpClient = HttpDiscoveryClient(
          fingerprint: fingerprint,
          alias: alias,
          port: port,
          deviceModel: deviceModel,
        );
      } else {
        AppLogger.d(
          '[DiscoveryService] Reusing existing HttpDiscoveryClient instance',
        );
      }

      // Initialize and start HTTP server
      _httpServer = HttpServerService(
        port: port,
        alias: alias,
        fingerprint: fingerprint,
        deviceModel: deviceModel,
        onDeviceRegistered: _onDeviceDiscovered,
      );
      await _httpServer!.start();

      // Initialize ConnectionManager for handling P2P connections
      AppLogger.d('[DiscoveryService] Initializing ConnectionManager');
      if (_sharedConnectionManager == null) {
        _sharedConnectionManager = ConnectionManager();
        _sharedConnectionManager!.initialize(alias);
      } else {
        AppLogger.d(
          '[DiscoveryService] Reusing existing ConnectionManager (preserving active connections)',
        );
        // Ensure it has the correct alias in case of restart
        _sharedConnectionManager!.initialize(alias);
      }

      // Initialize and start P2P incoming connection listener
      AppLogger.d(
        '[DiscoveryService] Starting P2P connection listener on port $p2pPort',
      );
      _incomingConnectionService ??= IncomingConnectionService(
        port: p2pPort,
        deviceName: alias,
      );
      _incomingConnectionService!.addConnectionListener(_onIncomingConnection);
      await _incomingConnectionService!.startListening();

      // Initialize and start multicast listener
      try {
        _multicastService ??= MulticastService(
          alias: alias,
          fingerprint: fingerprint,
          port: port,
          deviceModel: deviceModel,
        );
        _multicastService!.addDiscoveryListener(_onMulticastDiscovery);
        await _multicastService!.startListening();
      } catch (e) {
        AppLogger.w('[DiscoveryService] Multicast service failed to start: $e');
        AppLogger.w(
          '[DiscoveryService] This usually means no network connection is available',
        );
        AppLogger.w(
          '[DiscoveryService] App will continue but discovery may be limited',
        );
        _multicastService = null;
      }

      // iOS real devices: Use Bonjour/mDNS instead of multicast
      if (Platform.isIOS && !Platform.environment.containsKey('FLUTTER_TEST')) {
        AppLogger.i(
          '[DiscoveryService] iOS detected - starting Bonjour service',
        );
        AppLogger.w(
          '[DiscoveryService] IMPORTANT: iOS requires Local Network permission',
        );
        AppLogger.w('[DiscoveryService] If discovery doesn\'t work:');
        AppLogger.w(
          '[DiscoveryService]   1. Go to iPhone Settings → Privacy → Local Network',
        );
        AppLogger.w('[DiscoveryService]   2. Find "cpft" and toggle it ON');
        AppLogger.w('[DiscoveryService]   3. Restart the app');

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
          AppLogger.w('[DiscoveryService] Bonjour failed to start: $e');
          AppLogger.w(
            '[DiscoveryService] This usually means Local Network permission is denied',
          );
        }
      }

      // macOS: Also use Bonjour for local network discovery
      if (Platform.isMacOS &&
          !Platform.environment.containsKey('FLUTTER_TEST')) {
        AppLogger.i(
          '[DiscoveryService] macOS detected - starting Bonjour service',
          tag: 'Discovery',
        );

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
          AppLogger.w(
            'Bonjour failed to start on macOS: $e',
            tag: 'Discovery',
            error: e,
          );
        }
      }

      _isInitialized = true;
      AppLogger.i(
        'Initialization complete. Listening for devices...',
        tag: 'Discovery',
      );
      // Signal readiness to any awaiters
      _readyCompleter ??= Completer<void>();
      if (!(_readyCompleter!.isCompleted)) {
        _readyCompleter!.complete();
      }

      // Start cleanup timer to remove unavailable devices
      _startCleanupTimer();

      // Start network scanning as fallback discovery mechanism
      _startNetworkScanTimer();

      // Start health check timer
      _startHealthCheckTimer();

      // Initialize foreground service on Android (but don't start yet)
      // Service will start only when a connection is established
      if (Platform.isAndroid) {
        AppLogger.d(
          'Initializing Android foreground service...',
          tag: 'Discovery',
        );
        try {
          await BackgroundService.initialize();
          AppLogger.i(
            'Foreground service initialized (will start on connection)',
            tag: 'Discovery',
          );
        } catch (e) {
          AppLogger.w(
            'Error initializing foreground service: $e',
            tag: 'Discovery',
            error: e,
          );
        }
      }
    } catch (e) {
      AppLogger.w(
        'Some discovery services failed to initialize: $e',
        tag: 'Discovery',
        error: e,
      );
      AppLogger.w('Continuing with limited functionality', tag: 'Discovery');
      // Don't rethrow - allow app to continue even if discovery has issues
    }
  }

  /// Handle incoming P2P connection
  void _onIncomingConnection(Socket socket, String remoteName) async {
    final ip = socket.remoteAddress.address;
    final port = socket.remotePort;
    AppLogger.d('Incoming P2P connection from $remoteName', tag: 'Discovery');
    AppLogger.v('Remote address: $ip:$port', tag: 'Discovery');

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

    // If no listeners yet, queue the request to avoid losing the prompt
    if (_incomingRequestListeners.isEmpty) {
      AppLogger.w(
        'No UI listeners yet. Queuing incoming request from $displayName',
        tag: 'Discovery',
      );
      _queuedIncoming.add(
        _QueuedIncoming(
          displayName: displayName,
          ip: ip,
          socket: socket,
          receivedAt: DateTime.now(),
        ),
      );
      return;
    }

    _dispatchIncomingToUi(displayName: displayName, ip: ip, socket: socket);
  }

  /// Dispatch an incoming request to all UI listeners with accept/decline actions
  void _dispatchIncomingToUi({
    required String displayName,
    required String ip,
    required Socket socket,
  }) {
    // Build accept/decline closures
    Future<void> accept() async {
      AppLogger.i(
        'Accepting incoming connection from $displayName',
        tag: 'Discovery',
      );
      await _sharedConnectionManager!.handleIncomingConnection(
        socket,
        displayName,
      );
    }

    Future<void> decline() async {
      AppLogger.d(
        'Declining incoming connection from $displayName',
        tag: 'Discovery',
      );
      try {
        // Send explicit rejection message so remote can fail fast instead of waiting for handshake timeout
        final rejectPayload = {
          'type': 'reject',
          'content': 'Connection declined',
          'senderName': alias,
          'timestamp': DateTime.now().toIso8601String(),
          'metadata': null,
        };
        try {
          socket.add(utf8.encode('${jsonEncode(rejectPayload)}\n'));
          await socket.flush();
        } catch (_) {}
        // Close socket afterwards
        await socket.close();
      } catch (_) {}

      // Safety: ensure our incoming listener remains active after a decline
      try {
        if (!_incomingConnectionService!.isListening) {
          AppLogger.w(
            'Incoming service not listening after decline. Restarting listener...',
            tag: 'Discovery',
          );
          await _incomingConnectionService!.startListening();
        }
      } catch (e) {
        AppLogger.w(
          'Failed to ensure incoming listening after decline: $e',
          tag: 'Discovery',
          error: e,
        );
        // As a last resort, restart discovery services to recover the stack
        try {
          await restartDiscovery();
        } catch (_) {}
      }
    }

    // Notify UI listeners to prompt user
    for (final listener in _incomingRequestListeners) {
      try {
        listener(displayName, ip, p2pPort, accept, decline);
      } catch (e) {
        AppLogger.w(
          'Error notifying incoming request listener: $e',
          tag: 'Discovery',
          error: e,
        );
      }
    }
  }

  /// Drain any queued incoming requests to current listeners
  void _drainQueuedIncoming() {
    if (_queuedIncoming.isEmpty) return;
    if (_incomingRequestListeners.isEmpty) return;

    // Drop any entries older than 15 seconds to avoid stale prompts
    final cutoff = DateTime.now().subtract(const Duration(seconds: 15));
    final draining = List<_QueuedIncoming>.from(_queuedIncoming);
    _queuedIncoming.clear();

    for (final q in draining) {
      if (q.receivedAt.isBefore(cutoff)) {
        AppLogger.d(
          'Dropping stale queued incoming from ${q.displayName}',
          tag: 'Discovery',
        );
        try {
          q.socket.close();
        } catch (_) {}
        continue;
      }
      AppLogger.d(
        'Dispatching queued incoming from ${q.displayName}',
        tag: 'Discovery',
      );
      _dispatchIncomingToUi(
        displayName: q.displayName,
        ip: q.ip,
        socket: q.socket,
      );
    }
  }

  /// Handle device discovered via multicast
  void _onMulticastDiscovery(String deviceName, String ipAddress, int port) {
    _httpClient!
        .registerWithDevice(ipAddress, port)
        .then((success) {
          if (success) {
            _onDeviceDiscovered(deviceName, ipAddress, port);
          } else {}
        })
        .catchError((error) {
          print('[DiscoveryService] ❌ HTTP registration error: $error');
        });
  }

  /// Handle device discovered via Bonjour (iOS)
  void _onBonjourDiscovery(String deviceName, String ipAddress, int port) {
    _httpClient!
        .registerWithDevice(ipAddress, port)
        .then((success) {
          if (success) {
            _onDeviceDiscovered(deviceName, ipAddress, port);
          } else {}
        })
        .catchError((error) {
          print('[DiscoveryService] ❌ Bonjour HTTP registration error: $error');
        });
  }

  /// Handle device discovered/registered
  void _onDeviceDiscovered(String deviceName, String ipAddress, int port) {
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
      print(
        '[DiscoveryService] 🆕 New device discovered: $deviceName ($ipAddress:$port)',
      );
    } else {
      print(
        '[DiscoveryService] 🔄 Device updated: $deviceName ($ipAddress:$port)',
      );
    }
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
    print(
      '[DiscoveryService] ✅ Successfully notified $notifiedCount UI listeners',
    );
  }

  /// Send announcement (trigger discovery)
  Future<void> announce() async {
    if (!_isInitialized) {
      return;
    }

    if (_multicastService != null) {
      await _multicastService!.sendAnnouncement();
    } else {
      print('[DiscoveryService] Multicast service not available');
    }

    // On iOS/macOS, also trigger Bonjour refresh
    if ((Platform.isIOS || Platform.isMacOS) && _bonjourService != null) {
      _bonjourService!.refreshDiscovery();
    }
  }

  /// Get list of discovered devices
  Map<String, DeviceInfo> get discoveredDevices =>
      Map.unmodifiable(_discoveredDevices);

  /// Clear discovered devices
  void clearDevices() {
    _discoveredDevices.clear();
  }

  /// Dispose all services
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _networkScanTimer?.cancel();
    _healthCheckTimer?.cancel();
    _multicastService?.dispose();

    // Properly await Bonjour service disposal (important for iOS/macOS)
    if (_bonjourService != null) {
      try {
        await _bonjourService!.dispose();
      } catch (e) {
        debugPrint('[DiscoveryService] Error stopping Bonjour service: $e');
      }
    }

    if (_httpServer != null) {
      await _httpServer!.dispose();
      _httpServer = null;
    }
    _incomingConnectionService?.dispose();
    _discoveryListeners.clear();
    _queuedIncoming.clear();
    _discoveredDevices.clear();
    _isInitialized = false;

    // Reset readyCompleter for restart capability
    _readyCompleter = null;

    // Set fields to null for restart capability (except ConnectionManager)
    _multicastService = null;
    _httpClient = null;
    _incomingConnectionService = null;
    _bonjourService = null;

    // Note: Background service is now managed by ConnectionStateManager
    // based on actual connection states, not discovery state
    if (Platform.isAndroid) {
      // Release multicast lock on Android
      MulticastPlatformHelper.releaseMulticastLock();
    }
  }

  /// Start periodic cleanup timer for unavailable devices
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _cleanupUnavailableDevices();
    });
  }

  /// Force restart all discovery services (useful when discovery stops working)
  Future<void> restartDiscovery() async {
    try {
      await dispose();
      // Wait for sockets to be fully released by the OS
      await Future.delayed(const Duration(seconds: 5));
      // Now initialize fresh
      await initialize();
    } catch (e) {
      // Try to recover by just initializing if dispose worked but initialize failed
      if (!_isInitialized) {
        try {
          await initialize();
        } catch (recoveryError) {
          print(
            '[DiscoveryService] ❌ Recovery initialization also failed: $recoveryError',
          );
        }
      }
      rethrow;
    }
  }

  /// Start periodic health check timer
  void _startHealthCheckTimer() {
    // Avoid duplicate timers across restarts
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      checkDiscoveryHealth();
    });
  }

  /// Check if discovery services are healthy and restart if needed
  Future<void> checkDiscoveryHealth() async {
    if (!_isInitialized) {
      return;
    }

    try {
      final serverHealthy = _httpServer?.isRunning ?? false;
      final incomingHealthy = _incomingConnectionService?.isListening ?? false;

      // If HTTP server failed, perform full restart
      if (!serverHealthy) {
        await restartDiscovery();
        return; // Skip further checks this cycle
      }

      // If incoming listener stopped unexpectedly, attempt to restart it in isolation
      if (!incomingHealthy) {
        try {
          await _incomingConnectionService!.startListening();
        } catch (e) {
          await restartDiscovery();
          return;
        }
      }
    } catch (e) {
      try {
        await restartDiscovery();
      } catch (restartError) {
        print(
          '[DiscoveryService] Failed to restart after health check error: $restartError',
        );
      }
    }
  }

  /// Start periodic network scanning timer for fallback discovery
  void _startNetworkScanTimer() {
    _networkScanTimer?.cancel();
    _networkScanTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _scanLocalNetwork();
    });
  }

  /// Scan local network for devices (LocalSend-style fallback discovery)
  Future<void> _scanLocalNetwork() async {
    try {
      // Get local IP address
      final localIp = await _getLocalIpAddress();
      if (localIp == null) {
        return;
      }

      // Extract subnet (e.g., 192.168.1.0/24)
      final subnet = _getSubnet(localIp);

      // Scan common ports in the subnet
      final scanFutures = <Future>[];
      for (int i = 1; i <= 254; i++) {
        final ip = '$subnet$i';
        if (ip != localIp) {
          // Don't scan ourselves
          scanFutures.add(_checkDeviceAt(ip, port));
        }
      }

      // Limit concurrent scans to avoid overwhelming the network
      const int maxConcurrent = 20;
      for (int i = 0; i < scanFutures.length; i += maxConcurrent) {
        final batch = scanFutures.sublist(
          i,
          i + maxConcurrent > scanFutures.length
              ? scanFutures.length
              : i + maxConcurrent,
        );
        await Future.wait(batch);
        // Small delay between batches
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      print('[DiscoveryService] Error during network scan: $e');
    }
  }

  /// Check if a device is running at the given IP and port
  Future<void> _checkDeviceAt(String ip, int port) async {
    try {
      final info = await _httpClient!.getDeviceInfo(ip, port);
      if (info != null && info.fingerprint != fingerprint) {
        _onDeviceDiscovered(info.alias, ip, port);
      }
    } catch (e) {
      // Ignore connection errors - device not available
    }
  }

  /// Extract subnet from IP address (assumes /24 subnet)
  String _getSubnet(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}.';
    }
    return '';
  }

  /// Remove devices that haven't been seen for more than 3 minutes
  void _cleanupUnavailableDevices() {
    final now = DateTime.now();
    // Increased from 30 seconds to 3 minutes to prevent removing active devices
    final cutoffTime = now.subtract(const Duration(seconds: 30));

    final devicesToRemove = <String>[];

    _discoveredDevices.forEach((key, device) {
      if (device.lastSeen.isBefore(cutoffTime)) {
        devicesToRemove.add(key);
      }
    });

    if (devicesToRemove.isNotEmpty) {
      for (final key in devicesToRemove) {
        _discoveredDevices.remove(key);
      }

      // Notify listeners that devices were removed
      for (var listener in _discoveryListeners) {
        try {
          listener('', '', 0);
        } catch (e) {
          print('[DiscoveryService] ❌ Error notifying cleanup listener: $e');
        }
      }
    }
  }

  /// Start web server for browser-based file transfers
  Future<bool> startWebServer({int port = 80}) async {
    if (_webServer != null && _webServer!.isRunning) {
      return true;
    }

    _webServer = WebServer(
      deviceName: alias,
      onFileUploadProgress: (filename, received, total) {
        _notifyUploadProgress(filename, received, total);
      },
      onFileUploadComplete: (filename, savedPath) {
        _notifyFileReceived(filename, savedPath);
      },
    );

    final success = await _webServer!.start(port: port);

    if (success) {
      print('[DiscoveryService] ✅ Web server started on port $port');
    } else {
      print('[DiscoveryService] ❌ Failed to start web server');
    }

    return success;
  }

  // Listeners for web file transfers
  final List<Function(String filename, String path)> _webFileListeners = [];
  final List<Function(String filename, int received, int total)>
  _webProgressListeners = [];

  void addWebFileListener(Function(String filename, String path) listener) {
    _webFileListeners.add(listener);
  }

  void removeWebFileListener(Function(String filename, String path) listener) {
    _webFileListeners.remove(listener);
  }

  void addWebProgressListener(
    Function(String filename, int received, int total) listener,
  ) {
    _webProgressListeners.add(listener);
  }

  void removeWebProgressListener(
    Function(String filename, int received, int total) listener,
  ) {
    _webProgressListeners.remove(listener);
  }

  void _notifyFileReceived(String filename, String path) {
    for (var listener in _webFileListeners) {
      try {
        listener(filename, path);
      } catch (e) {
        print('[DiscoveryService] Error in web file listener: $e');
      }
    }
  }

  void _notifyUploadProgress(String filename, int received, int total) {
    for (var listener in _webProgressListeners) {
      try {
        listener(filename, received, total);
      } catch (e) {
        print('[DiscoveryService] Error in web progress listener: $e');
      }
    }
  }

  /// Stop web server
  Future<void> stopWebServer() async {
    if (_webServer != null) {
      await _webServer!.stop();
      _webServer = null;
    }
  }

  /// Get shareable web link
  Future<String?> getWebLink() async {
    if (_webServer == null || !_webServer!.isRunning) {
      return null;
    }

    // Get local IP address
    final ipAddress = await _getLocalIpAddress();
    if (ipAddress == null) return null;

    return _webServer!.getWebLink(ipAddress);
  }

  /// Get local IP address
  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            // Prefer local network addresses (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
            final ip = addr.address;
            if (ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                (ip.startsWith('172.') && _isPrivateClassB(ip))) {
              return ip;
            }
          }
        }
      }
    } catch (e) {
      print('[DiscoveryService] Error getting local IP: $e');
    }
    return null;
  }

  bool _isPrivateClassB(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }

  /// Check if web server is running
  bool get isWebServerRunning => _webServer?.isRunning ?? false;

  /// Share a file via web server
  String? shareFileViaWeb(String filePath, String filename) {
    if (_webServer == null || !_webServer!.isRunning) {
      return null;
    }
    return _webServer!.addFileForDownload(filePath, filename);
  }

  /// Remove file from web share
  void removeFileFromWeb(String fileId) {
    if (_webServer != null && _webServer!.isRunning) {
      _webServer!.removeFileFromDownload(fileId);
    }
  }

  /// Get list of files currently shared via web
  List<Map<String, dynamic>> getSharedFiles() {
    if (_webServer != null && _webServer!.isRunning) {
      return _webServer!.getSharedFiles();
    }
    return [];
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

/// Internal model for queued incoming connection prompts
class _QueuedIncoming {
  final String displayName;
  final String ip;
  final Socket socket;
  final DateTime receivedAt;

  _QueuedIncoming({
    required this.displayName,
    required this.ip,
    required this.socket,
    required this.receivedAt,
  });
}

extension DiscoveryServiceReadiness on DiscoveryService {
  /// Await this to ensure initialize() has completed.
  Future<void> get ready async {
    if (_isInitialized) return;
    _readyCompleter ??= Completer<void>();
    return _readyCompleter!.future;
  }
}
