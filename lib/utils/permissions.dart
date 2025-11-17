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
    // Android WiFi SSID access requires location (fine or coarse depending on API level)
    final fine = await Permission.location.status;
    if (!fine.isGranted) {
      final req = await Permission.location.request();
      if (!req.isGranted) {
        print('Android fine location denied; SSID and discovery may be limited.');
        return false;
      }
    }

    // Coarse (for older patterns) - permission_handler maps both
    final coarse = await Permission.locationWhenInUse.status; // may mirror fine
    if (!coarse.isGranted) {
      final req2 = await Permission.locationWhenInUse.request();
      if (!req2.isGranted) {
        print('Android coarse/when-in-use location denied; continuing with fine only.');
      }
    }
    return true;
  }

  static Future<bool> _requestIOSPermissions() async {
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

  static Future<bool> checkLocationPermission() async {
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted;
  }
}
