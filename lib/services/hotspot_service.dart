import 'dart:io';
import 'package:flutter/services.dart';

class LocalHotspotService {
  static const platform = MethodChannel('com.example.cpft/hotspot');

  // Start hotspot
  static Future<HotspotInfo?> startHotspot() async {
    // Hotspot APIs are Android-only. On other platforms, return null gracefully.
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      // Some devices keep WiFi connected while hotspot is on; proactively disconnect WiFi.
      try {
        // Use WifiService if available; ignore errors to avoid blocking hotspot start.
        const wifiChannel = MethodChannel('com.example.cpft/wifi');
        await wifiChannel.invokeMethod('disconnectWifi');
      } catch (_) {}

      final result = await platform.invokeMethod('startLocalOnlyHotspot');

      if (result['success']) {
        print('Hotspot started successfully:');
        print('SSID: "${result['ssid']}"');
        print('Password: "${result['password']}"');
        print('Security Type: "${result['securityType']}"');
        return HotspotInfo(
          ssid: result['ssid'] ?? 'Unknown',
          password: result['password'] ?? 'Unknown',
          securityType: result['securityType'] ?? 'WPA2',
        );
      } else {
        throw Exception(result['message'] ?? 'Failed to start hotspot');
      }
    } on PlatformException catch (e) {
      print("Error: ${e.message}");
      return null;
    }
  }

  // Stop hotspot
  static Future<bool> stopHotspot() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      final result = await platform.invokeMethod('stopLocalOnlyHotspot');
      return result['success'] ?? false;
    } on PlatformException catch (e) {
      print("Error: ${e.message}");
      return false;
    }
  }

  // Get hotspot details
  static Future<HotspotInfo?> getHotspotDetails() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final result = await platform.invokeMethod('getHotspotDetails');

      if (result['running'] ?? false) {
        return HotspotInfo(
          ssid: result['ssid'] ?? 'Unknown',
          password: result['password'] ?? 'Unknown',
          securityType: result['securityType'] ?? 'WPA2',
        );
      }
      return null;
    } on PlatformException catch (e) {
      print("Error: ${e.message}");
      return null;
    }
  }

  // Check if hotspot is running
  static Future<bool> isHotspotRunning() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      final result = await platform.invokeMethod('isHotspotRunning');
      return result ?? false;
    } on PlatformException catch (e) {
      print("Error: ${e.message}");
      return false;
    }
  }
}

// Model for hotspot information
class HotspotInfo {
  final String ssid;
  final String password;
  final String securityType;

  HotspotInfo({
    required this.ssid,
    required this.password,
    required this.securityType,
  });
}