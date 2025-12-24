import 'package:flutter/foundation.dart';

class WebUrlUtils {
  static const String webBaseUrl = 'https://fylooo.com';

  static String shareUrlForRoom(String roomId) {
    // return '$webBaseUrl/share?room=$roomId';
      return '$webBaseUrl/app/webshare?room=$roomId';
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
