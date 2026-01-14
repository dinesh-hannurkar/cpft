import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

/// Service to manage performance optimizations on Android
/// Prevents aggressive power saving during file transfers
class WiFiPerformanceService {
  static const _channel = MethodChannel('com.omnity.fylooo/wifi_performance');

  static bool _isWifiLockAcquired = false;
  static bool _isWakeLockAcquired = false;
  static bool _isPerformanceModeEnabled = false;

  /// Acquire all performance optimizations for transfers
  /// This is the main method to call at the start of a transfer
  static Future<void> acquireAllOptimizations() async {
    if (!Platform.isAndroid) {
      debugPrint('[WiFiPerformance] Skipping optimizations - not Android');
      return;
    }

    debugPrint('[WiFiPerformance] 🔄 Acquiring all optimizations...');

    final wifiResult = await acquireWifiLock();
    debugPrint(
      '[WiFiPerformance] WiFi lock: ${wifiResult ? "✅ Success" : "❌ Failed"}',
    );

    final wakeResult = await acquireWakeLock();
    debugPrint(
      '[WiFiPerformance] Wake lock: ${wakeResult ? "✅ Success" : "❌ Failed"}',
    );

    final perfResult = await enableSustainedPerformance();
    debugPrint(
      '[WiFiPerformance] Performance mode: ${perfResult ? "✅ Success" : "❌ Failed"}',
    );

    debugPrint('[WiFiPerformance] 🏁 All optimizations complete');
  }

  /// Release all performance optimizations
  /// Call this at the end of a transfer
  static Future<void> releaseAllOptimizations() async {
    if (!Platform.isAndroid) return;

    await releaseWifiLock();
    await releaseWakeLock();
    await disableSustainedPerformance();
  }

  /// Acquire high-performance WiFi lock
  /// Prevents WiFi from going to sleep during transfers
  static Future<bool> acquireWifiLock() async {
    if (_isWifiLockAcquired) return true;

    try {
      final result = await _channel.invokeMethod<bool>('acquireWifiLock');
      _isWifiLockAcquired = result ?? false;
      return _isWifiLockAcquired;
    } catch (e) {
      print('[WiFiPerformance] Failed to acquire WiFi lock: $e');
      return false;
    }
  }

  /// Release high-performance WiFi lock
  static Future<void> releaseWifiLock() async {
    if (!_isWifiLockAcquired) return;

    try {
      await _channel.invokeMethod('releaseWifiLock');
      _isWifiLockAcquired = false;
    } catch (e) {
      print('[WiFiPerformance] Failed to release WiFi lock: $e');
    }
  }

  /// Acquire partial wake lock
  /// Keeps CPU awake during transfers (allows screen off)
  static Future<bool> acquireWakeLock() async {
    if (_isWakeLockAcquired) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'acquireTransferWakeLock',
      );
      _isWakeLockAcquired = result ?? false;
      return _isWakeLockAcquired;
    } catch (e) {
      print('[WiFiPerformance] Failed to acquire wake lock: $e');
      return false;
    }
  }

  /// Release partial wake lock
  static Future<void> releaseWakeLock() async {
    if (!_isWakeLockAcquired) return;

    try {
      await _channel.invokeMethod('releaseTransferWakeLock');
      _isWakeLockAcquired = false;
    } catch (e) {
      print('[WiFiPerformance] Failed to release wake lock: $e');
    }
  }

  /// Enable sustained performance mode
  /// Hints to system to prioritize performance over battery
  static Future<bool> enableSustainedPerformance() async {
    if (_isPerformanceModeEnabled) return true;

    try {
      final result = await _channel.invokeMethod<bool>(
        'enableSustainedPerformance',
      );
      _isPerformanceModeEnabled = result ?? false;
      return _isPerformanceModeEnabled;
    } catch (e) {
      print('[WiFiPerformance] Failed to enable sustained performance: $e');
      return false;
    }
  }

  /// Disable sustained performance mode
  static Future<void> disableSustainedPerformance() async {
    if (!_isPerformanceModeEnabled) return;

    try {
      await _channel.invokeMethod('disableSustainedPerformance');
      _isPerformanceModeEnabled = false;
    } catch (e) {
      print('[WiFiPerformance] Failed to disable sustained performance: $e');
    }
  }

  /// Request battery optimization exemption
  /// Opens system settings for user to grant exemption
  static Future<bool> requestBatteryOptimizationExemption() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestBatteryOptimizationExemption',
      );
      return result ?? false;
    } catch (e) {
      print(
        '[WiFiPerformance] Failed to request battery optimization exemption: $e',
      );
      return false;
    }
  }

  /// Check if app is exempt from battery optimization
  static Future<bool> checkBatteryOptimizationStatus() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'checkBatteryOptimizationStatus',
      );
      return result ?? false;
    } catch (e) {
      print(
        '[WiFiPerformance] Failed to check battery optimization status: $e',
      );
      return false;
    }
  }

  /// Legacy method - use acquireWifiLock() instead
  @Deprecated('Use acquireWifiLock() instead')
  static Future<bool> acquirePerformanceLock() => acquireWifiLock();

  /// Legacy method - use releaseWifiLock() instead
  @Deprecated('Use releaseWifiLock() instead')
  static Future<void> releasePerformanceLock() => releaseWifiLock();

  /// Check if WiFi lock is currently held
  static bool get isWifiLockAcquired => _isWifiLockAcquired;

  /// Check if wake lock is currently held
  static bool get isWakeLockAcquired => _isWakeLockAcquired;

  /// Check if performance mode is enabled
  static bool get isPerformanceModeEnabled => _isPerformanceModeEnabled;
}
