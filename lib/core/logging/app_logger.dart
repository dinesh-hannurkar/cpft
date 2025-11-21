import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Centralized logging utility for the app.
/// Replace direct print calls with AppLogger methods.
class AppLogger {
  AppLogger._();

  static bool enableDebug = kDebugMode; // Only logs in release if explicitly enabled
  static bool verbose = false; // Toggle for extra noisy logs
  static String defaultTag = 'CPFT';

  static void d(String message, {String? tag}) {
    if (!enableDebug) return;
    developer.log(message, name: tag ?? defaultTag, level: 500);
  }

  static void i(String message, {String? tag}) {
    if (!enableDebug) return;
    developer.log(message, name: tag ?? defaultTag, level: 800);
  }

  static void w(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (!enableDebug) return;
    developer.log(message, name: tag ?? defaultTag, level: 900, error: error, stackTrace: stackTrace);
  }

  static void e(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    developer.log(message, name: tag ?? defaultTag, level: 1000, error: error, stackTrace: stackTrace);
  }

  static void v(String message, {String? tag}) {
    if (!enableDebug || !verbose) return;
    developer.log(message, name: tag ?? defaultTag, level: 400);
  }
}
