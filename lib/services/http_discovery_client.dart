import 'dart:async';
import 'dart:io';
import 'package:fylooo/core/logging/app_logger.dart';
import 'package:http/http.dart' as http;
import '../models/multicast_dto.dart';

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

  Future<bool> registerWithDevice(String ip, int port) async {
    try {
      final dto = RegisterDto(
        alias: alias,
        fingerprint: fingerprint,
        port: this.port,
        deviceModel: deviceModel,
      );

      final url = Uri.parse('http://$ip:$port/register');
      AppLogger.d('Registering with $ip:$port...', tag: 'HttpDisc');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: dto.toJsonString(),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        AppLogger.i('Successfully registered with $ip:$port', tag: 'HttpDisc');
        return true;
      } else if (response.statusCode == 412) {
        AppLogger.d('Self-discovery ignored ($ip)', tag: 'HttpDisc');
        return false;
      } else {
        AppLogger.w(
          'Registration failed: ${response.statusCode} ($ip:$port)',
          tag: 'HttpDisc',
        );
        return false;
      }
    } catch (e) {
      if (e is SocketException) {
        final errorCode = e.osError?.errorCode ?? 'unknown';

        switch (errorCode) {
          case 113: // EHOSTUNREACH - No route to host
            AppLogger.w(
              'Cannot register - no route to host $ip:$port',
              tag: 'HttpDisc',
            );
            break;
          case 111: // ECONNREFUSED - Connection refused
            AppLogger.w(
              'Registration refused by $ip:$port - device may not be running CPFT',
              tag: 'HttpDisc',
            );
            break;
          case 110: // ETIMEDOUT - Connection timed out
            AppLogger.w('Registration timeout to $ip:$port', tag: 'HttpDisc');
            break;
          default:
          // debugPrint('[HttpClient] ❌ Socket error ($errorCode) during registration with $ip:$port: $errorMessage');
        }
      } else if (e is TimeoutException) {
        AppLogger.w('Registration timeout with $ip:$port', tag: 'HttpDisc');
      } else {
        AppLogger.w(
          'Error registering with $ip:$port: $e',
          tag: 'HttpDisc',
          error: e,
        );
      }
      return false;
    }
  }

  /// Get device info from a specific IP
  Future<InfoDto?> getDeviceInfo(String ip, int port) async {
    try {
      final url = Uri.parse('http://$ip:$port/info?fingerprint=$fingerprint');
      final response = await http.get(url).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final dto = InfoDto.fromJsonString(response.body);
        AppLogger.d('Got info from ${dto.alias}', tag: 'HttpDisc');
        return dto;
      } else {
        AppLogger.w(
          'Get info failed: ${response.statusCode} ($ip:$port)',
          tag: 'HttpDisc',
        );
        return null;
      }
    } catch (e) {
      if (e is SocketException) {
        final errorCode = e.osError?.errorCode ?? 'unknown';
        switch (errorCode) {
          case 113: // EHOSTUNREACH - No route to host
            AppLogger.w(
              'Check host reachability / firewall for $ip:$port',
              tag: 'HttpDisc',
            );
            break;
          case 111: // ECONNREFUSED - Connection refused
            AppLogger.w(
              'Connection refused by $ip:$port - target may not run CPFT',
              tag: 'HttpDisc',
            );
            AppLogger.d(
              'Advise: ensure CPFT running on remote device',
              tag: 'HttpDisc',
            );
            break;
          case 110: // ETIMEDOUT - Connection timed out
            AppLogger.w(
              'Connection timeout to $ip:$port - network slow or unreachable',
              tag: 'HttpDisc',
            );
            break;
          case 101: // ENETUNREACH - Network unreachable
            AppLogger.w(
              'Network unreachable for $ip:$port - check connectivity',
              tag: 'HttpDisc',
            );
            break;
          default:
          // debugPrint('[HttpClient] ❌ Socket error ($errorCode) connecting to $ip:$port: $errorMessage');
        }
      } else if (e is TimeoutException) {
        // debugPrint('[HttpClient] ❌ Timeout connecting to $ip:$port - device may be slow to respond');
      } else {
        // debugPrint('[HttpClient] ❌ Error getting info from $ip:$port: $e');
      }
      return null;
    }
  }
}
