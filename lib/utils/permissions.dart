import 'dart:io';
import 'package:cpft/core/logging/app_logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

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
    // First check if location services are enabled on the device
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      AppLogger.w('Location services disabled on device. User must enable in Settings.', tag: 'Permissions');
      AppLogger.w('Prompt user: Enable Location in device Settings.', tag: 'Permissions');
      return false;
    }
    
    // Android WiFi SSID access requires location (fine location for Android 10+)
    final locationStatus = await Permission.location.status;
    
    if (!locationStatus.isGranted) {
      AppLogger.d('Location permission not granted. Requesting...', tag: 'Permissions');
      final requestResult = await Permission.location.request();
      
      if (!requestResult.isGranted) {
        AppLogger.w('Location permission denied. WiFi name detection will not work.', tag: 'Permissions');
        AppLogger.w('Permission REQUIRED for WiFi SSID on Android 10+', tag: 'Permissions');
        return false;
      }
      AppLogger.i('Location permission granted', tag: 'Permissions');
    }
    
    return true;
  }

  static Future<bool> _requestIOSPermissions() async {
    // First check if location services are enabled on the device
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      AppLogger.w('iOS: Location services disabled. User must enable in Settings.', tag: 'Permissions');
      AppLogger.w('Instruction: Settings > Privacy & Security > Location Services', tag: 'Permissions');
      return false;
    }
    
    // On iOS, we need location permission for WiFi information access
    final locationStatus = await Permission.locationWhenInUse.status;
    AppLogger.d('iOS Location permission status: $locationStatus', tag: 'Permissions');

    if (locationStatus.isGranted) {
      AppLogger.i('iOS location permission already granted', tag: 'Permissions');
      return true;
    }

    if (locationStatus.isPermanentlyDenied) {
      AppLogger.w('iOS location permission permanently denied.', tag: 'Permissions');
      AppLogger.w('Guide: Settings > Privacy & Security > Location Services > [App] > Allow', tag: 'Permissions');
      // Don't try to request again, just inform user
      return false;
    }

    // Try to request permission
    final requestResult = await Permission.locationWhenInUse.request();
    AppLogger.d('iOS location permission request result: $requestResult', tag: 'Permissions');

    if (requestResult.isGranted) {
      AppLogger.i('iOS location permission granted', tag: 'Permissions');
      return true;
    } else {
      AppLogger.w('iOS location permission denied or restricted', tag: 'Permissions');
      return false;
    }
  }

  static Future<void> openLocationSettings() async {
    AppLogger.d('Opening app settings for location permission', tag: 'Permissions');
    await openAppSettings();
  }

  static Future<void> openSystemLocationSettings() async {
    if (Platform.isAndroid) {
      AppLogger.d('Opening Android system location settings', tag: 'Permissions');
      try {
        // Use MethodChannel to open Android location settings
        const platform = MethodChannel('cpft/settings');
        await platform.invokeMethod('openLocationSettings');
      } catch (e) {
        AppLogger.w('Error opening Android system location settings: $e', tag: 'Permissions', error: e);
        // Fallback to app settings
        await openAppSettings();
      }
    } else if (Platform.isIOS) {
      AppLogger.d('Opening iOS location settings', tag: 'Permissions');
      // On iOS, openAppSettings goes to app-specific settings where user can see location permission
      await openAppSettings();
    } else {
      await openAppSettings();
    }
  }

  static Future<bool> checkLocationPermission() async {
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted;
  }

  /// Check if location services are enabled on the device
  static Future<bool> isLocationServiceEnabled() async {
    final serviceStatus = await Permission.location.serviceStatus;
    return serviceStatus.isEnabled;
  }
}
