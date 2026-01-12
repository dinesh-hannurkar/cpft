
import 'dart:io';
import 'native_socket.dart';
import 'linux_socket.dart';
import 'windows_socket.dart';
import 'macos_socket.dart';

class NativeSocketFactory {
  static NativeSocket create() {
    if (Platform.isLinux) {
      return LinuxSocket();
    } else if (Platform.isWindows) {
      return WindowsSocket();
    } else if (Platform.isMacOS) {
      return MacosSocket();
    } else {
      // TODO: Implement native sockets for mobile platforms.
      throw UnsupportedError('Platform not supported');
    }
  }
}
