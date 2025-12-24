import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fylooo/core/logging/app_logger.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissions {
  /// `permission_handler` throws if multiple permission dialogs/requests are
  /// started concurrently. This guard serializes permission requests app-wide.
  static Completer<void>? _permissionRequestInFlight;

  static Future<T> runGuarded<T>(Future<T> Function() action) async {
    // Wait for any in-flight permission request.
    while (_permissionRequestInFlight != null) {
      await _permissionRequestInFlight!.future;
    }
    final completer = Completer<void>();
    _permissionRequestInFlight = completer;
    try {
      return await action();
    } finally {
      _permissionRequestInFlight = null;
      completer.complete();
    }
  }

  /// Permissions required specifically for starting a temporary/local-only hotspot.
  ///
  /// On Android 13+ this is generally `NEARBY_WIFI_DEVICES`. We intentionally do
  /// not request Location here so app entry and hotspot use don't force it.
  ///
  /// Note: Other features (like reading Wi‑Fi SSID) may still require Location;
  /// use [requestNetworkPermissions] for those flows.
  static Future<bool> requestTemporaryHotspotPermissions() async {
    if (kIsWeb) return true;

    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    return runGuarded(() async {
      try {
        final status = await Permission.nearbyWifiDevices.status;
        if (status.isGranted) return true;

        final result = await Permission.nearbyWifiDevices.request();
        return result.isGranted;
      } catch (e) {
        // Permission not available on this Android version/device.
        AppLogger.d(
          'Nearby WiFi Devices permission not available: $e',
          tag: 'Permissions',
        );
        return true;
      }
    });
  }

  static Future<bool> requestNetworkPermissions() async {
    return runGuarded(() async {
      if (kIsWeb) {
        return true;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _requestAndroidPermissions();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _requestIOSPermissions();
      }
      return true;
    });
  }

  static Future<bool> _requestAndroidPermissions() async {
    // Request required permissions together to avoid overlapping requests.
    try {
      final statuses = await <Permission>[
        Permission.location,
        Permission.nearbyWifiDevices,
      ].request();

      final locationStatus = statuses[Permission.location];
      if (locationStatus == null || !locationStatus.isGranted) {
        return false;
      }

      final nearbyStatus = statuses[Permission.nearbyWifiDevices];
      if (nearbyStatus != null) {
        if (!nearbyStatus.isGranted) {
          if (nearbyStatus.isPermanentlyDenied) {
            AppLogger.w(
              'Nearby devices permission permanently denied. User can enable in settings if needed.',
              tag: 'Permissions',
            );
          }
        } else {
          AppLogger.i('Nearby devices permission granted', tag: 'Permissions');
        }
      }
    } catch (e) {
      // Fall back for devices/Android versions where nearbyWifiDevices isn't available.
      AppLogger.d(
        'Batch permission request failed, falling back to location-only: $e',
        tag: 'Permissions',
      );
      final locationStatus = await Permission.location.status;
      if (!locationStatus.isGranted) {
        final requestResult = await Permission.location.request();
        if (!requestResult.isGranted) return false;
      }
    }

    // Permissions may be granted but Location Services can still be disabled.
    // Return whether the app can reliably read Wi‑Fi SSID / do discovery.
    final serviceEnabled = await isLocationServiceEnabled();
    return serviceEnabled;
  }

  static Future<bool> _requestIOSPermissions() async {
    try {
      final locationStatus = await Permission.locationWhenInUse.status;

      if (locationStatus.isGranted) {
        return true;
      }

      if (locationStatus.isPermanentlyDenied) {
        return false;
      }

      final requestResult = await Permission.locationWhenInUse.request();
      if (!requestResult.isGranted) return false;

      // If granted, also reflect whether Location Services are enabled.
      final serviceEnabled = await isLocationServiceEnabled();
      return serviceEnabled;
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
