import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'quic_transport.dart';
import 'quic_progress.dart';

class QuicSender {
  final QuicTransport transport;
  final String ip;
  final int port;
  final File file;
  final String transferId;
  final Function(QuicProgress)? onProgress;

  bool _isCancelled = false;
  int _dataStreamId = 0;

  QuicSender({
    required this.transport,
    required this.ip,
    required this.port,
    required this.file,
    required this.transferId,
    this.onProgress,
  });

  int _startTime = 0;

  Future<void> start() async {
    try {
      _startTime = DateTime.now().millisecondsSinceEpoch;
      // Generate Random Stream ID (>10 to avoid conflicts)
      _dataStreamId = DateTime.now().millisecondsSinceEpoch % 10000 + 10;

      await _sendMetadata();
      await _sendFileData();

      debugPrint('[QUIC] Sender finished $transferId');
    } catch (e) {
      debugPrint('[QUIC] Sender Error: $e');
      onProgress?.call(
        QuicProgress(
          transferId: transferId,
          bytesTransferred: 0,
          totalBytes: 0,
          isOutgoing: true,
          error: e.toString(),
        ),
      );
    } finally {
      await _cleanup();
    }
  }

  Future<void> _sendMetadata() async {
    // Stream 0: Metadata
    // Format: [ID Len:2][ID][Size:8][Name Len:2][Name][DataStreamID:4]

    final metaBuilder = BytesBuilder();

    final idBytes = transferId.codeUnits;
    metaBuilder.addByte(idBytes.length >> 8);
    metaBuilder.addByte(idBytes.length & 0xFF);
    metaBuilder.add(idBytes);

    final len = await file.length();
    final sizeBytes = ByteData(8);
    sizeBytes.setUint64(0, len, Endian.big);
    metaBuilder.add(sizeBytes.buffer.asUint8List());

    final name = file.uri.pathSegments.last;
    final nameBytes = name.codeUnits;
    metaBuilder.addByte(nameBytes.length >> 8);
    metaBuilder.addByte(nameBytes.length & 0xFF);
    metaBuilder.add(nameBytes);

    // Add Data Stream ID
    final streamIdBytes = ByteData(4);
    streamIdBytes.setUint32(0, _dataStreamId, Endian.big);
    metaBuilder.add(streamIdBytes.buffer.asUint8List());

    await transport.sendStreamData(ip, port, 0, metaBuilder.takeBytes());
  }

  // Parallel Transfer State
  static const int _numStreams = 4;
  int _bytesSent = 0;
  int _totalFileLen = 0;

  Future<void> _sendFileData() async {
    // Parallel Streams Strategy
    // Split file into 4 segments.
    // Each segment is handled by an independent async loop.

    _totalFileLen = await file.length();
    final segmentSize = (_totalFileLen / _numStreams).ceil();

    final futures = <Future>[];

    for (int i = 0; i < _numStreams; i++) {
      final start = i * segmentSize;
      final end = (start + segmentSize < _totalFileLen)
          ? start + segmentSize
          : _totalFileLen;
      if (start >= _totalFileLen) break;

      // Use distinct Stream ID for each segment: Base + i
      final streamId = _dataStreamId + i;
      futures.add(_runStreamSender(streamId, start, end));
    }

    debugPrint(
      '[QUIC] STARTING PARALLEL TRANSFER: Launched $_numStreams concurrent streams. Total: $_totalFileLen bytes',
    );
    await Future.wait(futures);
    debugPrint('[QUIC] Parallel Transfer Finished.');
  }

  Future<void> _runStreamSender(
    int streamId,
    int startOffset,
    int endOffset,
  ) async {
    debugPrint(
      '[QUIC] Stream $streamId STARTED. Range: $startOffset - $endOffset (${(endOffset - startOffset) / 1024} KB)',
    );
    final raf = await file.open();
    // Seek to start
    await raf.setPosition(startOffset);

    int currentPos = startOffset;
    // Optimization: Increase Chunk Size to 2MB (was 32KB)
    // Minimizes loop overhead and syscalls.
    const chunkSize = 2 * 1024 * 1024;

    try {
      while (currentPos < endOffset && !_isCancelled) {
        int remaining = endOffset - currentPos;
        int toRead = remaining > chunkSize ? chunkSize : remaining;

        if (toRead <= 0) break;

        final data = await raf.read(toRead);
        if (data.isEmpty) break;

        await transport.sendStreamData(ip, port, streamId, data);

        currentPos += data.length;
        _updateProgress(data.length);
      }
      debugPrint('[QUIC] Stream $streamId COMPLETED successfully.');
    } catch (e) {
      debugPrint('[QUIC] Stream $streamId Error: $e');
      _isCancelled = true;
      rethrow;
    } finally {
      await raf.close();
    }
  }

  void _updateProgress(int bytes) {
    _bytesSent += bytes;
    onProgress?.call(
      QuicProgress(
        transferId: transferId,
        bytesTransferred: _bytesSent,
        totalBytes: _totalFileLen,
        isOutgoing: true,
        filePath: file.path,
        isComplete: _bytesSent >= _totalFileLen,
        durationMs: DateTime.now().millisecondsSinceEpoch - _startTime,
      ),
    );
  }

  Future<void> _cleanup() async {
    // Ensure all packets are acknowledged by the receiver before closing
    // This guarantees the receiver has all data.
    try {
      if (transport is QuicTransportDart) {
        final dartTransport = transport as QuicTransportDart;
        final state = dartTransport.getConnectionState(
          InternetAddress(ip),
          port,
        );
        if (state != null) {
          debugPrint(
            '[QUIC] Found connection state. Waiting for final ACKs...',
          );
          // Wait up to 10 seconds for final ACKs (increased from 5s).
          await state.waitForAllAcks().timeout(const Duration(seconds: 10));
          debugPrint('[QUIC] All packets acknowledged! Safe to close.');
        } else {
          debugPrint(
            '[QUIC] WARNING: No connection state found for $ip:$port (Key: ${InternetAddress(ip).address}:$port). Cannot confirm delivery.',
          );
        }
      }
    } catch (e) {
      debugPrint('[QUIC] Timeout waiting for ACKs or error: $e');
    }

    try {
      transport.closeConnection(InternetAddress(ip), port);
    } catch (e) {
      debugPrint('[QUIC] Error closing connection: $e');
    }
  }

  void cancel() {
    _isCancelled = true;
  }
}
