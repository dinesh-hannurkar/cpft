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
    raf = await file.open(mode: FileMode.write);

    // Pre-allocate
    try {
      await raf.truncate(startup.fileSize);
    } catch (e) {
      debugPrint('[DiskWriter] Could not pre-allocate: $e');
    }

    // FIXED: Initialize to -1 to force SEEK on first chunk (Offset 0)
    // Windows `truncate()` moves file ptr to end, so we MUST seek back to 0.
    int currentPosition = -1;
    int nextChunkToWrite = 0;
    final chunkBuffer = <int, _WriteCommand>{};

    // Process write commands
    await for (final message in receivePort) {
      if (message is _WriteCommand) {
        // Add chunk to buffer
        chunkBuffer[message.chunkId] = message;

        // Check if we can write sequential chunks from the buffer
        while (chunkBuffer.containsKey(nextChunkToWrite)) {
          final command = chunkBuffer.remove(nextChunkToWrite)!;
          try {
            // Smart seek: only seek if the position is incorrect
            if (currentPosition != command.offset) {
              await raf.setPosition(command.offset);
              // VERIFY SEEK for debugging
              final actualPos = await raf.position();
              if (actualPos != command.offset) {
                debugPrint(
                  '[DiskWriter] ❌ SEEK FAILED! Req: ${command.offset}, Act: $actualPos',
                );
              }
              currentPosition = command.offset;
            }

            // DEBUG: Trace write
            debugPrint(
              '[DiskWriter] ✍️ Writing Chunk ${command.chunkId} at offset ${command.offset} (Len: ${command.data.length}). Pos: $currentPosition',
            );

            await raf.writeFrom(command.data);
            currentPosition += command.data.length;

            final postPos = await raf.position();
            if (postPos != currentPosition) {
              debugPrint(
                '[DiskWriter] ⚠️ Position Mismatch after write! Expected: $currentPosition, Actual: $postPos',
              );
            }
            nextChunkToWrite++; // Move to the next chunk

            // Send completion acknowledgment
            startup.sendPort.send(_WriteResult(chunkId: command.chunkId));
          } catch (e) {
            startup.sendPort.send(
              _Error('Write failed for chunk ${command.chunkId}: $e'),
            );
            // Stop processing further to avoid corruption
            break;
          }
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
