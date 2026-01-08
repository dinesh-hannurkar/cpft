import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'quic_transport.dart';
import 'quic_progress.dart';

class QuicReceiver {
  final QuicTransport transport;
  final String saveDirectory;
  final Function(QuicProgress)? onProgress;

  QuicReceiver({
    required this.transport,
    required this.saveDirectory,
    this.onProgress,
  });

  // Track active transfers by TransferID
  // But wait, standard QUIC multiplexes streams.
  // We need to map Stream ID to Context.
  // We'll simplisticly assume one sender for now or map by IP.
  // Map Stream ID to Stream Info (Context + Base Offset)
  final Map<int, _StreamInfo> _streamMap = {};

  // Buffer for packets that arrive before their Metadata (Unknown Stream ID)
  final Map<int, List<QuicStreamEvent>> _orphanBuffer = {};

  final Map<String, _RxContext> _contexts = {};

  void start() {
    transport.dataStream.listen(_handleIncomingStreamData);
  }

  void _handleIncomingStreamData(QuicStreamEvent event) {
    // Map Context by IP for Metadata Stream 0
    // But for Data Streams, use Stream Map.

    if (event.streamId == 0) {
      if (event.data.length == 2 &&
          event.data[0] == 0xFF &&
          event.data[1] == 0xFF) {
        debugPrint('[QUIC-Rx] FIN signal received from ${event.remoteIp}');
        _contexts[event.remoteIp]?.markRemoteDone();
        return;
      }

      debugPrint('[QUIC-Rx] Metadata Packet Received from ${event.remoteIp}');
      final ctx = _contexts.putIfAbsent(
        event.remoteIp,
        () => _RxContext(saveDirectory, onProgress),
      );

      // Handle Meta and get Data Stream ID
      final dataStreamId = ctx.handleMetadata(event.data);
      if (dataStreamId != null) {
        debugPrint('[QUIC-Rx] Metadata Parsed. Base Stream ID: $dataStreamId');

        // Calculate Segment Size (assume 4 streams as per Sender)
        final fileSize = ctx.fileSize ?? 0;
        final segmentSize = (fileSize / 4).ceil();

        // Register Parallel Stream IDs (Base + 3)
        for (int i = 0; i < 4; i++) {
          final streamId = dataStreamId + i;
          final baseOffset = i * segmentSize;

          _streamMap[streamId] = _StreamInfo(ctx, baseOffset);

          // Check for buffered orphans
          if (_orphanBuffer.containsKey(streamId)) {
            debugPrint(
              '[QUIC-Rx] Replaying ${_orphanBuffer[streamId]!.length} orphaned packets for Stream $streamId',
            );
            final orphans = _orphanBuffer.remove(streamId)!;
            for (final orphan in orphans) {
              ctx.handleFileData(orphan.data, orphan.offset + baseOffset);
            }
          }
        }
      }
    } else {
      // Data Stream
      final info = _streamMap[event.streamId];
      if (info != null) {
        // Add Base Offset (Segment Start) to Stream Offset (Relative to Segment)
        info.ctx.handleFileData(event.data, event.offset + info.baseOffset);
      } else {
        // Metadata not arrived yet. Buffer this packet.
        if (!_orphanBuffer.containsKey(event.streamId)) {
          debugPrint(
            '[QUIC-Rx] Buffering FIRST Orphan for Stream ${event.streamId} (Waiting for Metadata)',
          );
        }
        _orphanBuffer.putIfAbsent(event.streamId, () => []).add(event);
      }
    }
  }

  void stop() {
    // Close all file handles
  }
}

class _StreamInfo {
  final _RxContext ctx;
  final int baseOffset;
  _StreamInfo(this.ctx, this.baseOffset);
}

class _RxContext {
  final String saveDir;
  final Function(QuicProgress)? onProgress;

  String? transferId;
  int? fileSize;
  String? fileName;
  RandomAccessFile? _raf;
  int _receivedBytes = 0;
  bool _isRemoteDone = false;
  Timer? _finTimeout;

  _RxContext(this.saveDir, this.onProgress);

  int _startTime = 0;

  void markRemoteDone() {
    if (_isRemoteDone) return;
    _isRemoteDone = true;
    debugPrint('[QUIC] Remote says DONE. Checked: $_receivedBytes / $fileSize');

    if (fileSize != null && _receivedBytes >= fileSize!) {
      finish();
    } else {
      // Wait for out-of-order packets, but set a hard limit
      debugPrint('[QUIC] Missing data. Waiting up to 10s for reordering...');
      _finTimeout = Timer(const Duration(seconds: 10), () {
        if (_raf != null) {
          debugPrint('[QUIC] Final Timeout. Forcing finish.');
          finish(force: true);
        }
      });
    }
  }

  int? handleMetadata(Uint8List data) {
    try {
      _startTime = DateTime.now().millisecondsSinceEpoch;

      final reader = ByteData.sublistView(data);
      int offset = 0;

      final idLen = reader.getUint16(offset);
      offset += 2;
      transferId = String.fromCharCodes(data.sublist(offset, offset + idLen));
      offset += idLen;

      fileSize = reader.getUint64(offset, Endian.big);
      offset += 8;

      final nameLen = reader.getUint16(offset);
      offset += 2;
      fileName = String.fromCharCodes(data.sublist(offset, offset + nameLen));
      offset += nameLen;

      final dataStreamId = reader.getUint32(offset, Endian.big);

      final path = '$saveDir/$fileName';
      // Use RandomAccessFile for parallel writes
      final file = File(path);
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);

      _raf = file.openSync(mode: FileMode.write);
      _raf!.truncateSync(fileSize!); // Pre-allocate

      debugPrint(
        '[QUIC] Rx Started: $fileName ($fileSize bytes) ID: $transferId',
      );
      return dataStreamId;
    } catch (e) {
      debugPrint('[QUIC] Metadata Error: $e');
      return null;
    }
  }

  void handleFileData(Uint8List data, int offset) {
    if (_raf == null) return;

    try {
      // Synchronous Random Write
      _raf!.setPositionSync(offset);
      _raf!.writeFromSync(data);

      _receivedBytes += data.length;

      // Heartbeat Log every ~1MB
      if (_receivedBytes % (1024 * 1024) < data.length) {
        debugPrint(
          '[QUIC-Rx] Progress: ${_receivedBytes ~/ 1024} KB / ${fileSize! ~/ 1024} KB',
        );
      }

      // Progress Update
      if (onProgress != null && transferId != null) {
        final isDone = fileSize != null && _receivedBytes >= fileSize!;

        onProgress!(
          QuicProgress(
            transferId: transferId!,
            bytesTransferred: _receivedBytes,
            totalBytes: fileSize ?? 0,
            isOutgoing: false,
            filePath: '$saveDir/$fileName',
            isComplete: isDone,
            durationMs: DateTime.now().millisecondsSinceEpoch - _startTime,
          ),
        );

        if (isDone) {
          finish();
        }
      }
    } catch (e) {
      debugPrint('[QUIC] Write Error: $e');
    }
  }

  void finish({bool force = false}) {
    _finTimeout?.cancel();
    if (_raf == null) return;

    if (force && fileSize != null && _receivedBytes < fileSize!) {
      debugPrint(
        '[QUIC] WARNING: Forced finish with incomplete data! Received $_receivedBytes / $fileSize',
      );
    }

    debugPrint('[QUIC] Rx Finished: $fileName. Closing file.');
    try {
      _raf?.closeSync();
      _raf = null;
    } catch (e) {
      debugPrint('[QUIC] Close Error: $e');
    }
  }
}
