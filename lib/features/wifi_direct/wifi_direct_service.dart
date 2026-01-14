import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for WiFi Direct (P2P) connections
/// Provides faster peer-to-peer transfers without router
class WiFiDirectService {
  static const _channel = MethodChannel('com.omnity.fylooo/wifi_direct');

  static final WiFiDirectService _instance = WiFiDirectService._();
  factory WiFiDirectService() => _instance;
  WiFiDirectService._();

  bool _isSupported = false;
  bool _isEnabled = false;
  final _peerController = StreamController<List<WiFiDirectPeer>>.broadcast();
  final _connectionController =
      StreamController<WiFiDirectConnectionEvent>.broadcast();
  WiFiDirectThisDevice? _thisDevice;

  bool _callbacksWired = false;

  Stream<List<WiFiDirectPeer>> get peersStream => _peerController.stream;
  Stream<WiFiDirectConnectionEvent> get connectionStream =>
      _connectionController.stream;

  WiFiDirectThisDevice? get cachedThisDevice => _thisDevice;

  void _ensureCallbacksWired() {
    if (_callbacksWired) return;
    _callbacksWired = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onDiscoveryStarted':
          debugPrint('[WiFiDirect] Discovery started');
          return;
        case 'onDiscoveryFailed':
          debugPrint('[WiFiDirect] Discovery failed: ${call.arguments}');
          return;
        case 'onPeersChanged':
          final args = call.arguments;
          if (args is List) {
            final peers = <WiFiDirectPeer>[];
            for (final item in args) {
              if (item is Map) {
                peers.add(WiFiDirectPeer.fromMap(item));
              }
            }
            _peerController.add(peers);
          }
          return;
        case 'onConnectionEstablished':
          final args = call.arguments;
          if (args is Map) {
            final ip = args['ipAddress'] as String?;
            final port = args['port'] as int?;
            final isGroupOwner = args['isGroupOwner'] as bool? ?? false;
            if (ip != null && port != null) {
              _connectionController.add(
                WiFiDirectConnectionEvent(
                  ipAddress: ip,
                  port: port,
                  isGroupOwner: isGroupOwner,
                ),
              );
            }
          }
          return;
        case 'onConnectionLost':
          _connectionController.add(const WiFiDirectConnectionEvent.lost());
          return;
        case 'onThisDeviceChanged':
          final args = call.arguments;
          if (args is Map) {
            final id = args['id'] as String?;
            final name = args['name'] as String?;
            if (name != null && name.isNotEmpty) {
              _thisDevice = WiFiDirectThisDevice(id: id ?? '', name: name);
            }
          }
          return;
        default:
          debugPrint('[WiFiDirect] Unknown callback: ${call.method}');
          return;
      }
    });
  }

  Future<WiFiDirectThisDevice?> getThisDevice() async {
    if (!_isSupported || kIsWeb) return null;
    try {
      _ensureCallbacksWired();
      final result = await _channel.invokeMethod('getThisDevice');
      if (result is Map) {
        final id = result['id'] as String?;
        final name = result['name'] as String?;
        if (name != null && name.isNotEmpty) {
          _thisDevice = WiFiDirectThisDevice(id: id ?? '', name: name);
          return _thisDevice;
        }
      }
    } catch (e) {
      debugPrint('[WiFiDirect] getThisDevice error: $e');
    }
    return _thisDevice;
  }

  Future<void> initialize() async {
    if (kIsWeb) {
      _isSupported = false;
      return;
    }

    _ensureCallbacksWired();

    try {
      if (Platform.isAndroid) {
        final supported = await _channel.invokeMethod('isWifiDirectSupported');
        _isSupported = supported == true;
        debugPrint('[WiFiDirect] Android P2P supported: $_isSupported');
      } else if (Platform.isIOS) {
        // iOS uses Multipeer Connectivity framework
        final supported = await _channel.invokeMethod('isMultipeerSupported');
        _isSupported = supported == true;
        debugPrint('[WiFiDirect] iOS Multipeer supported: $_isSupported');
      }
    } catch (e) {
      debugPrint('[WiFiDirect] Initialization error: $e');
      _isSupported = false;
    }
  }

  bool get isSupported => _isSupported;
  bool get isEnabled => _isEnabled;

  /// Start WiFi Direct discovery
  Future<bool> startDiscovery() async {
    if (!_isSupported) return false;

    try {
      _ensureCallbacksWired();
      final result = await _channel.invokeMethod('startDiscovery');
      _isEnabled = result == true;
      return _isEnabled;
    } catch (e) {
      debugPrint('[WiFiDirect] Start discovery error: $e');
      return false;
    }
  }

  /// Stop WiFi Direct discovery
  Future<void> stopDiscovery() async {
    if (!_isSupported) return;

    try {
      await _channel.invokeMethod('stopDiscovery');
      _isEnabled = false;
    } catch (e) {
      debugPrint('[WiFiDirect] Stop discovery error: $e');
    }
  }

  /// Create a P2P group and return credentials (Android 10+)
  Future<P2PCredentials?> createGroup() async {
    if (!_isSupported) return null;

    try {
      _ensureCallbacksWired();
      final result = await _channel.invokeMethod('createGroup');
      if (result is Map) {
        return P2PCredentials(
          ssid: result['ssid'] as String,
          password: result['password'] as String,
        );
      }
    } catch (e) {
      debugPrint('[WiFiDirect] Create group error: $e');
    }
    return null;
  }

  /// Connect to a WiFi Direct Group (Client side)
  Future<bool> connectToGroup({required String ssid, required String password}) async {
     if (!_isSupported) return false;

     try {
       // On Android, we can reuse the generic WifiService connect logic via method channel
       // or we can invoke a specific method in WIFI_DIRECT_CHANNEL if we implemented it there.
       // The plan decided to implement `connectToGroup` in WIFI_DIRECT_CHANNEL in MainActivity.kt
       // but I haven't added `connectToGroup` to MainActivity.kt yet in the new plan.
       // The previous attempt added `connect` (for peerId) but not `connectToGroup` (for SSID).

       // Actually, the best way is to use the existing WifiService.connectToWifi
       // because it already handles WifiNetworkSpecifier perfectly.
       // But to encapsulate it here as requested:

       final method = Platform.isAndroid ? 'connectToGroup' : 'connectToGroupIOS';
       // Note: iOS doesn't support connecting to specific SSID programmatically usually without NEHotspotConfigurationManager.
       // WifiService likely handles it.

       // Let's call the native `connectToGroup` which I will add to MainActivity/WiFiDirectManager
       // to satisfy the strict P2P requirement.
       final result = await _channel.invokeMethod('connectToGroup', {
         'ssid': ssid,
         'password': password
       });
       return result == true;
     } catch (e) {
       debugPrint('[WiFiDirect] Connect to group error: $e');
       return false;
     }
  }

  /// Remove P2P group
  Future<void> removeGroup() async {
    if (!_isSupported) return;

    try {
      await _channel.invokeMethod('removeGroup');
    } catch (e) {
      debugPrint('[WiFiDirect] Remove group error: $e');
    }
  }

  /// Connect to a WiFi Direct peer
  Future<WiFiDirectConnection?> connect(String peerId) async {
    if (!_isSupported) return null;

    try {
      _ensureCallbacksWired();
      final result = await _channel
          .invokeMethod('connect', {'peerId': peerId})
          .timeout(const Duration(seconds: 20));
      if (result is Map) {
        return WiFiDirectConnection(
          peerId: result['peerId'] as String,
          ipAddress: result['ipAddress'] as String,
          port: result['port'] as int,
        );
      }
    } on TimeoutException {
      debugPrint('[WiFiDirect] Connection attempt timed out');
      disconnect();
    } catch (e) {
      debugPrint('[WiFiDirect] Connection error: $e');
    }
    return null;
  }

  /// Disconnect from current WiFi Direct connection
  Future<void> disconnect() async {
    if (!_isSupported) return;

    try {
      await _channel.invokeMethod('disconnect');
    } catch (e) {
      debugPrint('[WiFiDirect] Disconnect error: $e');
    }
  }

  void dispose() {
    _peerController.close();
    _connectionController.close();
  }
}

