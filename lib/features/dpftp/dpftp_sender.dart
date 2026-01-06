import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dpftp_types.dart';
import 'dpftp_socket_manager.dart';
import 'dpftp_socket.dart';

/// Sender side of DPFTP v1 (Client).
/// - Connects to Receiver
/// - Sends HELLO (with size)
/// - Asks for work (REQUEST_CHUNKS)
/// - Sends assigned chunks (DATA + CHUNK_DONE)
/// - Uses Window-based Flow Control via CHUNK_ACK
class DpftpSender {
  final String ip;
  final int port;
  final File file;
  final int parallelConnections;

  final DpftpSocketManager _sockets = DpftpSocketManager();
  RandomAccessFile? _raf;
  DpftpFileInfo? _serverInfo;

  // Transfer State
  final String transferId;
  final Function(DpftpProgress)? onProgress;
  DateTime? _startTime;

  // Flow Control & Queue
  static const int _maxInFlightBytes =
      16 * 1024 * 1024; // 16MB Window (Lower memory pressure)
  static const int _requestChunkCount =
      16; // Request 16 chunks (1MB * 16 = 16MB)

  int _ackedBytes = 0; // Verified progress (for UI)
  int _pushedBytes = 0; // Bytes sent to socket (for Flow Control)
  final Map<int, int> _inflightSizes = {}; // ID -> Size
  final List<int> _chunkQueue = [];

  bool _isPumping = false;
  bool _waitingForAssignment = false;
  Completer<void>? _flowControlWait;
  int _socketIdx = 0;

  DpftpSender({
    required this.ip,
    required this.port,
    required this.file,
    required this.transferId,
    this.parallelConnections = 1,
    this.onProgress,
  });

  Future<void> start() async {
    try {
      final fileSize = await file.length();
      _raf = await file.open(mode: FileMode.read);
      _ackedBytes = 0;
      _pushedBytes = 0;

      // Connect Control Socket (0)
      await _connectSocket();

      // Setup Listener
      _sockets.controlMessages.listen(_handleControlMessage);

      // Send HELLO
      // [NameLen:2][Name][Size:8]
      final name = file.uri.pathSegments.last;
      final nameBytes = Uint8List.fromList(name.codeUnits);
      final b = BytesBuilder();
      b.add(Dpftp.int16(nameBytes.length));
      b.add(nameBytes);
      final sizeBytes = ByteData(8)..setUint64(0, fileSize, Endian.big);
      b.add(sizeBytes.buffer.asUint8List());

      // PROTOCOL V1.1: Add TransferID [Len:2][ID]
      final idBytes = Uint8List.fromList(transferId.codeUnits);
      b.add(Dpftp.int16(idBytes.length));
      b.add(idBytes);

      await _sockets.sendControl(Dpftp.typeHello, b.takeBytes());

      // Now wait for FILE_INFO
    } catch (e) {
      debugPrint('[DPFTP] Sender Start Error: $e');
    }
  }

  Future<void> _connectSocket() async {
    debugPrint('[DPFTP] Connecting socket to $ip:$port...');
    final socket = await Socket.connect(ip, port);
    _sockets.addSocket(socket);
  }

  Future<void> _handleControlMessage(DpftpMessage msg) async {
    // Keep control loop responsive! Do not block here.
    switch (msg.type) {
      case Dpftp.typeFileInfo:
        await _handleFileInfo(msg.payload);
        break;
      case Dpftp.typeAssignChunks:
        _handleAssignChunks(msg.payload);
        break;
      case Dpftp.typeChunkAck:
        _handleChunkAck(msg.payload);
        break;
      case Dpftp.typeTransferComplete:
        _handleTransferComplete();
        break;
      case Dpftp.typeError:
        debugPrint(
          '[DPFTP] Error from Receiver: ${String.fromCharCodes(msg.payload)}',
        );
        stop();
        break;
      default:
        debugPrint('[DPFTP][Tx] Unknown Control Type: ${msg.type}');
    }
  }

  Future<void> _handleFileInfo(Uint8List payload) async {
    _serverInfo = DpftpFileInfo.fromBytes(payload);
    debugPrint(
      '[DPFTP] Got FILE_INFO. Server has ${_serverInfo!.totalChunks} chunks active.',
    );

    // Establish Parallel Data Connections
    for (int i = 0; i < parallelConnections; i++) {
      await _connectSocket();
    }

    // Start Pump logic by requesting initial work
    if (!_waitingForAssignment) {
      _requestWork();
    }
  }

  void _requestWork() {
    // Only request if not already waiting
    if (_waitingForAssignment) return;

    _waitingForAssignment = true;
    // Ask for window size appropriate amount (4 chunks = 32MB)
    _sockets.sendControl(
      Dpftp.typeRequestChunks,
      Dpftp.int16(_requestChunkCount),
    );
  }

