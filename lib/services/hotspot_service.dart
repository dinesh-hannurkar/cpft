import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fylooo/features/wifi_direct/wifi_direct_service.dart';
import 'package:fylooo/models/hotspot_info.dart';
import 'package:fylooo/services/discovery_service.dart';

class LocalHotspotService {
  static const platform = MethodChannel('com.omnity.fylooo/hotspot');
  static final _wifiDirectService = WiFiDirectService();
  static StreamSubscription? _connectionSub;
  static HotspotInfo? _cachedHotspotInfo;
  static DateTime? _expiryTime;

  static HotspotInfo? get cachedHotspotInfo => _cachedHotspotInfo;
  static DateTime? get expiryTime => _expiryTime;

  static bool get isExpired =>
      _expiryTime != null && DateTime.now().isAfter(_expiryTime!);

  /// Start hotspot - uses WiFi Direct on Android, falls back to platform hotspot on other platforms
  static Future<HotspotInfo?> startHotspot({bool forceNew = false}) async {
    if (Platform.isAndroid) {
      // If we already have a hotspot and it's NOT expired, and we aren't forcing a new one, reuse it.
      if (!forceNew && _connectionSub != null && _cachedHotspotInfo != null) {
        if (_expiryTime == null || DateTime.now().isBefore(_expiryTime!)) {
          return _cachedHotspotInfo;
        }
        // If expired, or forced, we stop the old one first
      }

      if (forceNew ||
          (_expiryTime != null && DateTime.now().isAfter(_expiryTime!))) {
        await stopHotspot();
      }

      // Use WiFi Direct on Android
      try {
        // Initialize WiFi Direct service
        await _wifiDirectService.initialize();

        // Create WiFi Direct group (Native layer will reuse existing group if already active)
        // If we called stopHotspot() above, the native group is removed.
        final success = await _wifiDirectService.createGroup();
        if (!success) {
          return null;
        }

        // Wait for group credentials from connection stream
        final completer = Completer<HotspotInfo?>();

        _connectionSub = _wifiDirectService.connectionStream.listen((event) {
          if (event.isGroupOwner &&
              event.ssid != null &&
              event.password != null) {
            if (!completer.isCompleted) {
              _cachedHotspotInfo = HotspotInfo(
                ssid: event.ssid!,
                password: event.password!,
                securityType: 'WPA2',
              );
              // Fresh hotspot: set expiry to 60 seconds
              _expiryTime = DateTime.now().add(const Duration(seconds: 60));
              completer.complete(_cachedHotspotInfo);
            }
          } else if (event.isLost) {
            _cachedHotspotInfo = null;
            _expiryTime = null;
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        });

        // Timeout after 30 seconds (some devices take longer to establish group)
        return await completer.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            _connectionSub?.cancel();
            _connectionSub = null;
            _cachedHotspotInfo = null;
            _expiryTime = null;
            return null;
          },
        );
      } catch (e) {
        debugPrint('WiFi Direct hotspot error: $e');
        _cachedHotspotInfo = null;
        _expiryTime = null;
        return null;
      }
    } else {
      // Fall back to platform-specific hotspot for other platforms
      try {
        final result = await platform.invokeMethod('startLocalOnlyHotspot');
        if (result != null && result['success'] == true) {
          return HotspotInfo(
            ssid: result['ssid'] as String,
            password: result['password'] as String,
            securityType: result['securityType'] ?? 'WPA2',
          );
        }
      } catch (e) {
        print('Platform hotspot error: $e');
      }
      return null;
    }
  }

  /// Stop hotspot - disconnects WiFi Direct on Android, stops platform hotspot on other platforms
  static Future<bool> stopHotspot() async {
    // Disable auto-accept regardless of platform
    DiscoveryService.sharedConnectionManager?.setAutoAccept(false);

    if (Platform.isAndroid) {
      // Disconnect WiFi Direct
      try {
        _connectionSub?.cancel();
        _connectionSub = null;
        _cachedHotspotInfo = null;
        await _wifiDirectService.disconnect();
        return true;
      } catch (e) {
        print('WiFi Direct stop error: $e');
        _cachedHotspotInfo = null;
        return false;
      }
    } else {
      // Stop platform hotspot
      try {
        final result = await platform.invokeMethod('stopLocalOnlyHotspot');
        return result?['success'] ?? false;
      } catch (e) {
        print('Platform hotspot stop error: $e');
        return false;
      }
    }
  }

  /// Check if hotspot is currently running
  static Future<bool> isHotspotRunning() async {
    if (Platform.isAndroid) {
      // For WiFi Direct, check if we have an active subscription
      return _connectionSub != null;
    } else {
      try {
        final result = await platform.invokeMethod('isHotspotRunning');
        return result ?? false;
      } catch (e) {
        return false;
      }
    }
  }
}
