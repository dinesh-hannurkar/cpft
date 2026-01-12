
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'windows_ffi.dart' as ffi;

class WindowsSocketManager {
  static final WindowsSocketManager _instance = WindowsSocketManager._internal();
  factory WindowsSocketManager() => _instance;

  WindowsSocketManager._internal() {
    _initialize();
  }

  void _initialize() {
    final wsaData = calloc<ffi.WSAData>();
    final result = ffi.wsaStartup(0x0202, wsaData);
    calloc.free(wsaData);
    if (result != 0) {
      throw 'WSAStartup failed with error: $result';
    }
  }

  void cleanup() {
    ffi.wsaCleanup();
  }
}
