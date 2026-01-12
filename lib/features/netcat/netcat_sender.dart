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
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();

  Stream<double> get progress => _progressController.stream;

  // Optimize buffer sizes for high-speed transfer
  static const int _socketBufferSize = 1 * 1024 * 1024; // 1MB socket buffer
  static const int _progressUpdateInterval =
      10 * 1024 * 1024; // Update every 10MB

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
    StreamSubscription? subscription;
    try {
      debugPrint('[Netcat] Connecting to $ip:$port');
      socket = await Socket.connect(ip, port);

      // Optimize socket buffers for high-speed transfer
      _optimizeSocketBuffers(socket);

      // Setup listener BEFORE sending the offer to catch fast responses
      final acceptanceCompleter = Completer<void>();
      final acceptanceBuffer = <int>[];

      subscription = socket.listen(
        (data) {
          debugPrint('[Netcat] Sender received data: ${data.length} bytes');
          if (!acceptanceCompleter.isCompleted) {
            acceptanceBuffer.addAll(data);
            final newlineIndex = acceptanceBuffer.indexOf(10); // '\n'
            if (newlineIndex != -1) {
              final acceptance = utf8
                  .decode(acceptanceBuffer.sublist(0, newlineIndex))
                  .trim();
              debugPrint('[Netcat] Received acceptance string: "$acceptance"');
              if (acceptance == 'accept') {
                acceptanceCompleter.complete();
              } else {
                acceptanceCompleter.completeError(
                  Exception('File transfer rejected: $acceptance'),
                );
              }
            } else {
              debugPrint(
                '[Netcat] Buffering acceptance (buffer size: ${acceptanceBuffer.length})',
              );
            }
          }
        },
        onError: (error) {
          debugPrint('[Netcat] Sender socket error: $error');
          if (!acceptanceCompleter.isCompleted) {
            acceptanceCompleter.completeError(error);
          }
        },
        onDone: () {
          debugPrint('[Netcat] Sender socket closed');
          if (!acceptanceCompleter.isCompleted) {
            acceptanceCompleter.completeError(
              Exception('Socket closed before acceptance received'),
            );
          }
        },
      );

      debugPrint('[Netcat] Connected. Sending file offer...');

      final offer = {
        'filename': filename,
        'size': fileSize,
        'transferId': transferId,
      };
      socket.writeln(jsonEncode(offer));
      await socket.flush();

      // Wait for acceptance with timeout
      await acceptanceCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('No acceptance received within 30 seconds');
        },
      );

      // Pause the subscription while we send the file
      subscription?.pause();

      debugPrint('[Netcat] Received acceptance. Sending file...');

      int bytesSent = 0;
      int lastProgressUpdate = 0;

      // Use RandomAccessFile for explicit large chunk reading (faster than stream)
      RandomAccessFile? raf;
      try {
        raf = await file.open();
        // 1MB chunk size
        const int chunkSize = 1024 * 1024;

        while (bytesSent < fileSize) {
          final chunk = await raf.read(chunkSize);
          if (chunk.isEmpty) break;

          socket.add(chunk);
          bytesSent += chunk.length;

          // Update progress less frequently to reduce overhead
          if (bytesSent - lastProgressUpdate >= _progressUpdateInterval ||
              bytesSent == fileSize) {
            _progressController.add(bytesSent / fileSize);
            lastProgressUpdate = bytesSent;
          }
        }
      } finally {
        await raf?.close();
      }

      await socket.flush();
      debugPrint(
        '[Netcat] File sent successfully. Total: ${bytesSent / (1024 * 1024)} MB',
      );
    } catch (e) {
      debugPrint('[Netcat] Sender error: $e');
      rethrow;
    } finally {
      await subscription?.cancel();
      await socket?.close();
      _progressController.close();
    }
  }

  void _optimizeSocketBuffers(Socket socket) {
    if (kIsWeb) return;

    try {
      final bufferBytes = ByteData(4);
      bufferBytes.setInt32(0, _socketBufferSize, Endian.host);
      final bufferValue = bufferBytes.buffer.asUint8List();

      // Platform-specific socket option constants
      final solSocket = Platform.isWindows ? 0xFFFF : 1;
      final soSndBuf = Platform.isWindows ? 0x1001 : 7;

      socket.setRawOption(RawSocketOption(solSocket, soSndBuf, bufferValue));

      debugPrint(
        '[Netcat] Socket send buffer optimized to ${_socketBufferSize / (1024 * 1024)} MB',
      );
    } catch (e) {
      debugPrint('[Netcat] Failed to optimize socket buffers: $e');
    }
  }
}
