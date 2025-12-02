import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cpft/core/logging/app_logger.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissions {
  static Future<bool> requestNetworkPermissions() async {
    // On web, runtime permissions are handled by the browser; skip app-level requests
    if (kIsWeb) {
      AppLogger.i('Web platform detected: skipping app-level permission checks', tag: 'Permissions');
      return true;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _requestAndroidPermissions();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
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

    // For Android, try to request nearby devices permission (required for WiFi hotspot on Android 12+)
    // We'll attempt to request it regardless of API level, and handle any exceptions
    try {
      AppLogger.d('Attempting to request nearby devices permission for WiFi hotspot', tag: 'Permissions');
      final nearbyDevicesStatus = await Permission.nearbyWifiDevices.status;
      AppLogger.d('Nearby devices permission status: $nearbyDevicesStatus', tag: 'Permissions');

      if (!nearbyDevicesStatus.isGranted) {
        AppLogger.d('Nearby devices permission not granted. Requesting...', tag: 'Permissions');

        // Force request the permission
        final nearbyRequestResult = await Permission.nearbyWifiDevices.request();
        AppLogger.d('Nearby devices permission request result: $nearbyRequestResult', tag: 'Permissions');

        if (!nearbyRequestResult.isGranted) {
          AppLogger.w('Nearby devices permission denied. WiFi hotspot may not work.', tag: 'Permissions');
          AppLogger.w('Permission REQUIRED for WiFi hotspot on Android 12+', tag: 'Permissions');

          // If permanently denied, guide user to settings
          if (nearbyRequestResult.isPermanentlyDenied) {
            AppLogger.w('Nearby devices permission permanently denied. Opening app settings...', tag: 'Permissions');
            await openAppSettings();
          }

          return false;
        }
        AppLogger.i('Nearby devices permission granted', tag: 'Permissions');
      } else {
        AppLogger.i('Nearby devices permission already granted', tag: 'Permissions');
      }
    } catch (e) {
      AppLogger.d('Nearby devices permission not available on this Android version (expected on Android < 12): $e', tag: 'Permissions');
      // This is expected on Android versions < 12 where the permission doesn't exist
      // Continue without the permission
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
    if (kIsWeb) {
      AppLogger.d('Web: location settings not applicable', tag: 'Permissions');
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      AppLogger.d('Location settings not applicable on desktop platforms', tag: 'Permissions');
      return;
    }
    try {
      AppLogger.d('Opening app settings for location permission', tag: 'Permissions');
      await openAppSettings();
    } catch (e) {
      AppLogger.w('Error opening location settings: $e', tag: 'Permissions', error: e);
    }
  }

  static Future<void> openSystemLocationSettings() async {
    if (kIsWeb) {
      AppLogger.d('Web: system location settings not applicable', tag: 'Permissions');
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      AppLogger.d('Opening Android system location settings', tag: 'Permissions');
      try {
        // Use MethodChannel to open Android location settings
        const platform = MethodChannel('cpft/settings');
        await platform.invokeMethod('openLocationSettings');
      } catch (e) {
        AppLogger.w('Error opening Android system location settings: $e', tag: 'Permissions', error: e);
        // Fallback to app settings
        try {
          await openAppSettings();
        } catch (e2) {
          AppLogger.w('Error opening app settings fallback: $e2', tag: 'Permissions', error: e2);
        }
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      AppLogger.d('Opening iOS location settings', tag: 'Permissions');
      // On iOS, openAppSettings goes to app-specific settings where user can see location permission
      try {
        await openAppSettings();
      } catch (e) {
        AppLogger.w('Error opening iOS settings: $e', tag: 'Permissions', error: e);
      }
    } else {
      AppLogger.d('Location settings not applicable on desktop platforms', tag: 'Permissions');
    }
  }

  static Future<bool> checkLocationPermission() async {
    // Web and desktop: treat as granted/not applicable
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return true;
    }
    try {
      final status = await Permission.locationWhenInUse.status;
      return status.isGranted;
    } catch (e) {
      AppLogger.w('Error checking location permission: $e', tag: 'Permissions', error: e);
      return true; // Assume granted on platforms that don't support it
    }
  }

  /// Check if location services are enabled on the device
  static Future<bool> isLocationServiceEnabled() async {
    // Web and desktop platforms don't need location service checks
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return true;
    }
    try {
      final serviceStatus = await Permission.location.serviceStatus;
      return serviceStatus.isEnabled;
    } catch (e) {
      AppLogger.w('Error checking location service status: $e', tag: 'Permissions', error: e);
      return true; // Assume enabled on platforms that don't support it
    }
  }
}
