import 'dart:async';

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
      print('[HttpClient] Registering with $ip:$port...');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: dto.toJsonString(),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        print('[HttpClient] Successfully registered with $ip:$port');
        return true;
      } else if (response.statusCode == 412) {
        print('[HttpClient] Self-discovery ignored');
        return false;
      } else {
        print('[HttpClient] Registration failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('[HttpClient] Error registering with $ip:$port: $e');
      return false;
    }
  }

  /// Get device info from a specific IP
  Future<InfoDto?> getDeviceInfo(String ip, int port) async {
    try {
      final url = Uri.parse('http://$ip:$port/info?fingerprint=$fingerprint');
      print('[HttpClient] Fetching info from $ip:$port...');

      final response = await http.get(url).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final dto = InfoDto.fromJsonString(response.body);
        print('[HttpClient] Got info from ${dto.alias}');
        return dto;
      } else {
        print('[HttpClient] Get info failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('[HttpClient] Error getting info from $ip:$port: $e');
      return null;
    }
  }
}
