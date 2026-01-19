
import 'dart:io';

abstract class NativeSocket {
  Future<void> connect(SocketAddress address);
  Future<void> bind(SocketAddress address);
  Future<void> listen(int backlog);
  Future<NativeSocket> accept();
  Future<int> write(List<int> data);
  Future<List<int>> read(int length);
  Future<void> close();
  Future<void> sendFile(File file, {void Function(int bytesSent)? onProgress});
}

class SocketAddress {
  final String host;
  final int port;

  SocketAddress(this.host, this.port);
}
