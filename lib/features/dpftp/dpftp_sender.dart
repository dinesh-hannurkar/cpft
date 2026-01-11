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
  final List<RandomAccessFile> _rafs = [];
  DpftpFileInfo? _serverInfo;

  // Transfer State
  final String transferId;
  final Function(DpftpProgress)? onProgress;
  DateTime? _startTime;

  // Flow Control & Queue
  final int maxInFlightBytes; // Dynamic window size
  final int requestChunkCount; // Dynamic chunk request count
  final int chunkSize; // Dynamic chunk size

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
    int? chunkSize,
    int? maxInFlightBytes,
    this.onProgress,
  }) : chunkSize = chunkSize ?? Dpftp.defaultChunkSize,
       maxInFlightBytes = maxInFlightBytes ?? (16 * 1024 * 1024),
       requestChunkCount =
           (maxInFlightBytes ?? (16 * 1024 * 1024)) ~/
           (chunkSize ?? Dpftp.defaultChunkSize);

  Future<void> start() async {
    try {
      final fileSize = await file.length();
      // Open a file handle for each parallel connection for true parallel IO.
      for (int i = 0; i < parallelConnections; i++) {
        _rafs.add(await file.open(mode: FileMode.read));
      }
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

    // Proactively start sending chunks ("push" model)
    // Enqueue all chunks and let the pump and flow control manage the rate.
    _chunkQueue.addAll(
      List.generate(_serverInfo!.totalChunks, (index) => index),
    );
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
      if (_pushedBytes - _ackedBytes < maxInFlightBytes) {
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
        if (_pushedBytes - _ackedBytes >= maxInFlightBytes) {
          // Window Full
          _flowControlWait ??= Completer<void>();
          await _flowControlWait!.future;
          _flowControlWait = null;
        }

        // Queue might be empty if cleared externally (unlikely) or after notify
        if (_chunkQueue.isEmpty) break;

        final id = _chunkQueue.removeAt(0);

        // Send (Awaited but IO is separate from Control)
        // Cycle through available sockets (0, 1, 2, 3, 0, 1, 2, 3...)
        await _sendChunk(id, _socketIdx++ % parallelConnections);

      }
    } catch (e) {
      debugPrint('[DPFTP] Pump Error: $e');
    } finally {
      _isPumping = false;
    }
  }

  Future<void> _sendChunk(int id, int socketIndex) async {
    if (_rafs.isEmpty || _serverInfo == null) return;

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

    // Read using the dedicated file handle for this socket.
    final raf = _rafs[socketIndex];
    try {
      await raf.setPosition(offset);
      await raf.readInto(buffer);
    } catch (e) {
      debugPrint('[DPFTP] Read error: $e');
      rethrow;
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
    for (var raf in _rafs) {
      raf.close();
    }
    _rafs.clear();
  }
}
