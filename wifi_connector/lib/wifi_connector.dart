import 'dart:async';

import 'package:flutter/services.dart';

class WifiConnector {
  static const MethodChannel _channel =
      const MethodChannel('wifi_connector');

  static Future<List<String>> scan() async {
    final List<dynamic> networks = await _channel.invokeMethod('scan');
    return networks.cast<String>();
  }

  static Future<bool> connect(String ssid, String password) async {
    return await _channel.invokeMethod('connect', {
      'ssid': ssid,
      'password': password,
    });
  }
}
