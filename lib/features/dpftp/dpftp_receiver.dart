import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
// import 'package:crypto/crypto.dart'; // PERF: Disabled
import 'dpftp_types.dart';
import 'dpftp_socket_manager.dart';
import 'dpftp_socket.dart';
import 'dpftp_disk_writer.dart';

/// Receiver side of DPFTP v1.
/// - Accepts connections (Control + Data)
/// - Manages the file Bitmap
/// - Assigns chunks to data connections (PULL)
/// - Verifies hashes
class DpftpReceiver {
  final int port;
  final String saveDirectory;
  final Function(DpftpProgress)? onProgress;

  ServerSocket? _server;
  final Map<String, _Session> _sessions =
      {}; // Active sessions by peer IP? Or 1 session?
  // V1 Simplification: Single active transfer per instance?
  // Design says "1 control connection...".
  // We'll manage per-file sessions. But how to map socket to session?
  // HELLO message starts session.

  DpftpReceiver({
    required this.port,
    required this.saveDirectory,
    this.onProgress,
  });

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    debugPrint('[DPFTP] Receiver listening on $port');
    _server!.listen(_handleConnection);
  }

  void _handleConnection(Socket socket) {
    // For now, simple logic: First socket from IP is Control?
    // SocketManager handles this. We need to act as "Session Manager".
    // When socket connects, we don't know who it is yet.
    // We wrap it in a SocketManager.
    // Wait, multiple sockets form ONE transfer.
    // We need to group them. IP is the key.

    final ip = socket.remoteAddress.address;
    if (!_sessions.containsKey(ip)) {
      _sessions[ip] = _Session(
        ip,
        saveDirectory,
        onProgress,
        onComplete: () {
          // Reset session state for next transfer (keep sockets alive)
          debugPrint('[DPFTP] Transfer complete for $ip, ready for next file');
          _sessions[ip]?.reset();
        },
      );
    }

    _sessions[ip]!.addSocket(socket);
  }

  Future<void> stop() async {
    await _server?.close();
    for (var s in _sessions.values) s.dispose();
    _sessions.clear();
  }
}

class _Session {
  final String ip;
  final String saveDir;
  final Function(DpftpProgress)? onProgress;
  final VoidCallback? onComplete; // Callback when transfer finishes
  final DpftpSocketManager _sockets = DpftpSocketManager();

  // State
  DpftpDiskWriter? _diskWriter; // Isolate-based disk writer
  RandomAccessFile? _raf; // Kept for metadata/legacy fallback
  DpftpFileInfo? _fileInfo;
  String? _fileName;
  String? _transferId;
  DateTime? _startTime;
  int _receivedBytes = 0;

  _Session(this.ip, this.saveDir, this.onProgress, {this.onComplete}) {
    _sockets.controlMessages.listen(_handleControlMessage);
    _sockets.dataMessages.listen(_handleDataMessage);
  }

  void addSocket(Socket s) => _sockets.addSocket(s);

  void sendError(String msg) {
    _sockets.sendControl(Dpftp.typeError, Uint8List.fromList(msg.codeUnits));
  }

  Future<void> _handleControlMessage(DpftpMessage msg) async {
    try {
      // Log only control messages, not data
      // if (msg.type != Dpftp.typeData && msg.type != Dpftp.typeChunkDone) {
      //   debugPrint(
      //     '[DPFTP][Rx] Control Msg Type: ${msg.type} (Len: ${msg.payload.length})',
      //   );
      // }
      switch (msg.type) {
        case Dpftp.typeHello:
          await _handleHello(msg.payload);
          break;
        case Dpftp.typeRequestChunks:
          await _handleRequestChunks(msg.payload);
          break;
        case Dpftp.typeChunkDone:
          await _handleChunkDone(msg.payload);
          break;
        case Dpftp.typeError:
          debugPrint(
            '[DPFTP] Error from sender: ${String.fromCharCodes(msg.payload)}',
          );
          break;
        default:
          debugPrint('[DPFTP] Unknown control type: ${msg.type}');
      }
    } catch (e) {
      debugPrint('[DPFTP] Control handler error: $e');
      sendError(e.toString());
    }
  }

