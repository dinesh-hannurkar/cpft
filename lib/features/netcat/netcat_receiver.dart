import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class NetcatReceiver {
  final int port;
  final String saveDirectory;
  ServerSocket? _server;
  final StreamController<Map<String, dynamic>> _progressController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get progress => _progressController.stream;

  final StreamController<Map<String, dynamic>> _completionController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get completion => _completionController.stream;

  NetcatReceiver({
    required this.port,
    required this.saveDirectory,
  });

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    debugPrint('[Netcat] Receiver listening on $port');
    _server!.listen(_handleConnection);
  }

  final Map<String, Socket> _pendingSockets = {};

  void _handleConnection(Socket socket) {
    socket.transform(utf8.decoder).transform(LineSplitter()).listen(
      (line) {
        final offer = jsonDecode(line);
        final transferId = offer['transferId'];
        _pendingSockets[transferId] = socket;
      },
      onError: (error) {
        debugPrint('[Netcat] Receiver error: $error');
        socket.close();
      },
      onDone: () {
        socket.close();
      },
    );
  }

  void acceptFile(String transferId, String filePath, int fileSize) {
    final socket = _pendingSockets.remove(transferId);
    if (socket == null) {
      debugPrint('[Netcat] No pending socket for transfer ID: $transferId');
      return;
    }

    final file = File(filePath);
    final sink = file.openWrite();
    int bytesReceived = 0;

    socket.writeln('accept');

    socket.listen(
      (data) {
        sink.add(data);
        bytesReceived += data.length;
        _progressController.add({
          'transferId': transferId,
          'totalSize': fileSize,
          'progress': bytesReceived / fileSize,
          'path': filePath,
        });
      },
      onDone: () async {
        await sink.close();
        debugPrint('[Netcat] File received successfully.');
        _completionController.add({
          'transferId': transferId,
          'path': filePath,
          'size': fileSize,
        });
        await socket.close();
      },
      onError: (error) async {
        debugPrint('[Netcat] Receiver error: $error');
        await sink.close();
        await socket.close();
      },
    );
  }

  void stop() {
    _server?.close();
    _progressController.close();
    _completionController.close();
  }
}
