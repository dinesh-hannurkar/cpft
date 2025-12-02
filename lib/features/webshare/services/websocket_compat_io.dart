import 'dart:async';
import 'dart:io' as io;

typedef WsOnData = void Function(dynamic data);

class WsClient {
  final io.WebSocket _socket;
  WsClient._(this._socket);

  static Future<WsClient> connect(String url, {Duration? timeout}) {
    final future = io.WebSocket.connect(url).then((s) => WsClient._(s));
    return timeout != null ? future.timeout(timeout) : future;
  }

  void add(String data) => _socket.add(data);

  StreamSubscription listen(
    WsOnData onData, {
    void Function()? onDone,
    void Function(Object error)? onError,
  }) {
    return _socket.listen(onData, onDone: onDone, onError: onError);
  }

  void close() {
    try {
      _socket.close();
    } catch (_) {}
  }
}
