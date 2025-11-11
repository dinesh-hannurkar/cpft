import 'dart:io';
import 'package:flutter/services.dart';

/// Platform-specific helper for multicast operations
class MulticastPlatformHelper {
  static const MethodChannel _channel = MethodChannel('com.example.cpft/multicast');

  /// Acquire multicast lock on Android
  /// This is required for multicast packets to be received on Android
  static Future<bool> acquireMulticastLock() async {
    if (!Platform.isAndroid) {
      print('[MulticastPlatformHelper] Not on Android, skipping multicast lock');
      return true;
    }

    try {
      print('[MulticastPlatformHelper] Acquiring Android multicast lock...');
      final result = await _channel.invokeMethod('acquireMulticastLock');
      print('[MulticastPlatformHelper] Multicast lock acquired: $result');
      return result == true;
    } catch (e) {
      print('[MulticastPlatformHelper] Error acquiring multicast lock: $e');
      return false;
    }
  }

  /// Release multicast lock on Android
  static Future<bool> releaseMulticastLock() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      print('[MulticastPlatformHelper] Releasing Android multicast lock...');
      final result = await _channel.invokeMethod('releaseMulticastLock');
      print('[MulticastPlatformHelper] Multicast lock released: $result');
      return result == true;
    } catch (e) {
      print('[MulticastPlatformHelper] Error releasing multicast lock: $e');
      return false;
    }
  }
}
