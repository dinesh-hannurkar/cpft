import 'dart:io';
import 'package:fylooo/models/hotspot_info.dart';
import 'package:flutter/services.dart';

class LocalHotspotService {
  static const platform = MethodChannel('com.omnity.fylooo/hotspot');
  static Future<HotspotInfo?> startHotspot() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      try {
        const wifiChannel = MethodChannel('com.omnity.fylooo/wifi');
        await wifiChannel.invokeMethod('disconnectWifi');
      } catch (_) {}

      final result = await platform.invokeMethod('startLocalOnlyHotspot');

      if (result['success']) {
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
