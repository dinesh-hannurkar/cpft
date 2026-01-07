import 'dart:io'
    if (dart.library.html) 'package:fylooo/features/webshare/services/io_stub.dart';
import 'package:fylooo/core/logging/app_logger.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NetworkUtils {
  static const _wifiChannel = MethodChannel('com.omnity.fylooo/wifi');
  
  static Future<Map<String, dynamic>?> getWifiFrequency() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final result = await _wifiChannel.invokeMethod('getWifiFrequency');
      if (result is Map) {
        final freq = result['frequency'] as int?;
        final band = result['band'] as String?;
        AppLogger.d('WiFi Frequency: $freq MHz ($band)', tag: 'Network');
        return {'frequency': freq, 'band': band};
      }
    } catch (e) {
      AppLogger.w('Error getting WiFi frequency: $e', tag: 'Network', error: e);
    }
    return null;
  }
  
  static bool _isIosHotspotIp(String ip) {
    try {
      final parts = ip.split('.');
      if (parts.length != 4) return false;
      final first = int.parse(parts[0]);
      final second = int.parse(parts[1]);
      final third = int.parse(parts[2]);
      if (first == 172 && second == 20 && third == 10) {
        return true; // 172.20.10.x
      }
      if (first == 10 && second == 0 && third <= 2) return true; // 10.0.0-2.x
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getLanIPv4() async {
    if (kIsWeb) {
      AppLogger.d('Web platform: skipping LAN IPv4 detection', tag: 'Network');
      return null;
    }
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      final wifiInterfaces = <NetworkInterface>[];
      final otherInterfaces = <NetworkInterface>[];

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        final isWifiLike = name.startsWith('wlan') ||
            name.contains('wifi') ||
            name.contains('wi-fi') ||
            name.startsWith('en') ||
            name.startsWith('eth') ||
            name.startsWith('ap') ||
            name.startsWith('bridge') ||
            name.startsWith('wl');
        if (isWifiLike) {
          wifiInterfaces.add(iface);
        } else {
          otherInterfaces.add(iface);
        }
      }

      for (final iface in wifiInterfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && _isValidLanAddress(addr.address)) {
            if (!kIsWeb &&
                defaultTargetPlatform == TargetPlatform.iOS &&
                _isIosHotspotIp(addr.address)) {
              AppLogger.d(
                '[NetworkUtils] Prefer iOS hotspot IP on ${iface.name}: ${addr.address}',
                tag: 'Network',
              );
              return addr.address;
            }
          }
        }
      }

      for (final iface in wifiInterfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && _isValidLanAddress(addr.address)) {
            AppLogger.d(
              '[NetworkUtils] Using WiFi interface ${iface.name}: ${addr.address}',
              tag: 'Network',
            );
            return addr.address;
          }
        }
      }

      // Fallback: use any other interface with a valid private LAN address (e.g., Ethernet)
      for (final iface in otherInterfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && _isValidLanAddress(addr.address)) {
            AppLogger.d(
              '[NetworkUtils] Using non-WiFi interface ${iface.name}: ${addr.address}',
              tag: 'Network',
            );
            return addr.address;
          }
        }
      }

      AppLogger.d(
        '[NetworkUtils] No WiFi interface with valid LAN address found',
        tag: 'Network',
      );
      return null;
    } catch (e) {
      AppLogger.w(
        '[NetworkUtils] Error getting LAN IPv4: $e',
        tag: 'Network',
        error: e,
      );
    }
    return null;
  }

  static bool _isValidLanAddress(String ip) {
    try {
      final parts = ip.split('.');
      if (parts.length != 4) return false;

      final first = int.parse(parts[0]);
      final second = int.parse(parts[1]);

      if (first == 192 && second == 168) return true; // 192.168.x.x
      if (first == 172 && second >= 16 && second <= 31) {
        return true; // 172.16-31.x.x
      }
      if (first == 10) return true; // 10.x.x.x
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getWifiName() async {
    if (kIsWeb) {
      AppLogger.d(
        'Web platform: WiFi name not available; returning generic label',
        tag: 'Network',
      );
      return 'Web Browser';
    }
    try {
      final lanIp = await getLanIPv4();
      if (lanIp == null) {
        AppLogger.d('No valid LAN IP found - not on WiFi', tag: 'Network');
        return 'Not Connected';
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final isHotspot = _isIosHotspotIp(lanIp);
        if (isHotspot) {
          AppLogger.d(
            'Detected iOS Personal Hotspot - reporting as hotspot',
            tag: 'Network',
          );
          return 'Personal Hotspot';
        }
      }

      // On Android 10+ location permission is required for SSID
      // Don't request permission here - just check if it's granted
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.location.status;
        if (!status.isGranted) {
          AppLogger.d(
            'Android location not granted; using fallback network name',
            tag: 'Network',
          );
          return await _fallbackNetworkName();
        }
      }

      final networkInfo = NetworkInfo();
      final wifiName = await networkInfo.getWifiName();
      AppLogger.d('WiFi name retrieved: $wifiName', tag: 'Network');
      if (wifiName != null &&
          wifiName.trim().isNotEmpty &&
          wifiName != 'unknown ssid') {
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
        AppLogger.d(
          '[NetworkUtils] Fallback network name for IP: $ip on platform: ${defaultTargetPlatform.name}',
          tag: 'Network',
        );
        // Only check for iOS hotspot on iOS devices
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          if (_isIosHotspotIp(ip)) {
            AppLogger.d(
              '[NetworkUtils] iOS hotspot detected, returning Personal Hotspot',
              tag: 'Network',
            );
            return 'Personal Hotspot';
          }
        }
        AppLogger.d(
          '[NetworkUtils] Returning Local with IP: $ip',
          tag: 'Network',
        );
        return 'Local ($ip)';
      }
    } catch (e) {
      AppLogger.w(
        '[NetworkUtils] Error in fallback: $e',
        tag: 'Network',
        error: e,
      );
    }
    return 'Not Connected';
  }

  static Future<bool> isIosPersonalHotspot() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;

    try {
      final ip = await getLanIPv4();
      if (ip == null) return false;

      final isHotspot = _isIosHotspotIp(ip);
      if (isHotspot) {
        AppLogger.d(
          '[NetworkUtils] Detected iOS Personal Hotspot: $ip',
          tag: 'Network',
        );
      }
      return isHotspot;
    } catch (e) {
      AppLogger.w(
        '[NetworkUtils] Error checking iOS hotspot: $e',
        tag: 'Network',
        error: e,
      );
      return false;
    }
  }
}
