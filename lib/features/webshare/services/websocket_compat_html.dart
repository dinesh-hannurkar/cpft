// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

typedef WsOnData = void Function(dynamic data);

class WsClient {
  final html.WebSocket _socket;
  StreamSubscription<html.MessageEvent>? _msgSub;
  StreamSubscription<html.Event>? _openSub;
  StreamSubscription<html.Event>? _errorSub;
  StreamSubscription<html.Event>? _closeSub;

  WsClient._(this._socket);

  static Future<WsClient> connect(String url, {Duration? timeout}) async {
    final completer = Completer<WsClient>();
    try {
      final ws = html.WebSocket(url);
      ws.binaryType = 'arraybuffer';
      void handleOpen(html.Event _) {
        completer.complete(WsClient._(ws));
      }

      void handleError(html.Event _) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('WebSocket connection failed'));
        }
      }

      ws.onOpen.first.then(handleOpen);
      ws.onError.first.then(handleError);

      return timeout != null
          ? completer.future.timeout(timeout)
          : completer.future;
    } catch (e) {
      return Future.error(e);
    }
  }

  void add(String data) => _socket.send(data);

  StreamSubscription listen(
    WsOnData onData, {
    void Function()? onDone,
    void Function(Object error)? onError,
  }) {
    _msgSub = _socket.onMessage.listen((event) {
      onData(event.data);
    });
    _closeSub = _socket.onClose.listen((_) {
      if (onDone != null) onDone();
    });
    _errorSub = _socket.onError.listen((_) {
      if (onError != null) onError(StateError('WebSocket error'));
    });

    return _HtmlCompositeSubscription([
      _msgSub!,
      _closeSub!,
      _errorSub!,
    ]);
  }

  void close() {
    try {
      _socket.close();
    } catch (_) {}
    _msgSub?.cancel();
    _openSub?.cancel();
    _errorSub?.cancel();
    _closeSub?.cancel();
  }
}

class _HtmlCompositeSubscription implements StreamSubscription {
  final List<StreamSubscription> _subs;
  _HtmlCompositeSubscription(this._subs);

  @override
  Future<void> cancel() async {
    for (final s in _subs) {
      try {
        await s.cancel();
      } catch (_) {}
    }
  }

  @override
  bool get isPaused => _subs.any((s) => s.isPaused);

  @override
  void onData(void Function(dynamic data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {
    for (final s in _subs) {
      s.pause(resumeSignal);
    }
  }

  @override
  void resume() {
    for (final s in _subs) {
      s.resume();
    }
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) async {
    await Future.wait(_subs.map((s) => s.asFuture()));
    return (futureValue as E);
  }
}
