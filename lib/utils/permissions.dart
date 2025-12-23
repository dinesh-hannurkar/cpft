import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fylooo/core/logging/app_logger.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissions {
  static bool _isRequestingPermissions = false;
  static Future<bool> requestNetworkPermissions() async {
    if (_isRequestingPermissions) {
      await Future.delayed(const Duration(milliseconds: 500));
      return await checkLocationPermission();
    }

    _isRequestingPermissions = true;
    try {
      if (kIsWeb) {
        return true;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _requestAndroidPermissions();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _requestIOSPermissions();
      }
      return true;
    } finally {
      _isRequestingPermissions = false;
    }
  }

  static Future<bool> _requestAndroidPermissions() async {
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      AppLogger.w(
        'Location services disabled on device. User must enable in Settings.',
        tag: 'Permissions',
      );
      AppLogger.w(
        'Prompt user: Enable Location in device Settings.',
        tag: 'Permissions',
      );
      return false;
    }

    final locationStatus = await Permission.location.status;

    if (!locationStatus.isGranted) {
      final requestResult = await Permission.location.request();

      if (!requestResult.isGranted) {
        return false;
      }
    }

    try {
      final nearbyDevicesStatus = await Permission.nearbyWifiDevices.status;

      if (!nearbyDevicesStatus.isGranted) {
        final nearbyRequestResult = await Permission.nearbyWifiDevices
            .request();
        if (!nearbyRequestResult.isGranted) {
          // If permanently denied, guide user to settings
          if (nearbyRequestResult.isPermanentlyDenied) {
            AppLogger.w(
              'Nearby devices permission permanently denied. User can enable in settings if needed.',
              tag: 'Permissions',
            );
          }
        } else {
          AppLogger.i('Nearby devices permission granted', tag: 'Permissions');
        }
      } else {
        AppLogger.i(
          'Nearby devices permission already granted',
          tag: 'Permissions',
        );
      }
    } catch (e) {
      AppLogger.d(
        'Nearby devices permission not available on this device/Android version: $e',
        tag: 'Permissions',
      );
    }

    return true;
  }

  static Future<bool> _requestIOSPermissions() async {
    try {
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      final locationStatus = await Permission.locationWhenInUse.status;

      if (locationStatus.isGranted) {
        return true;
      }

      if (locationStatus.isPermanentlyDenied) {
        return false;
      }

      final requestResult = await Permission.locationWhenInUse.request();
      if (requestResult.isGranted) {
        return true;
      } else {
        return false;
      }
    } on PlatformException catch (e) {
      if (e.code == 'ERROR_ALREADY_REQUESTING_PERMISSIONS') {
        final currentStatus = await Permission.locationWhenInUse.status;
        return currentStatus.isGranted;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> openLocationSettings() async {
    if (kIsWeb) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return;
    }
    try {
      await openAppSettings();
    } catch (e) {
      AppLogger.w(
        'Error opening location settings: $e',
        tag: 'Permissions',
        error: e,
      );
    }
  }

  static Future<void> openSystemLocationSettings() async {
    if (kIsWeb) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        const platform = MethodChannel('cpft/settings');
        await platform.invokeMethod('openLocationSettings');
      } catch (e) {
        try {
          await openAppSettings();
        } catch (e2) {
          AppLogger.w(
            'Error opening app settings fallback: $e2',
            tag: 'Permissions',
            error: e2,
          );
        }
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await openAppSettings();
      } catch (e) {
        AppLogger.w(
          'Error opening iOS settings: $e',
          tag: 'Permissions',
          error: e,
        );
      }
    } else {
      AppLogger.d(
        'Location settings not applicable on desktop platforms',
        tag: 'Permissions',
      );
    }
  }

  static Future<bool> checkLocationPermission() async {
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
      return true;
    }
  }

  static Future<bool> isLocationServiceEnabled() async {
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
      return true;
    }
  }
}
