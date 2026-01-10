import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Isolate-based disk writer for DPFTP
/// Runs disk I/O on separate thread to not block network reception
class DpftpDiskWriter {
  SendPort? _sendPort;
  Isolate? _isolate;

  /// Start the disk writer isolate
  Future<void> start(String filePath, int fileSize) async {
    final receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _diskWriterIsolate,
      _IsolateStartup(
        sendPort: receivePort.sendPort,
        filePath: filePath,
        fileSize: fileSize,
      ),
    );

    // Wait for isolate to send back its SendPort
    final completer = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is _WriteResult) {
        // Handle write completion (for future use)
      } else if (message is _Error) {
        debugPrint('[DiskWriter] Error: ${message.message}');
      }
    });

    _sendPort = await completer.future;
  }

  /// Write a chunk to disk (non-blocking)
  void writeChunk(int chunkId, int offset, Uint8List data) {
    _sendPort?.send(
      _WriteCommand(chunkId: chunkId, offset: offset, data: data),
    );
  }

  /// Close the file and stop the isolate
  Future<void> stop() async {
    _sendPort?.send(_CloseCommand());
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

// ═══════════════════════════════════════════════════════════════
// Isolate Entry Point
// ═══════════════════════════════════════════════════════════════

void _diskWriterIsolate(_IsolateStartup startup) async {
  final receivePort = ReceivePort();

  // Send our SendPort back to main isolate
  startup.sendPort.send(receivePort.sendPort);

  RandomAccessFile? raf;

  try {
    // Open file
    final file = File(startup.filePath);
    raf = await file.open(mode: FileMode.writeOnly);

    // Pre-allocate
    try {
      await raf.truncate(startup.fileSize);
    } catch (e) {
      debugPrint('[DiskWriter] Could not pre-allocate: $e');
    }

    int currentPosition = 0;

    // Process write commands
    await for (final message in receivePort) {
      if (message is _WriteCommand) {
        try {
          // Smart seek: only seek if needed
          if (currentPosition != message.offset) {
            await raf.setPosition(message.offset);
            currentPosition = message.offset;
          }

          await raf.writeFrom(message.data);
          currentPosition += message.data.length;

          // Send completion acknowledgment
          startup.sendPort.send(_WriteResult(chunkId: message.chunkId));
        } catch (e) {
          startup.sendPort.send(_Error('Write failed: $e'));
        }
      } else if (message is _CloseCommand) {
        break;
      }
    }
  } catch (e) {
    startup.sendPort.send(_Error('Isolate error: $e'));
  } finally {
    await raf?.close();
    receivePort.close();
  }
}

// ═══════════════════════════════════════════════════════════════
// Message Types
// ═══════════════════════════════════════════════════════════════

class _IsolateStartup {
  final SendPort sendPort;
  final String filePath;
  final int fileSize;

  _IsolateStartup({
    required this.sendPort,
    required this.filePath,
    required this.fileSize,
  });
}

class _WriteCommand {
  final int chunkId;
  final int offset;
  final Uint8List data;

  _WriteCommand({
    required this.chunkId,
    required this.offset,
    required this.data,
  });
}

class _WriteResult {
  final int chunkId;
  _WriteResult({required this.chunkId});
}

class _CloseCommand {}

class _Error {
  final String message;
  _Error(this.message);
}
