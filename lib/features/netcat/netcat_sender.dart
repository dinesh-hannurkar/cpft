import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class NetcatSender {
  final String ip;
  final int port;
  final File file;
  final String filename;
  final int fileSize;
  final String transferId;
  final StreamController<double> _progressController = StreamController<double>.broadcast();

  Stream<double> get progress => _progressController.stream;

  NetcatSender({
    required this.ip,
    required this.port,
    required this.file,
    required this.filename,
    required this.fileSize,
    required this.transferId,
  });

  Future<void> start() async {
    Socket? socket;
    try {
      debugPrint('[Netcat] Connecting to $ip:$port');
      socket = await Socket.connect(ip, port);
      debugPrint('[Netcat] Connected. Sending file offer...');
      final offer = {'filename': filename, 'size': fileSize, 'transferId': transferId};
      socket.writeln(jsonEncode(offer));
      await socket.flush();

      // Wait for the receiver to accept the offer
      await socket.transform(utf8.decoder).transform(LineSplitter()).first;

      debugPrint('[Netcat] Offer accepted. Sending file...');
      int bytesSent = 0;
      final stream = file.openRead();
      await for (final chunk in stream) {
        socket.add(chunk);
        bytesSent += chunk.length;
        _progressController.add(bytesSent / fileSize);
      }
      await socket.flush();
      debugPrint('[Netcat] File sent successfully.');
    } catch (e) {
      debugPrint('[Netcat] Sender error: $e');
      rethrow;
    } finally {
      await socket?.close();
      _progressController.close();
    }
  }
}
