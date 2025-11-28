import 'dart:io';
import 'package:cpft/core/logging/app_logger.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class NetworkUtils {
  /// Returns true if the given IP looks like an iOS Personal Hotspot IP.
  static bool _isIosHotspotIp(String ip) {
    try {
      final parts = ip.split('.');
      if (parts.length != 4) return false;
      final first = int.parse(parts[0]);
      final second = int.parse(parts[1]);
      final third = int.parse(parts[2]);

      // Most common iOS hotspot subnet
      if (first == 172 && second == 20 && third == 10) return true; // 172.20.10.x

      // Some iOS variants use 10.0.x.x for hotspot. Heuristic: third octet small.
      if (first == 10 && second == 0 && third <= 2) return true; // 10.0.0-2.x

      return false;
    } catch (_) {
      return false;
    }
  }

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
        // Common WiFi interface names, including hotspot (ap0 on Android) and
        // iOS personal hotspot bridge interface (bridge100)
        if (name.startsWith('wlan') ||
            name.startsWith('en') ||
            name.startsWith('eth') ||
            name.startsWith('ap') ||
            name.startsWith('bridge')) {
          wifiInterfaces.add(iface);
        } else {
          otherInterfaces.add(iface);
        }
      }

      // First try WiFi interfaces
      // If any address looks like iOS Personal Hotspot, prefer returning that immediately
      for (final iface in wifiInterfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && _isValidLanAddress(addr.address)) {
            if (Platform.isIOS && _isIosHotspotIp(addr.address)) {
              AppLogger.d('[NetworkUtils] Prefer iOS hotspot IP on ${iface.name}: ${addr.address}', tag: 'Network');
              return addr.address;
            }
          }
        }
      }

      for (final iface in wifiInterfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && _isValidLanAddress(addr.address)) {
            AppLogger.d('[NetworkUtils] Using WiFi interface ${iface.name}: ${addr.address}', tag: 'Network');
            return addr.address;
          }
        }
      }

      // Don't fall back to other interfaces (mobile data) - return null instead
      // This ensures we only show as connected when on actual WiFi/LAN
      AppLogger.d('[NetworkUtils] No WiFi interface with valid LAN address found', tag: 'Network');
      return null;
    } catch (e) {
      AppLogger.w('[NetworkUtils] Error getting LAN IPv4: $e', tag: 'Network', error: e);
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

      if (first == 192 && second == 168) return true; // 192.168.x.x
      if (first == 172 && second >= 16 && second <= 31) return true; // 172.16-31.x.x
      if (first == 10) return true; // 10.x.x.x

      // Reject everything else including:
      // 100.x.x.x (carrier-grade NAT)
      // 169.254.x.x (link-local - indicates no DHCP)
      // Any other range is likely mobile/carrier network
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Get the current WiFi SSID (network name).
  static Future<String?> getWifiName() async {
    try {
      // First check if we have a valid WiFi/LAN IP
      // This ensures we're not on mobile data
      final lanIp = await getLanIPv4();
      if (lanIp == null) {
        AppLogger.d('No valid LAN IP found - not on WiFi', tag: 'Network');
        return 'Not Connected';
      }

      // On iOS, if we detect Personal Hotspot IP range, report accordingly
      if (Platform.isIOS) {
        final isHotspot = _isIosHotspotIp(lanIp);
        if (isHotspot) {
          AppLogger.d('Detected iOS Personal Hotspot - reporting as hotspot', tag: 'Network');
          return 'Personal Hotspot';
        }
      }

      // On Android 10+ location permission (fine + precise) is required for SSID
      if (Platform.isAndroid) {
        final status = await Permission.location.status;
        if (!status.isGranted) {
          final req = await Permission.location.request();
          if (!req.isGranted) {
            AppLogger.w('Android location not granted; cannot read SSID', tag: 'Network');
            return await _fallbackNetworkName();
          }
        }
      }

      final networkInfo = NetworkInfo();
      final wifiName = await networkInfo.getWifiName();
      AppLogger.d('WiFi name retrieved: $wifiName', tag: 'Network');
      if (wifiName != null && wifiName.trim().isNotEmpty && wifiName != 'unknown ssid') {
        return wifiName.trim();
      }
    } catch (e) {
      AppLogger.w('Error getting WiFi name: $e', tag: 'Network', error: e);
      // WiFi name access failed (likely iOS restrictions), fall back to IP
    }
    return await _fallbackNetworkName();
  }

  static Future<String> _fallbackNetworkName() async {
    try {
      final ip = await getLanIPv4();
      if (ip != null) {
        if (Platform.isIOS && _isIosHotspotIp(ip)) return 'Personal Hotspot';
        return 'Local ($ip)';
      }
    } catch (_) {}
    return 'Not Connected';
  }

  /// Check if the current network connection is an iOS Personal Hotspot
  /// based on the IP address range (typically 172.20.10.x)
  static Future<bool> isIosPersonalHotspot() async {
    if (!Platform.isIOS) return false;
    
    try {
      final ip = await getLanIPv4();
      if (ip == null) return false;

      final isHotspot = _isIosHotspotIp(ip);
      if (isHotspot) {
        AppLogger.d('[NetworkUtils] Detected iOS Personal Hotspot: $ip', tag: 'Network');
      }
      return isHotspot;
    } catch (e) {
      AppLogger.w('[NetworkUtils] Error checking iOS hotspot: $e', tag: 'Network', error: e);
      return false;
    }
  }
}