  Future<void> _handleDataMessage(DpftpMessage msg) async {
    // Expected to be typeData (0x08)
    // BUT DpftpSocket doesn't check specific types.
    // Frame: [ChunkId:4][Len:4][Data]
    final bd = ByteData.view(msg.payload.buffer);
    final chunkId = bd.getInt32(0, Endian.big);
    final len = bd.getInt32(4, Endian.big);

    // Log occasionally only for debug builds if needed
    // if (chunkId % 50 == 0) {
    //   debugPrint('[DPFTP][Rx] Data Chunk $chunkId ($len bytes)');
    // }

    // Data starts at offset 8
    final data = msg.payload.sublist(8);

    if (data.length != len) {
      debugPrint('[DPFTP] Data mismatch: declared $len, got ${data.length}');
      return;
    }

    if (_diskWriter == null || _fileInfo == null) return;

    // Track start time on first chunk
    _startTime ??= DateTime.now();

    // Calculate hash synchronously (faster for 1MB than Isolate overhead)
    // PERF: Disable hash for max throughput test
    // final hash = sha256.convert(data).bytes;
    final calculated = _calculatedHashes[chunkId] = const <int>[]; // Dummy hash

    final offset = chunkId * Dpftp.defaultChunkSize;

    // Send to isolate disk writer (non-blocking!)
    if (_diskWriter != null) {
      _diskWriter!.writeChunk(chunkId, offset, data);
    } else {
      // Fallback to direct write (should not happen in normal flow)
      debugPrint(
        '[DPFTP] Warning: disk writer not initialized, using fallback',
      );
      return;
    }

    _receivedBytes += len;
    // PERF: Throttled progress callbacks (chunk 0 + every 8 chunks for UI timing)
    if (chunkId == 0 || chunkId % 8 == 0 || _fileInfo!.bitmap.isComplete) {
      onProgress?.call(
        DpftpProgress(
          transferId: _transferId ?? _fileName ?? 'unknown',
          bytesTransferred: _receivedBytes,
          totalBytes: _fileInfo?.fileSize ?? 0,
          isOutgoing: false,
          filePath: '${saveDir}/${_fileName}',
        ),
      );
    }

    // Check if CHUNK_DONE arrived early
    if (_pendingDoneHashes.containsKey(chunkId)) {
      final expected = _pendingDoneHashes.remove(chunkId)!;
      _verifyChunk(chunkId, calculated, expected);
    }
  }

  final Map<int, List<int>> _calculatedHashes = {};
  final Map<int, List<int>> _pendingDoneHashes =
      {}; // [ID -> Hash] from early Control msg

  final Set<int> _inFlightChunks = {};

  void _verifyChunk(int id, List<int> calculated, List<int> expected) {
    // PERF: Skip verification
    if (true /*listEquals(calculated, expected)*/ ) {
      _fileInfo!.bitmap.markReceived(id);
      // _calculatedHashes.remove(id); // Clean up
      _inFlightChunks.remove(id); // Done
      _saveMetadata(); // Throttled

      // Send ACK for flow control & progress sync
      _sockets.sendControl(Dpftp.typeChunkAck, Dpftp.int32(id));

      if (_fileInfo!.bitmap.isComplete) {
        _finishTransfer();
      }
    } else {
      debugPrint('[DPFTP] Chunk $id Hash Mismatch!');
      _calculatedHashes.remove(id);
      _inFlightChunks.remove(id); // Allow retry
    }
  }

  // ... (handleHello in between)

  Future<void> _handleRequestChunks(Uint8List payload) async {
    // Payload: [MaxChunks:2]
    final maxChunks = Dpftp.readInt16(payload, 0);

    // Find missing chunks in bitmap
    final missing = _fileInfo!.bitmap.getMissingChunks(
      maxChunks + _inFlightChunks.length,
    );

    // Filter out in-flight
    final assignable = missing
        .where((id) => !_inFlightChunks.contains(id))
        .take(maxChunks)
        .toList();

    if (assignable.isEmpty) {
      if (_fileInfo!.bitmap.isComplete) {
        return;
      }
      return;
    }

    // Send ASSIGN_CHUNKS
    final b = BytesBuilder();
    b.add(Dpftp.int16(assignable.length));
    for (final id in assignable) {
      b.add(Dpftp.int32(id));
      _inFlightChunks.add(id); // Mark In-Flight
    }

    await _sockets.sendControl(Dpftp.typeAssignChunks, b.takeBytes());
  }

