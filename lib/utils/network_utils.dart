import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class NetworkUtils {
  /// Try to find a LAN IPv4 address.
  static Future<String?> getLanIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Get the current WiFi SSID (network name).
  static Future<String?> getWifiName() async {
    try {
      // On Android 10+ location permission (fine + precise) is required for SSID
      if (Platform.isAndroid) {
        final status = await Permission.location.status;
        if (!status.isGranted) {
          final req = await Permission.location.request();
          if (!req.isGranted) {
            print('Android location not granted; cannot read SSID');
            return await _fallbackNetworkName();
          }
        }
      }

      final networkInfo = NetworkInfo();
      final wifiName = await networkInfo.getWifiName();
      print('WiFi name retrieved: $wifiName');
      if (wifiName != null && wifiName.trim().isNotEmpty && wifiName != 'unknown ssid') {
        return wifiName.trim();
      }
    } catch (e) {
      print('Error getting WiFi name: $e');
      // WiFi name access failed (likely iOS restrictions), fall back to IP
    }
    return await _fallbackNetworkName();
  }

  static Future<String> _fallbackNetworkName() async {
    try {
      final ip = await getLanIPv4();
      if (ip != null) return 'Local ($ip)';
    } catch (_) {}
    return 'Connected';
  }
}
