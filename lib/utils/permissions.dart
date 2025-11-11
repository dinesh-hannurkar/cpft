import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class AppPermissions {
  static Future<bool> requestNetworkPermissions() async {
    if (Platform.isAndroid) {
      return await _requestAndroidPermissions();
    } else if (Platform.isIOS) {
      return await _requestIOSPermissions();
    }
    return true; // Desktop platforms don't need special permissions
  }

  static Future<bool> _requestAndroidPermissions() async {
    // On Android, we need location permission for WiFi operations
    final locationStatus = await Permission.location.request();
    if (locationStatus.isDenied || locationStatus.isPermanentlyDenied) {
      print('Location permission denied. This is required for device discovery on Android.');
      return false;
    }

    // Also request WiFi state permission if available
    final wifiStatus = await Permission.locationWhenInUse.request();
    if (wifiStatus.isDenied || wifiStatus.isPermanentlyDenied) {
      print('Location permission (when in use) denied. Device discovery may not work properly.');
      return false;
    }

    return true;
  }

  static Future<bool> _requestIOSPermissions() async {
    // On iOS 14+, local network permission is handled automatically by the system
    // when NSLocalNetworkUsageDescription is present in Info.plist
    // We don't need to explicitly request it via permission_handler
    return true;
  }

  static Future<void> openSettingsIfNeeded() async {
    if (Platform.isAndroid) {
      final locationStatus = await Permission.location.status;
      final locationWhenInUseStatus = await Permission.locationWhenInUse.status;

      if (locationStatus.isPermanentlyDenied || locationWhenInUseStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
    }
  }
}