  Future<void> _handleHello(Uint8List payload) async {
    // Payload: [NameLen:2][Name][Size:8] (Adapted)
    int offset = 0;
    final nameLen = Dpftp.readInt16(payload, offset);
    offset += 2;
    _fileName = String.fromCharCodes(payload.sublist(offset, offset + nameLen));
    offset += nameLen;

    // Support standard HELLO (no size) if it's a resume of known file?
    // But for new upload, valid size is critical.
    if (payload.length < offset + 8) {
      sendError('Protocol mismatch: HELLO must include File Size (8 bytes)');
      return;
    }
    final fileSize = ByteData.sublistView(
      payload,
      offset,
      offset + 8,
    ).getUint64(0, Endian.big);
    offset += 8;

    // PROTOCOL V1.1: Parse TransferID [Len:2][ID]
    // Check if available (backward compat?)
    if (payload.length >= offset + 2) {
      final idLen = Dpftp.readInt16(payload, offset);
      offset += 2;
      _transferId = String.fromCharCodes(
        payload.sublist(offset, offset + idLen),
      );
      offset += idLen;
    } else {
      _transferId = _fileName; // Fallback
    }

    debugPrint(
      '[DPFTP] Hello: $_fileName ($fileSize bytes) from $ip (ID: $_transferId)',
    );

    // Create session file info with unique filename if needed
    String uniqueFileName = _fileName ?? 'unknown';
    File file = File('$saveDir/$uniqueFileName');

    // Generate unique filename if file already exists (avoid overwriting)
    if (await file.exists() &&
        !await File('$saveDir/$uniqueFileName.dpftp').exists()) {
      int counter = 1;
      final parts = uniqueFileName.split('.');
      final extension = parts.length > 1 ? parts.last : '';
      final baseName = parts.length > 1
          ? parts.sublist(0, parts.length - 1).join('.')
          : uniqueFileName;

      while (await file.exists()) {
        uniqueFileName = extension.isNotEmpty
            ? '$baseName ($counter).$extension'
            : '$uniqueFileName ($counter)';
        file = File('$saveDir/$uniqueFileName');
        counter++;
        if (counter > 100) break; // Safety limit
      }

      debugPrint('[DPFTP] File exists, using unique name: $uniqueFileName');
      _fileName = uniqueFileName; // Update filename
    }

    final metaFile = File('$saveDir/${_fileName}.dpftp');

    if (await metaFile.exists()) {
      final bytes = await metaFile.readAsBytes();
      _fileInfo = DpftpFileInfo.fromBytes(bytes);
      // Verify size matches?
      if (_fileInfo!.fileSize != fileSize) {
        sendError('Resume mismatch: File size changed');
        return;
      }
      debugPrint('[DPFTP] Resuming: ${_fileInfo!.totalChunks} chunks');
    } else {
      // Calculation - use int for large files
      final chunkSize = Dpftp.defaultChunkSize;
      final totalChunks = (fileSize / chunkSize).ceil();

      // Validate file size (Dart int is 64-bit, supports up to ~9 exabytes)
      if (fileSize < 0 || totalChunks < 0) {
        sendError('Invalid file size: $fileSize bytes');
        return;
      }

      debugPrint(
        '[DPFTP] Creating new transfer: $totalChunks chunks, ${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB',
      );

      _fileInfo = DpftpFileInfo(
        fileSize: fileSize,
        chunkSize: chunkSize,
        totalChunks: totalChunks,
        bitmap: ChunkBitmap(totalChunks),
      );

      // Create file with proper mode (writeOnly creates if not exists)
      _raf = await file.open(mode: FileMode.writeOnly);
      // Pre-allocate space for large files (helps performance)
      try {
        await _raf!.truncate(fileSize);
      } catch (e) {
        debugPrint(
          '[DPFTP] Warning: Could not pre-allocate $fileSize bytes: $e',
        );
        // Continue anyway - file will grow as chunks are written
      }
      _saveMetadata();
      _receivedBytes = 0;

      // Initialize disk writer isolate
      _diskWriter = DpftpDiskWriter();
      await _diskWriter!.start('$saveDir/$_fileName', fileSize);
      debugPrint('[DPFTP] Disk writer isolate started');
    }

    if (_raf == null && _diskWriter == null) {
      _raf = await file.open(mode: FileMode.append); // Re-open for resume

      // Calc received bytes (approx)
      final missing = _fileInfo!.bitmap.getMissingChunks(
        _fileInfo!.totalChunks,
      );
      final receivedChunks = _fileInfo!.totalChunks - missing.length;
      _receivedBytes = receivedChunks * _fileInfo!.chunkSize;

      // Initialize disk writer for resume
      _diskWriter = DpftpDiskWriter();
      await _diskWriter!.start('$saveDir/$_fileName', fileSize);
      debugPrint('[DPFTP] Disk writer isolate started (resume)');
    }

    // ... rest of function

    // Send FILE_INFO
    await _sockets.sendControl(Dpftp.typeFileInfo, _fileInfo!.toBytes());
  }