class WiFiDirectConnectionEvent {
  final String? ipAddress;
  final int? port;
  final bool isGroupOwner;
  final bool isLost;

  const WiFiDirectConnectionEvent({
    required this.ipAddress,
    required this.port,
    required this.isGroupOwner,
  }) : isLost = false;

  const WiFiDirectConnectionEvent.lost()
    : ipAddress = null,
      port = null,
      isGroupOwner = false,
      isLost = true;
}

class WiFiDirectPeer {
  final String id;
  final String name;
  final bool isConnected;

  WiFiDirectPeer({
    required this.id,
    required this.name,
    required this.isConnected,
  });

  factory WiFiDirectPeer.fromMap(Map<dynamic, dynamic> map) {
    return WiFiDirectPeer(
      id: map['id'] as String,
      name: map['name'] as String,
      isConnected: map['isConnected'] as bool? ?? false,
    );
  }
}

class WiFiDirectConnection {
  final String peerId;
  final String ipAddress;
  final int port;

  WiFiDirectConnection({
    required this.peerId,
    required this.ipAddress,
    required this.port,
  });
}

class WiFiDirectThisDevice {
  final String id;
  final String name;

  WiFiDirectThisDevice({required this.id, this.name = ''});
}

class P2PCredentials {
  final String ssid;
  final String password;

  P2PCredentials({required this.ssid, required this.password});
}
