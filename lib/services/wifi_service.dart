import 'dart:io';
import 'package:flutter/services.dart';

class WifiService {
  static const MethodChannel _channel = MethodChannel('com.example.cpft/wifi');

  /// Connect to a WiFi network
  /// Returns a map with connection status
  static Future<Map<String, dynamic>> connectToWifi({
    required String ssid,
    String? password,
    String security = 'WPA',
  }) async {

    try {
      final result = await _channel.invokeMethod('connectToWifi', {
        'ssid': ssid,
        'password': password,
        'security': security,
      });

      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw 'Failed to connect to WiFi: ${e.message}';
    }
  }

  /// Disconnect from current WiFi network
  static Future<Map<String, dynamic>> disconnectWifi() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('WiFi disconnection is only supported on Android');
    }

    try {
      final result = await _channel.invokeMethod('disconnectWifi');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw 'Failed to disconnect WiFi: ${e.message}';
    }
  }

  /// Get current connected WiFi SSID
  static Future<String?> getCurrentWifiSsid() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod('getCurrentWifi');
      return result as String?;
    } catch (e) {
      // Ignore errors when getting current WiFi
      return null;
    }
  }

  /// Check if WiFi connection is supported on this platform
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;
}