  Timer? _metaSaveTimer;

  void _saveMetadata() {
    // Throttle saves to once per second
    if (_metaSaveTimer?.isActive ?? false) return;

    _metaSaveTimer = Timer(const Duration(seconds: 1), () async {
      if (_fileInfo == null || _fileName == null) return;
      try {
        final metaFile = File('$saveDir/$_fileName!.dpftp');
        await metaFile.writeAsBytes(_fileInfo!.toBytes());
      } catch (e) {
        debugPrint('[DPFTP] Meta save failed: $e');
      }
    });
  }

  Future<void> _handleChunkDone(Uint8List payload) async {
    // Payload: [ID:4][Hash:32]
    final id = Dpftp.readInt32(payload, 0);
    final hashBytes = payload.sublist(4, 36);

    // 1. Check if we have data (from Data Channel)
    if (_calculatedHashes.containsKey(id)) {
      _verifyChunk(id, _calculatedHashes[id]!, hashBytes);
    } else {
      // Data not yet processed. Store this hash for later.
      _pendingDoneHashes[id] = hashBytes;
    }
  }

  bool _transferFinished = false;

  Future<void> _finishTransfer() async {
    if (_transferFinished) return;
    _transferFinished = true;

    debugPrint('[DPFTP] Transfer Complete!');

    // Calculate actual transfer duration
    final duration = _startTime != null
        ? DateTime.now().difference(_startTime!)
        : Duration.zero;
    debugPrint('[DPFTP] Actual transfer time: ${duration.inSeconds}s');

    // Calculate final hash?
    // Protocol 3.8: Payload final_hash.
    // For now, send dummy or calculated.
    // We'll send Empty hash for V1 or file hash.
    final finalHash = Uint8List(32); // Todo
    await _sockets.sendControl(Dpftp.typeTransferComplete, finalHash);

    // Emit final progress/completion event for UI with actual duration
    onProgress?.call(
      DpftpProgress(
        transferId: _transferId ?? 'unknown',
        bytesTransferred: _fileInfo?.fileSize ?? 0,
        totalBytes: _fileInfo?.fileSize ?? 0,
        isOutgoing: false,
        filePath: '$saveDir/$_fileName',
        isComplete: true,
        durationMs: duration.inMilliseconds,
      ),
    );

    // Clean up metadata
    final metaFile = File('$saveDir/$_fileName!.dpftp');
    if (await metaFile.exists()) await metaFile.delete();

    _raf?.close();
    _raf = null;

    // Notify parent to clean up this session
    onComplete?.call();
  }

  void reset() {
    // Reset transfer state without closing sockets (for sequential transfers)
    _raf?.close();
    _raf = null;
    _diskWriter?.stop();
    _diskWriter = null;
    _fileInfo = null;
    _fileName = null;
    _transferId = null;
    _receivedBytes = 0;
    _transferFinished = false;
    _calculatedHashes.clear();
    _pendingDoneHashes.clear();
    _inFlightChunks.clear();
    _startTime = null;
    _metaSaveTimer?.cancel();
    _metaSaveTimer = null;
    debugPrint('[DPFTP] Session reset, ready for next transfer');
  }

  void dispose() {
    _raf?.close();
    _diskWriter?.stop();
    _sockets.dispose(); // Close all sockets
    _metaSaveTimer?.cancel();
  }
}
