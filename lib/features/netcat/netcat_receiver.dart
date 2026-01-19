
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/sockets/native_socket.dart';
import '../../core/sockets/native_socket_factory.dart';

class NetcatReceiver {
  final int port;
  final String saveDirectory;
  NativeSocket? _serverSocket;
  bool _listening = false;
  final StreamController<Map<String, dynamic>> _progressController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _completionController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get progress => _progressController.stream;
  Stream<Map<String, dynamic>> get completion => _completionController.stream;

  final Map<String, Completer<_PendingTransfer>> _transferCompleters = {};

  NetcatReceiver({required this.port, required this.saveDirectory});

  Future<void> start() async {
    _serverSocket = NativeSocketFactory.create();
    await _serverSocket!.bind(SocketAddress('0.0.0.0', port));
    await _serverSocket!.listen(5);
    _listening = true;
    debugPrint('[Netcat] Receiver listening on $port with native socket');
    _listenForConnections();
  }

  void _listenForConnections() async {
    while (_listening) {
      try {
        final clientSocket = await _serverSocket!.accept();
        _handleConnection(clientSocket);
      } catch (e) {
        if (_listening) {
          debugPrint('[Netcat] Error accepting connection: $e');
        }
      }
    }
  }

  void _handleConnection(NativeSocket socket) async {
    try {
      final buffer = <int>[];
      while (true) {
        final data = await socket.read(1024);
        if (data.isEmpty) break;
        buffer.addAll(data);
        final newlineIndex = buffer.indexOf(10); // '\n'
        if (newlineIndex != -1) {
          final offerLine = utf8.decode(buffer.sublist(0, newlineIndex));
          final offer = jsonDecode(offerLine);
          final transferId = offer['transferId'] as String;
          final fileSize = offer['size'] as int;
          final remainingData = buffer.sublist(newlineIndex + 1);

          final pending = _PendingTransfer(
            socket: socket,
            fileSize: fileSize,
            remainingData: remainingData,
          );

          if (!_transferCompleters.containsKey(transferId)) {
            _transferCompleters[transferId] = Completer<_PendingTransfer>();
          }
          if (!_transferCompleters[transferId]!.isCompleted) {
            _transferCompleters[transferId]!.complete(pending);
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('[Netcat] Error handling connection: $e');
      await socket.close();
    }
  }

  void acceptFile(String transferId, String filePath, int fileSize) async {
    if (!_transferCompleters.containsKey(transferId)) {
      _transferCompleters[transferId] = Completer<_PendingTransfer>();
    }

    _PendingTransfer? pending;
    try {
      pending = await _transferCompleters[transferId]!.future.timeout(
        const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint('[Netcat] Timeout waiting for connection: $e');
      _transferCompleters.remove(transferId);
      return;
    }

    _transferCompleters.remove(transferId);

    final socket = pending.socket;
    final file = File(filePath);
    final sink = file.openWrite();
    int bytesReceived = 0;

    try {
      await socket.write(utf8.encode('accept\n'));

      sink.add(pending.remainingData);
      bytesReceived += pending.remainingData.length;

      while (bytesReceived < fileSize) {
        final data = await socket.read(65536);
        if (data.isEmpty) break;
        sink.add(data);
        bytesReceived += data.length;

        _progressController.add({
          'transferId': transferId,
          'totalSize': fileSize,
          'progress': bytesReceived / fileSize,
          'path': filePath,
        });
      }

      await sink.close();
      debugPrint('[Netcat] File received successfully: $filePath');
      _completionController.add({
        'transferId': transferId,
        'path': filePath,
        'size': fileSize,
      });
    } catch (e) {
      debugPrint('[Netcat] Error receiving file: $e');
      await sink.close();
    } finally {
      await socket.close();
    }
  }

  void stop() {
    _listening = false;
    _serverSocket?.close();
    _progressController.close();
    _completionController.close();
    for (final completer in _transferCompleters.values) {
      if (completer.isCompleted) {
        completer.future.then((pending) => pending.socket.close());
      }
    }
    _transferCompleters.clear();
  }
}

class _PendingTransfer {
  final NativeSocket socket;
  final int fileSize;
  final List<int> remainingData;

  _PendingTransfer({
    required this.socket,
    required this.fileSize,
    required this.remainingData,
  });
}
