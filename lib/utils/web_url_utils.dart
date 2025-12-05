import 'package:flutter/foundation.dart';

/// Utility class for handling web-specific URL parameters
class WebUrlUtils {
  /// Base URL for the hosted web app
  static const String webBaseUrl = 'https://cpft-bf8a0.web.app';

  /// Build a share URL for a given code/room id
  static String shareUrlForRoom(String roomId) {
    return '$webBaseUrl/share?room=$roomId';
  }
  /// Get URL query parameters on web
  static Map<String, String> getQueryParameters() {
    if (!kIsWeb) return {};

    try {
      // Web-specific import for URL handling
      return Uri.base.queryParameters;
    } catch (e) {
      return {};
    }
  }

  /// Get a specific query parameter value
  static String? getQueryParameter(String key) {
    return getQueryParameters()[key];
  }

  /// Check if current URL has a room parameter
  static String? getRoomIdFromUrl() {
    return getQueryParameter('room');
  }
}