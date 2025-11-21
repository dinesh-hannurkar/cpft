import 'dart:io';
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
      print('Location services are disabled on device. User must enable in Settings.');
      print('Please enable Location in device Settings.');
      return false;
    }
    
    // Android WiFi SSID access requires location (fine location for Android 10+)
    final locationStatus = await Permission.location.status;
    
    if (!locationStatus.isGranted) {
      print('Location permission not granted. Requesting...');
      final requestResult = await Permission.location.request();
      
      if (!requestResult.isGranted) {
        print('Location permission denied. WiFi name detection will not work.');
        print('This permission is REQUIRED to detect WiFi network name on Android 10+');
        return false;
      }
      print('Location permission granted');
    }
    
    return true;
  }

  static Future<bool> _requestIOSPermissions() async {
    // First check if location services are enabled on the device
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled on device. User must enable in Settings.');
      print('Please enable Location Services in Settings > Privacy & Security > Location Services');
      return false;
    }
    
    // On iOS, we need location permission for WiFi information access
    final locationStatus = await Permission.locationWhenInUse.status;
    print('iOS Location permission current status: $locationStatus');

    if (locationStatus.isGranted) {
      print('Location permission already granted');
      return true;
    }

    if (locationStatus.isPermanentlyDenied) {
      print('Location permission permanently denied. User must enable in Settings.');
      print('Please go to: Settings > Privacy & Security > Location Services > [App Name] > Allow');
      // Don't try to request again, just inform user
      return false;
    }

    // Try to request permission
    final requestResult = await Permission.locationWhenInUse.request();
    print('iOS Location permission request result: $requestResult');

    if (requestResult.isGranted) {
      print('Location permission granted successfully');
      return true;
    } else {
      print('Location permission denied or restricted');
      return false;
    }
  }

  static Future<void> openLocationSettings() async {
    print('Opening app settings for location permission...');
    await openAppSettings();
  }

  static Future<void> openSystemLocationSettings() async {
    if (Platform.isAndroid) {
      print('Opening Android system location settings...');
      try {
        // Use MethodChannel to open Android location settings
        const platform = MethodChannel('cpft/settings');
        await platform.invokeMethod('openLocationSettings');
      } catch (e) {
        print('Error opening location settings: $e');
        // Fallback to app settings
        await openAppSettings();
      }
    } else if (Platform.isIOS) {
      print('Opening iOS location settings...');
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