  void _handleAssignChunks(Uint8List payload) {
    // Received assignment
    _waitingForAssignment = false;

    final count = Dpftp.readInt16(payload, 0);
    int offset = 2;
    final newChunks = <int>[];

    for (int i = 0; i < count; i++) {
      newChunks.add(Dpftp.readInt32(payload, offset));
      offset += 4;
    }

    if (newChunks.isEmpty) {
      // Receiver gave us nothing (shouldn't happen with current receiver logic, but handled gracefully)
      // This might mean EOF or "Try Again Later"
      return;
    }

    debugPrint('[DPFTP] Assigned ${newChunks.length} chunks. Enqueuing.');
    _chunkQueue.addAll(newChunks);

    // Trigger pump
    _pump();
  }

  void _handleChunkAck(Uint8List payload) {
    final id = Dpftp.readInt32(payload, 0);
    // Flow Control Update
    if (_inflightSizes.containsKey(id)) {
      final size = _inflightSizes.remove(id)!;
      _ackedBytes += size;

      // Update Progress on ACK
      // Throttling isn't strictly necessary for ACKs as they are somewhat spaced out,
      // but if chunks are small, might want to throttle.
      // Here we assume 8MB chunks, so very infrequent.
      onProgress?.call(
        DpftpProgress(
          transferId: transferId,
          bytesTransferred: _ackedBytes,
          totalBytes: _serverInfo?.fileSize ?? 0,
          isOutgoing: true,
          filePath: file.path,
        ),
      );
    }

    // Check if we can unblock the pump
    if (_flowControlWait != null && !(_flowControlWait!.isCompleted)) {
      if (_pushedBytes - _ackedBytes < _maxInFlightBytes) {
        _flowControlWait!.complete();
      }
    }

    // Also trigger pump in case it was idle (though usually wait handles it)
    _pump();
  }

  void _handleTransferComplete() {
    debugPrint('[DPFTP] Transfer Complete! ✅');

    final duration = _startTime != null
        ? DateTime.now().difference(_startTime!)
        : Duration.zero;

    // Ensure 100%
    onProgress?.call(
      DpftpProgress(
        transferId: transferId,
        bytesTransferred: _serverInfo?.fileSize ?? 0,
        totalBytes: _serverInfo?.fileSize ?? 0,
        isOutgoing: true,
        filePath: file.path,
        isComplete: true,
        durationMs: duration.inMilliseconds,
      ),
    );
  }

  Future<void> _pump() async {
    if (_isPumping) return;
    _isPumping = true;

    try {
      while (_chunkQueue.isNotEmpty) {
        // Flow Control Check
        if (_pushedBytes - _ackedBytes >= _maxInFlightBytes) {
          // Window Full
          _flowControlWait ??= Completer<void>();
          await _flowControlWait!.future;
          _flowControlWait = null;
        }

        // Queue might be empty if cleared externally (unlikely) or after notify
        if (_chunkQueue.isEmpty) break;

        final id = _chunkQueue.removeAt(0);

        // Send (Awaited but IO is separate from Control)
        await _sendChunk(id, _socketIdx++);

        // Pipelining: Request more work if queue is getting low
        if (_chunkQueue.length < 2 && !_waitingForAssignment) {
          _requestWork();
        }
      }

      // If queue is empty, ensure we have requested next batch
      if (_chunkQueue.isEmpty &&
          !_waitingForAssignment &&
          _serverInfo != null) {
        // Simple check: do we think there is more?
        // Receiver handles "No More", so we just ask.
        _requestWork();
      }
    } catch (e) {
      debugPrint('[DPFTP] Pump Error: $e');
    } finally {
      _isPumping = false;
    }
  }

  Future<void> _ioLock = Future.value();

  Future<void> _sendChunk(int id, int socketIndex) async {
    if (_raf == null || _serverInfo == null) return;

    final offset = id * _serverInfo!.chunkSize;

    // Calculate size
    int size = _serverInfo!.chunkSize;
    if (id == _serverInfo!.totalChunks - 1) {
      size = (_serverInfo!.fileSize - offset).toInt();
    }

    // Register size for Flow Control
    _inflightSizes[id] = size;
    _pushedBytes += size;

    final buffer = Uint8List(size);

    // Atomic Read
    final myLock = Completer<void>();
    final prevLock = _ioLock;
    _ioLock = myLock.future;

    try {
      await prevLock;
      if (_raf == null) return;
      await _raf!.setPosition(offset);
      await _raf!.readInto(buffer);
    } catch (e) {
      debugPrint('[DPFTP] Read error: $e');
      rethrow;
    } finally {
      myLock.complete();
    }

    // Send Data
    // [ChunkId:4][Len:4][Payload]
    // Note: sendDataChunk is async (flushes to socket buffer)
    await _sockets.sendDataChunk(socketIndex, id, size, buffer);

    if (_startTime == null) _startTime = DateTime.now();

    // Send CHUNK_DONE [ID:4][Hash:32]
    final donePayload = Uint8List(36);
    final bd = ByteData.view(donePayload.buffer);
    bd.setUint32(0, id, Endian.big);

    await _sockets.sendControl(Dpftp.typeChunkDone, donePayload);

    // NOTE: Progress is NO LONGER updated here. Updated in _handleChunkAck.
  }

  void stop() {
    _sockets.dispose();
    _raf?.close();
  }
}
