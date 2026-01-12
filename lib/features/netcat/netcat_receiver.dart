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

  // Optimize for high-speed transfer
  static const int _socketBufferSize = 2 * 1024 * 1024; // 2MB socket buffer
  static const int _progressUpdateInterval =
      10 * 1024 * 1024; // Update every 10MB

  NetcatReceiver({required this.port, required this.saveDirectory});

  Future<void> start() async {
    _server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    debugPrint('[Netcat] Receiver listening on $port');
    _server!.listen(_handleConnection);
  }

  final Map<String, Completer<_PendingTransfer>> _transferCompleters = {};

  void _handleConnection(Socket socket) {
    // Optimize socket buffers immediately
    _optimizeSocketBuffers(socket);

    final buffer = <int>[];
    StreamSubscription<List<int>>? subscription;

    subscription = socket.listen(
      (data) {
        try {
          // If we haven't processed the header yet
          buffer.addAll(data);
          final newlineIndex = buffer.indexOf(10); // '\n'

          if (newlineIndex != -1) {
            // Found the header
            final offerLine = utf8.decode(buffer.sublist(0, newlineIndex));
            final offer = jsonDecode(offerLine);
            final transferId = offer['transferId'] as String;
            final fileSize = offer['size'] as int;

            debugPrint('[Netcat] Received offer for transfer: $transferId');

            // Capture any data that came after the newline
            Uint8List? remainingData;
            if (buffer.length > newlineIndex + 1) {
              remainingData = Uint8List.fromList(
                buffer.sublist(newlineIndex + 1),
              );
            }

            // Create the pending transfer object
            final pending = _PendingTransfer(
              socket: socket,
              subscription: subscription!,
              fileSize: fileSize,
              remainingData: remainingData,
            );

            // Pause subscription
            subscription.pause();

            // Complete the waiter if one exists, or create a completed one
            if (!_transferCompleters.containsKey(transferId)) {
              _transferCompleters[transferId] = Completer<_PendingTransfer>();
            }
            if (!_transferCompleters[transferId]!.isCompleted) {
              _transferCompleters[transferId]!.complete(pending);
            }
          }
        } catch (e) {
          debugPrint('[Netcat] Error parsing offer: $e');
          subscription?.cancel();
          socket.close();
        }
      },
      onError: (error) {
        debugPrint('[Netcat] Receiver socket error: $error');
        socket.close();
      },
      onDone: () {
        // If we haven't stored the transfer yet, close socket
        socket.close();
      },
    );
  }

  void acceptFile(String transferId, String filePath, int fileSize) async {
    debugPrint('[Netcat] acceptFile called for $transferId');

    // Ensure we have a completer entry
    if (!_transferCompleters.containsKey(transferId)) {
      _transferCompleters[transferId] = Completer<_PendingTransfer>();
    }

    _PendingTransfer? pending;
    try {
      // Wait for the connection to arrive (timeout 15s)
      debugPrint('[Netcat] Waiting for connection for $transferId...');
      pending = await _transferCompleters[transferId]!.future.timeout(
        const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint('[Netcat] Timeout waiting for connection: $e');
      _transferCompleters.remove(transferId);
      return;
    }

    // Clean up map
    _transferCompleters.remove(transferId);

    final socket = pending.socket;
    // Explicitly typed locally as well
    final StreamSubscription<List<int>> subscription = pending.subscription;
    final file = File(filePath);
    final sink = file.openWrite();
    int bytesReceived = 0;
    int lastProgressUpdate = 0;

    try {
      // Send acceptance message
      socket.writeln('accept');
      await socket.flush();

      debugPrint('[Netcat] Sent acceptance, waiting for file data...');

      // Process any data we already read
      if (pending.remainingData != null) {
        sink.add(pending.remainingData!);
        bytesReceived += pending.remainingData!.length;
      }

      // Completer to wait for the stream to finish
      final transferCompleter = Completer<void>();

      // Update the subscription to write to file
      subscription.onData((data) {
        sink.add(data);
        bytesReceived += data.length;

        // Update progress less frequently to reduce overhead
        if (bytesReceived - lastProgressUpdate >= _progressUpdateInterval ||
            bytesReceived >= fileSize) {
          _progressController.add({
            'transferId': transferId,
            'totalSize': fileSize,
            'progress': bytesReceived / fileSize,
            'path': filePath,
          });
          lastProgressUpdate = bytesReceived;
        }
      });

      subscription.onDone(() {
        transferCompleter.complete();
      });

      subscription.onError((error) {
        transferCompleter.completeError(error);
      });

      // Resume the stream to flow data
      subscription.resume();

      // Wait for it to finish
      await transferCompleter.future;

      await sink.close();
      debugPrint(
        '[Netcat] File received successfully: $filePath (${bytesReceived / (1024 * 1024)} MB)',
      );
      _completionController.add({
        'transferId': transferId,
        'path': filePath,
        'size': fileSize,
      });
    } catch (e) {
      debugPrint('[Netcat] Error receiving file: $e');
      await sink.close();
    } finally {
      await subscription.cancel();
      await socket.close();
    }
  }

  void _optimizeSocketBuffers(Socket socket) {
    if (kIsWeb) return;

    try {
      final bufferBytes = ByteData(4);
      bufferBytes.setInt32(0, _socketBufferSize, Endian.host);
      final bufferValue = bufferBytes.buffer.asUint8List();

      // Platform-specific socket option constants
      final solSocket = (Platform.isWindows || Platform.isMacOS) ? 0xFFFF : 1;
      final soRcvBuf = (Platform.isWindows || Platform.isMacOS) ? 0x1002 : 8;

      socket.setRawOption(RawSocketOption(solSocket, soRcvBuf, bufferValue));

      // Verify if possible (by checking exceptions) or just log success attempt
      debugPrint(
        '[Netcat] Attempted to set Receive Buffer to ${_socketBufferSize / 1024} KB',
      );
    } catch (e) {
      debugPrint('[Netcat] Failed to optimize socket buffers: $e');
    }
  }

  void stop() {
    _server?.close();
    _progressController.close();
    _completionController.close();
    // Close any pending sockets
    for (final completer in _transferCompleters.values) {
      if (completer.isCompleted) {
        completer.future.then((pending) => pending.socket.close());
      }
    }
    _transferCompleters.clear();
  }
}

class _PendingTransfer {
  final Socket socket;
  final StreamSubscription<List<int>> subscription;
  final int fileSize;
  final Uint8List? remainingData;

  _PendingTransfer({
    required this.socket,
    required this.subscription,
    required this.fileSize,
    this.remainingData,
  });
}
