
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/sockets/native_socket.dart';
import '../../core/sockets/native_socket_factory.dart';

class NetcatSender {
  final String ip;
  final int port;
  final File file;
  final String filename;
  final int fileSize;
  final String transferId;
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();

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
    NativeSocket? socket;
    try {
      debugPrint('[Netcat] Connecting to $ip:$port with native socket');
      socket = NativeSocketFactory.create();
      await socket.connect(SocketAddress(ip, port));

      debugPrint('[Netcat] Connected. Sending file offer...');

      final offer = {
        'size': fileSize,
        'transferId': transferId,
      };
      // Add a newline for the receiver to delimit the header
      final offerString = jsonEncode(offer) + '\n';
      await socket.write(utf8.encode(offerString));


      // Wait for acceptance
      // The native socket read is blocking, so we'll read in a loop
      // until we get the acceptance message.
      final acceptanceBuffer = StringBuffer();
      while (true) {
        final data = await socket.read(1024);
        if (data.isEmpty) {
          throw Exception('Socket closed before acceptance received');
        }
        acceptanceBuffer.write(utf8.decode(data, allowMalformed: true));
        final content = acceptanceBuffer.toString();
        if (content.contains('accept')) {
          break;
        }
      }


      debugPrint('[Netcat] Received acceptance. Sending file...');

      // Use the high-performance native sendFile method
      await socket.sendFile(file, onProgress: (bytesSent) {
        _progressController.add(bytesSent / fileSize);
      });

      debugPrint(
        '[Netcat] File sent successfully. Total: ${fileSize / (1024 * 1024)} MB',
      );
    } catch (e) {
      debugPrint('[Netcat] Sender error: $e');
      rethrow;
    } finally {
      await socket?.close();
      _progressController.close();
    }
  }
}
