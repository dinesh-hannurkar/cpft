import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import '../models/multicast_dto.dart';

/// HTTP client for sending registration requests to discovered devices
class HttpDiscoveryClient {
  final String fingerprint;
  final String alias;
  final int port;
  final String deviceModel;

  HttpDiscoveryClient({
    required this.fingerprint,
    required this.alias,
    required this.port,
    required this.deviceModel,
  });

  /// Send registration to a discovered device
  Future<bool> registerWithDevice(String ip, int port) async {
    try {
      final dto = RegisterDto(
        alias: alias,
        fingerprint: fingerprint,
        port: this.port,
        deviceModel: deviceModel,
      );

      final url = Uri.parse('http://$ip:$port/register');
      debugPrint('[HttpClient] Registering with $ip:$port...');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: dto.toJsonString(),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        debugPrint('[HttpClient] Successfully registered with $ip:$port');
        return true;
      } else if (response.statusCode == 412) {
        debugPrint('[HttpClient] Self-discovery ignored');
        return false;
      } else {
        debugPrint('[HttpClient] Registration failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      // Provide more detailed error diagnostics for registration
      if (e is SocketException) {
        final errorCode = e.osError?.errorCode ?? 'unknown';
        final errorMessage = e.osError?.message ?? e.message;
        
        switch (errorCode) {
          case 113: // EHOSTUNREACH - No route to host
            debugPrint('[HttpClient] ❌ Cannot register - no route to host $ip:$port');
            break;
          case 111: // ECONNREFUSED - Connection refused
            debugPrint('[HttpClient] ❌ Registration refused by $ip:$port - device may not be running CPFT');
            break;
          case 110: // ETIMEDOUT - Connection timed out
            debugPrint('[HttpClient] ❌ Registration timeout to $ip:$port');
            break;
          default:
            debugPrint('[HttpClient] ❌ Socket error ($errorCode) during registration with $ip:$port: $errorMessage');
        }
      } else if (e is TimeoutException) {
        debugPrint('[HttpClient] ❌ Registration timeout with $ip:$port');
      } else {
        debugPrint('[HttpClient] ❌ Error registering with $ip:$port: $e');
      }
      return false;
    }
  }

  /// Get device info from a specific IP
  Future<InfoDto?> getDeviceInfo(String ip, int port) async {
    try {
      final url = Uri.parse('http://$ip:$port/info?fingerprint=$fingerprint');
      debugPrint('[HttpClient] Fetching info from $ip:$port...');

      final response = await http.get(url).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final dto = InfoDto.fromJsonString(response.body);
        debugPrint('[HttpClient] Got info from ${dto.alias}');
        return dto;
      } else {
        debugPrint('[HttpClient] Get info failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      // Provide more detailed error diagnostics
      if (e is SocketException) {
        final errorCode = e.osError?.errorCode ?? 'unknown';
        final errorMessage = e.osError?.message ?? e.message;
        
        switch (errorCode) {
          case 113: // EHOSTUNREACH - No route to host
            debugPrint('[HttpClient] ❌ No route to host $ip:$port - device may be offline or unreachable');
            debugPrint('[HttpClient] 💡 Check: Is the device on the same network? Is firewall blocking?');
            break;
          case 111: // ECONNREFUSED - Connection refused
            debugPrint('[HttpClient] ❌ Connection refused by $ip:$port - device may not be running CPFT');
            debugPrint('[HttpClient] 💡 Check: Is CPFT running on the target device?');
            break;
          case 110: // ETIMEDOUT - Connection timed out
            debugPrint('[HttpClient] ❌ Connection timeout to $ip:$port - network may be slow or device unreachable');
            break;
          case 101: // ENETUNREACH - Network unreachable
            debugPrint('[HttpClient] ❌ Network unreachable for $ip:$port - check network connectivity');
            break;
          default:
            debugPrint('[HttpClient] ❌ Socket error ($errorCode) connecting to $ip:$port: $errorMessage');
        }
      } else if (e is TimeoutException) {
        debugPrint('[HttpClient] ❌ Timeout connecting to $ip:$port - device may be slow to respond');
      } else {
        debugPrint('[HttpClient] ❌ Error getting info from $ip:$port: $e');
      }
      
      return null;
    }
  }
}
