import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class NetworkUtils {
  /// Try to find a LAN IPv4 address, prioritizing WiFi interfaces for web sharing.
  static Future<String?> getLanIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);

      // Prioritize WiFi interfaces (typically named wlan0, wlan1, en0, en1, etc.)
      // over mobile data interfaces (typically named rmnet0, pdp_ip0, etc.)
      final wifiInterfaces = <NetworkInterface>[];
      final otherInterfaces = <NetworkInterface>[];

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        // Common WiFi interface names
        if (name.startsWith('wlan') || name.startsWith('en') || name.startsWith('eth')) {
          wifiInterfaces.add(iface);
        } else {
          otherInterfaces.add(iface);
        }
      }

      // First try WiFi interfaces
      for (final iface in wifiInterfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && _isValidLanAddress(addr.address)) {
            print('[NetworkUtils] Using WiFi interface ${iface.name}: ${addr.address}');
            return addr.address;
          }
        }
      }

      // Fall back to other interfaces if no WiFi found
      for (final iface in otherInterfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && _isValidLanAddress(addr.address)) {
            print('[NetworkUtils] Using interface ${iface.name}: ${addr.address}');
            return addr.address;
          }
        }
      }

      // Last resort: any non-loopback address
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            print('[NetworkUtils] Using fallback interface ${iface.name}: ${addr.address}');
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('[NetworkUtils] Error getting LAN IPv4: $e');
    }
    return null;
  }

  /// Check if an IP address is a valid LAN address (not mobile data)
  static bool _isValidLanAddress(String ip) {
    try {
      final parts = ip.split('.');
      if (parts.length != 4) return false;

      final first = int.parse(parts[0]);
      final second = int.parse(parts[1]);

      // Common LAN IP ranges:
      // 192.168.x.x (most common)
      // 172.16.x.x to 172.31.x.x
      // 10.x.x.x
      // 169.254.x.x (link-local/APIPA - but we'll allow it as fallback)

      if (first == 192 && second == 168) return true; // 192.168.x.x
      if (first == 172 && second >= 16 && second <= 31) return true; // 172.16-31.x.x
      if (first == 10) return true; // 10.x.x.x
      if (first == 169 && second == 254) return true; // 169.254.x.x (link-local)

      // Reject common mobile/carrier IP ranges that start with:
      // 100.x.x.x (carrier-grade NAT)
      // 25.x.x.x, 26.x.x.x, etc. (various carrier ranges)
      if (first == 100) return false; // Carrier-grade NAT

      return false; // Unknown range, be conservative
    } catch (_) {
      return false;
    }
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
