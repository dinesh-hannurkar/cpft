import 'package:flutter/foundation.dart';

class WebUrlUtils {
  static const String webBaseUrl = 'https://cpft-bf8a0.web.app';

  static String shareUrlForRoom(String roomId) {
    return '$webBaseUrl/share?room=$roomId';
  }

  static Map<String, String> getQueryParameters() {
    if (!kIsWeb) return {};

    try {
      return Uri.base.queryParameters;
    } catch (e) {
      return {};
    }
  }

  static String? getQueryParameter(String key) {
    return getQueryParameters()[key];
  }

  static String? getRoomIdFromUrl() {
    return getQueryParameter('room');
  }
}
