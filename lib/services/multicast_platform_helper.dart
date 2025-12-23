import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MulticastPlatformHelper {
  static const MethodChannel _channel = MethodChannel(
    'com.omnity.fylooo/multicast',
  );
  static Future<bool> acquireMulticastLock() async {
    if (!Platform.isAndroid) {
      debugPrint(
        '[MulticastPlatformHelper] Not on Android, skipping multicast lock',
      );
      return true;
    }

    try {
      debugPrint(
        '[MulticastPlatformHelper] Acquiring Android multicast lock...',
      );
      final result = await _channel.invokeMethod('acquireMulticastLock');
      debugPrint('[MulticastPlatformHelper] Multicast lock acquired: $result');
      return result == true;
    } catch (e) {
      debugPrint(
        '[MulticastPlatformHelper] Error acquiring multicast lock: $e',
      );
      return false;
    }
  }

  static Future<bool> releaseMulticastLock() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      debugPrint(
        '[MulticastPlatformHelper] Releasing Android multicast lock...',
      );
      final result = await _channel.invokeMethod('releaseMulticastLock');
      debugPrint('[MulticastPlatformHelper] Multicast lock released: $result');
      return result == true;
    } catch (e) {
      debugPrint(
        '[MulticastPlatformHelper] Error releasing multicast lock: $e',
      );
      return false;
    }
  }
}
