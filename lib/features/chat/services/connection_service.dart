import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import '../models/connection_state.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fylooo/models/file_transfer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fylooo/services/notification_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter/services.dart';
import 'package:fylooo/features/wifi_direct/wifi_direct_service.dart';
import 'package:fylooo/features/dpftp/dpftp_service.dart';
import 'package:fylooo/services/database_service.dart';

// 🔬 PERF: Global profiling state
class _PerfMetrics {
  int _totalBytesReceived = 0;
  DateTime? _startTime;
  int _lastReportBytes = 0;

  void recordBytes(int bytes) {
    _totalBytesReceived += bytes;
    _startTime ??= DateTime.now();

    // Report every 10MB for more frequent updates
    if (_totalBytesReceived - _lastReportBytes >= (10 * 1024 * 1024)) {
      final elapsed = DateTime.now().difference(_startTime!);
      final mbps =
          (_totalBytesReceived * 8.0 / (elapsed.inMilliseconds / 1000.0)) /
          1000000;
      debugPrint(
        '[PERF] Socket arrival rate: ${mbps.toStringAsFixed(1)} Mbps (${_totalBytesReceived ~/ (1024 * 1024)} MB in ${elapsed.inSeconds}s)',
      );
      _lastReportBytes = _totalBytesReceived;
    }
  }

  void reset() {
    _totalBytesReceived = 0;
    _startTime = null;
    _lastReportBytes = 0;
  }
}

final _perfMetrics = _PerfMetrics();

// Binary frame helpers
Uint8List _int32(int value) {
  final b = ByteData(4);
  b.setInt32(0, value, Endian.big);
  return b.buffer.asUint8List();
}

int _readInt32(Uint8List data, int offset) {
  return ByteData.sublistView(
    data,
    offset,
    offset + 4,
  ).getUint32(0, Endian.big);
}

/// Service for managing device-to-device connections
class ConnectionService {
  // Perf/debug logging toggles. Keep these off for real transfers.
  static const bool _enablePerfLogs = false;
  static const bool _enableBinaryChunkLogs = false;
  static const int _binaryChunkLogEveryN = 256;
  // Magic byte sequence to identify frame start [AC, DC, 12, 34]
  static const int _frameMagic = 0xACDC1234;

  final String deviceName;
  List<Socket> _sockets = [];
  Socket? get _primarySocket => _sockets.isNotEmpty ? _sockets.first : null;
  ConnectionInfo? _currentConnection;
  final List<Function(DeviceMessage)> _messageListeners = [];
  final List<Function(ConnectionInfo)> _statusListeners = [];
  final List<DeviceMessage> _messageHistory = [];
  List<StreamSubscription> _socketSubscriptions = [];
  Timer? _keepAliveTimer;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  Timer? _errorResetTimer;
  final Map<String, _IncomingFile> _incomingFiles = {};
  final Map<String, FileOffer> _pendingOffers = {};
  final Map<String, _OutgoingTransfer> _outgoingTransfers = {};
  final Map<String, List<_PendingBinaryChunk>> _pendingBinary = {};
  final Map<String, Socket> _nativeReceiverSockets =
      {}; // Socket pool for native receiver per transfer
  final Map<String, int> _nativeReceiverLastFlush =
      {}; // Track last flush chunk index per transfer
  // Flow control: limit by bytes in-flight (instead of chunk count). Default 256MB.
  static const int _maxPendingBytes = 256 * 1024 * 1024; // 256MB
  // Keep old chunk-count constant for safety/backwards-compat but not used.
  static const int _maxPendingChunks = 4000;
  Future<void> _sendChain = Future.value();
  List<Future<void>> _sendChains = [];
  List<Future<void>> _incomingChains = [];
  final List<_FrameParser> _frameParsers = [];
  Completer<void>? _parallelAckCompleter;
  int _expectedParallelStreams = 1;
  final _wifiDirectFrameParser = _FrameParser();

  // WiFi Direct state
  final ValueNotifier<WifiDirectStatus> wifiDirectStatusNotifier =
      ValueNotifier(WifiDirectStatus.disconnected);
  bool _wifiDirectAttempted = false;
  bool _usingWifiDirect = false;

  // Track WiFi Direct connection details
  String? _wifiDirectIp;
  int? _wifiDirectPort;
  bool _isWifiDirectGroupOwner = false;

  // Getters for WiFi Direct details
  String? get wifiDirectIp => _wifiDirectIp;
  int? get wifiDirectPort => _wifiDirectPort;
  bool get isWifiDirectGroupOwner => _isWifiDirectGroupOwner;
  String? get remoteWifiDirectName => _remoteWifiDirectName;
  String? get remoteWifiDirectMac => _remotePeerAddress;
  String? get localWifiDirectMac => _localWifiDirectPeerId;
  final _wifiDirectService = WiFiDirectService();
  Timer? _wifiDirectRetryTimer;
  String? _remotePeerAddress; // Store remote device MAC for P2P
  String? _remoteWifiDirectPeerId; // Exchanged via chat to avoid guessing
  String? _localWifiDirectPeerId;
  String? _remoteWifiDirectName; // P2P device name (more reliable than MAC)
  String? _localWifiDirectName;
  String? _wifiDirectIpAddress; // Store the actual P2P IP address
  String? _remotePlatform; // Store remote OS for transfer optimization
  final int _localWifiDirectTieBreaker = math.Random().nextInt(
    1000000,
  ); // For P2P role negotiation

  bool _wifiDirectPreparing = false;
  StreamSubscription<WiFiDirectConnectionEvent>? _wifiDirectConnSub;
  // ... (skip lines) ...

  StreamSubscription<List<WiFiDirectPeer>>? _wifiDirectPeersSub;
  ServerSocket? _wifiDirectServer;
  Socket? _wifiDirectDataSocket;
  StreamSubscription? _wifiDirectDataSub;
  Future<void> _wifiDirectIncomingChain = Future.value();
  Future<void> _wifiDirectSendChain = Future.value();

  // Allow larger frame payloads (64MB) to support bigger chunk sizes if needed
  static const int _maxFramePayloadBytes = 64 * 1024 * 1024; // 64MB
  static const int _maxTransferIdBytes = 128;
  static const int dataPort = 53319; // Port for native Android data receiver
  // How often to flush to native receiver (in chunks). With 4MB chunks, 16
  // chunks ~= 64MB which reduces syscall/flush overhead on localhost.
  static const int _nativeReceiverFlushEveryChunks = 16;

  // 🚀 Use native receiver with optimized forwarding (targeting 50+ Mbps)
  static bool useNativeReceiver = true;
  // 🚀 Enable parallel TCP streams for non-Android platforms to boost speed
  // MODIFIED: Enable for Android as well to boost Hotspot speeds
  static bool get enableParallelTransfers => Platform.isAndroid || !kIsWeb;
  static const int parallelSockets = 4; // Number of parallel sockets

  // 🚀 Socket buffer optimization - Platform-specific constants
  // Windows uses different values than Unix/Linux/macOS/Android
  static int get _SOL_SOCKET => Platform.isWindows ? 0xFFFF : 1;
  static int get _SO_RCVBUF => Platform.isWindows ? 0x1002 : 8;
  static int get _SO_SNDBUF => Platform.isWindows ? 0x1001 : 7;
  static const int _BUFFER_SIZE =
      16 * 1024 * 1024; // 2MB (kernel may double to 4MB)

  // 🚀 Use DPFTP (Dart Parallel File Transfer Protocol) v1
  // For macOS connections, use false (standard socket transfer)
  // For all other platforms, use true (DPFTP)
  bool get useDpftp {
    // When connecting to macOS, disable DPFTP
    if (_remotePlatform == 'macos') {
      return true;
    }
    // For all other platforms (android, ios, windows, linux), use DPFTP
    return true;
  }

  /// Optimize socket buffers for high-speed transfer (all platforms)
  void _optimizeSocketBuffers(Socket socket, {bool verify = true}) {
    // Skip for web platform only
    if (kIsWeb) return;

    try {
      // Create buffer value as 4-byte integer in host byte order
      final bufferBytes = ByteData(4);
      bufferBytes.setInt32(0, _BUFFER_SIZE, Endian.host);
      final bufferValue = bufferBytes.buffer.asUint8List();

      // Set 2MB receive buffer (SO_RCVBUF)
      socket.setRawOption(
        RawSocketOption(_SOL_SOCKET, _SO_RCVBUF, bufferValue),
      );

      // Set 2MB send buffer (SO_SNDBUF)
      socket.setRawOption(
        RawSocketOption(_SOL_SOCKET, _SO_SNDBUF, bufferValue),
      );

      if (verify) {
        // Verify buffer sizes were applied
        try {
          final rcvOption = socket.getRawOption(
            RawSocketOption(_SOL_SOCKET, _SO_RCVBUF, Uint8List(4)),
          );
          final rcvSize = ByteData.sublistView(
            rcvOption,
          ).getInt32(0, Endian.host);

          final sndOption = socket.getRawOption(
            RawSocketOption(_SOL_SOCKET, _SO_SNDBUF, Uint8List(4)),
          );
          final sndSize = ByteData.sublistView(
            sndOption,
          ).getInt32(0, Endian.host);

          debugPrint(
            '[ConnectionService] 🚀 Socket buffers optimized - RCV: ${(rcvSize / 1024 / 1024).toStringAsFixed(1)}MB, SND: ${(sndSize / 1024 / 1024).toStringAsFixed(1)}MB',
          );
        } catch (e) {
          debugPrint(
            '[ConnectionService] ⚠️ Could not verify buffer sizes: $e',
          );
        }
      }
    } catch (e) {
      debugPrint(
        '[ConnectionService] ⚠️ Failed to optimize socket buffers: $e',
      );
    }
  }

  Future<void> _writeFrame(
    int type,
    Uint8List payload, {
    bool forceFlush = false,
  }) async {
    if (_primarySocket == null) return;

    // frame = [MAGIC:4][payloadLen:int32][type:1][payload]
    final payloadLen = 1 + payload.length;

    final buffer = BytesBuilder(copy: false);
    buffer.add(_int32(_frameMagic));
    buffer.add(_int32(payloadLen));
    buffer.add([type & 0xFF]);
    buffer.add(payload);

    try {
      _primarySocket!.add(buffer.takeBytes());
      if (forceFlush) {
        await _primarySocket!.flush();
      }
    } catch (e) {
      debugPrint('[ConnectionService] ❌ Error writing to socket: $e');

      // Socket is already closed/broken - don't propagate error to avoid cascading failures
      // Just return silently since we can't write anyway
      debugPrint(
        '[ConnectionService] Socket write failed (likely closed), ignoring.',
      );
      return; // Don't call _handleConnectionError to avoid double-close
      // Do not rethrow - prevents unhandled exceptions during cleanup
    }
  }

  Future<void> _writeFrameOnSocket(
    Socket socket,
    int type,
    Uint8List payload, {
    bool forceFlush = false,
  }) async {
    // frame = [MAGIC:4][payloadLen:int32][type:1][payload]
    final payloadLen = 1 + payload.length;

    final buffer = BytesBuilder(copy: false);
    buffer.add(_int32(_frameMagic));
    buffer.add(_int32(payloadLen));
    buffer.add([type & 0xFF]);
    buffer.add(payload);
    try {
      socket.add(buffer.takeBytes());
      if (forceFlush) {
        await socket.flush();
      }
    } catch (e) {
      debugPrint('[ConnectionService] ❌ Error writing to specific socket: $e');
      // If we can't write, likely the socket is dead.
      // We don't rethrow to avoid unhandled exceptions crashing the app,
      // but we should probably signal that this socket is bad.
    }
  }

  Future<void> _enqueueFrame(
    int type,
    Uint8List payload, {
    bool forceFlush = false,
  }) async {
    // Use _sendChains[0] if available (parallel sockets), otherwise use _sendChain
    // This ensures coordination with binary transfers
    if (_sendChains.isNotEmpty) {
      _sendChains[0] = _sendChains[0].then((_) async {
        await _writeFrame(type, payload, forceFlush: forceFlush);
      });
      await _sendChains[0];
    } else {
      // Fallback to _sendChain for single socket mode
      _sendChain = _sendChain.then((_) async {
        await _writeFrame(type, payload, forceFlush: forceFlush);
      });
      await _sendChain;
    }
  }

  Future<void> _enqueueWifiDirectFrame(
    int type,
    Uint8List payload, {
    bool forceFlush = false,
  }) async {
    final socket = _wifiDirectDataSocket;
    if (socket == null) return;

    _wifiDirectSendChain = _wifiDirectSendChain.then((_) async {
      await _writeFrameOnSocket(socket, type, payload, forceFlush: forceFlush);
    });
    await _wifiDirectSendChain;
  }

  Future<void> _sendControlMessage(
    DeviceMessage message, {
    bool preferWifiDirect = false,
  }) async {
    final json = jsonEncode(message.toJson());
    final payload = Uint8List.fromList(utf8.encode(json));

    if (preferWifiDirect && _wifiDirectDataSocket != null) {
      await _enqueueWifiDirectFrame(0, payload, forceFlush: true);
      return;
    }

    await _enqueueFrame(0, payload, forceFlush: true);
  }

  /// Send binary file chunk without JSON/base64 overhead
  /// Chunks are written directly without serialization (receiver re-orders by index)
  Future<void> _sendBinaryChunk({
    required String transferId,
    required int index,
    required bool isLast,
    required Uint8List bytes,
    bool flush = false,
  }) async {
    final targetSocket = _getTransferSocket(chunkIndex: index);
    if (targetSocket == null) return;

    // Find the actual index of targetSocket in _sockets list
    // This is critical for using the correct send chain
    int socketIndex = 0;
    if (!identical(targetSocket, _wifiDirectDataSocket)) {
      socketIndex = _sockets.indexOf(targetSocket);
      if (socketIndex == -1) {
        debugPrint(
          '[ConnectionService] ❌ targetSocket not found in _sockets list!',
        );
        return;
      }
    }

    final tid = utf8.encode(transferId);

    if (tid.length > _maxTransferIdBytes) {
      throw StateError('transferId too long (${tid.length} bytes)');
    }

    // Frame structure: [MAGIC:4][payloadLen:4][type:1][tidLen:1][tid:N][index:4][isLast:1][bytes:M]
    final payloadLen = 1 + 1 + tid.length + 4 + 1 + bytes.length;
    final tidLen = tid.length;

    final headerSize =
        4 + 4 + 1 + 1 + tidLen + 4 + 1; // Added 4 bytes for magic
    final header = Uint8List(headerSize);
    final bd = ByteData.view(header.buffer);

    int offset = 0;
    bd.setInt32(offset, _frameMagic, Endian.big);
    offset += 4;
    bd.setInt32(offset, payloadLen, Endian.big);
    offset += 4;
    header[offset++] = 1;
    header[offset++] = tidLen;
    header.setRange(offset, offset + tidLen, tid);
    offset += tidLen;
    bd.setInt32(offset, index, Endian.big);
    offset += 4;
    header[offset++] = isLast ? 1 : 0;

    Future<void> write() async {
      try {
        final combined = BytesBuilder(copy: false);
        combined.add(header);
        combined.add(bytes);
        targetSocket.add(combined.takeBytes());
        if (flush) {
          await targetSocket.flush();
        }
      } catch (e) {
        debugPrint('[ConnectionService] ❌ Error writing binary chunk: $e');
        // Safe to ignore, connection likely dead and will be handled by onError/onDone
      }
    }

    if (identical(targetSocket, _wifiDirectDataSocket)) {
      _wifiDirectSendChain = _wifiDirectSendChain.then((_) => write());
      if (flush) await _wifiDirectSendChain;
    } else {
      _sendChains[socketIndex] = _sendChains[socketIndex].then((_) => write());
      if (flush) await _sendChains[socketIndex];
    }
  }

  /// Send ACK for file transfer
  Future<void> _sendAck(
    String transferId,
    int nextExpectedIndex, {
    bool completed = false,
  }) async {
    final ack = FileAck(
      transferId: transferId,
      nextExpectedIndex: nextExpectedIndex,
      completed: completed,
    );
    await _sendControlMessage(
      DeviceMessage(
        type: 'file_ack',
        content: jsonEncode(ack.toJson()),
        senderName: deviceName,
      ),
      // If WiFi Direct is up, keep the ACK path on the same fast link.
      preferWifiDirect: _usingWifiDirect,
    );
  }

  /// Forward binary chunk to native Android receiver
  Future<void> _forwardToNativeReceiver(
    String transferId,
    int index,
    bool isLast,
    Uint8List bytes,
  ) async {
    // Verify transfer is registered before forwarding
    if (!_incomingFiles.containsKey(transferId)) {
      debugPrint(
        '[ConnectionService] ⚠️ Cannot forward chunk $index: transfer $transferId not registered yet',
      );
      throw StateError('Transfer not registered in _incomingFiles');
    }

    try {
      // Reuse existing socket for this transfer, or create a new one
      Socket? socket = _nativeReceiverSockets[transferId];
      if (socket == null) {
        socket = await Socket.connect('127.0.0.1', dataPort);
        socket.setOption(SocketOption.tcpNoDelay, true);
        _nativeReceiverSockets[transferId] = socket;
        _nativeReceiverLastFlush[transferId] = -1;
      }

      // 🚀 PERF: Write frame directly without BytesBuilder allocations
      final tid = utf8.encode(transferId);
      final tidLen = tid.length;
      final payloadLen = 1 + tidLen + 4 + 1 + bytes.length;

      // Write frame: [payloadLen:4][tidLen:1][tid][index:4][isLast:1][bytes]
      // Combine header into one buffer
      final headerSize = 4 + 1 + tidLen + 4 + 1;
      final header = Uint8List(headerSize);
      final bd = ByteData.view(header.buffer);

      int offset = 0;
      bd.setInt32(offset, payloadLen, Endian.big);
      offset += 4;
      header[offset++] = tidLen;
      header.setRange(offset, offset + tidLen, tid);
      offset += tidLen;
      bd.setInt32(offset, index, Endian.big);
      offset += 4;
      header[offset++] = isLast ? 1 : 0;

      socket.add(header);
      socket.add(bytes);

      // Batch flushes to reduce syscall overhead on localhost
      final lastFlush = _nativeReceiverLastFlush[transferId] ?? -1;
      if (isLast ||
          (index - lastFlush >=
              ConnectionService._nativeReceiverFlushEveryChunks)) {
        await socket.flush();
        _nativeReceiverLastFlush[transferId] = index;
      }

      // Close socket only if this is the last chunk
      if (isLast) {
        try {
          await socket.close();
        } catch (e) {
          debugPrint('[ConnectionService] ⚠️ Error closing native socket: $e');
        }
        _nativeReceiverSockets.remove(transferId);
        _nativeReceiverLastFlush.remove(transferId);
      }
    } catch (e) {
      debugPrint(
        '[ConnectionService] ❌ Failed to forward chunk to native receiver: $e',
      );
      // Clean up socket on error
      try {
        _nativeReceiverSockets[transferId]?.close();
      } catch (_) {}
      _nativeReceiverSockets.remove(transferId);
      rethrow;
    }
  }

  ConnectionService({required this.deviceName}) {
    // Prune old messages on startup/service creation
    DatabaseService().pruneOldMessages();

    debugPrint(
      '[ConnectionService] 🆕 NEW ConnectionService instance created for device: $deviceName ($hashCode)',
    );

    // Set up native receiver progress channel for Android
    if (Platform.isAndroid) {
      const nativeReceiverProgressChannel = MethodChannel(
        'com.omnity.fylooo/native_receiver_progress',
      );
      nativeReceiverProgressChannel.setMethodCallHandler(
        _handleNativeReceiverProgress,
      );
    }

    if (Platform.isAndroid) {
      cleanupOldReceivedFiles().catchError((e) {
        debugPrint('[ConnectionService] ⚠️ Startup cleanup error: $e');
      });
    }

    if (useDpftp) {
      // Set up DPFTP progress listener ONCE in constructor
      // This persists across receiver restarts (from Settings, file_offer prompts, etc.)
      DpftpService().progress.listen((p) {
        _notifyMessageListeners(
          DeviceMessage(
            type: 'file_progress',
            content: p.transferId,
            senderName: deviceName,
            timestamp: DateTime.now(),
            metadata: {
              'transferId': p.transferId,
              'bytes': (p.bytesTransferred > p.totalBytes)
                  ? p.totalBytes
                  : p.bytesTransferred,
              'total': p.totalBytes,
              'outgoing': p.isOutgoing,
              'path': p.filePath,
            },
          ),
        );

        // If complete, signal UI completion
        if (p.isComplete) {
          debugPrint(
            '[ConnectionService] 🏁 DPFTP Transfer ${p.transferId} Complete. Signaling UI.',
          );

          // Get file name from legacy offer if available
          final name =
              _incomingFiles[p.transferId]?.offer.fileName ??
              p.filePath?.split(Platform.pathSeparator).last ??
              'Unknown File';

          _notifyMessageListeners(
            DeviceMessage(
              type: 'file_complete',
              content: name,
              senderName: p.isOutgoing
                  ? deviceName
                  : (_currentConnection?.deviceName ?? 'Unknown'),
              timestamp: DateTime.now(),
              metadata: {
                'transferId': p.transferId,
                'path': p.filePath,
                'size': p.totalBytes,
                'outgoing': p.isOutgoing,
                'durationMs': p.durationMs,
              },
            ),
          );
        }
      });

      _initDpftp();
    }
  }

  Future<void> _initDpftp() async {
    try {
      Directory? dir;
      if (Platform.isAndroid || Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        // Desktop: Check for saved download location preference
        final prefs = await SharedPreferences.getInstance();
        final savedPath = prefs.getString('download_save_path');

        if (savedPath != null && savedPath.isNotEmpty) {
          dir = Directory(savedPath);
          if (!await dir.exists()) {
            // Saved path no longer exists, clear it
            await prefs.remove('download_save_path');
            dir = null;
          } else {
            // Test if we have write permission
            try {
              final testFile = File('${dir.path}/.cpft_permission_test');
              await testFile.writeAsString('test');
              await testFile.delete();
            } catch (e) {
              // No write permission, clear the saved path and prompt
              debugPrint(
                '[ConnectionService] No write permission to $savedPath: $e',
              );
              await prefs.remove('download_save_path');
              dir = null;
            }
          }
        }

        // If no saved location on desktop, don't initialize receiver yet
        // Will prompt when actually receiving a file
        if (dir == null) {
          debugPrint(
            '[ConnectionService] No download location set, will prompt on file reception',
          );
          return; // Don't start receiver yet
        }
      }

      // Start receiver (progress listener already set up in constructor)
      await DpftpService().startReceiver(saveDirectory: dir.path);
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️ Failed to init DPFTP: $e');
    }
  }

  /// Get current connection info
  ConnectionInfo? get currentConnection => _currentConnection;

  /// Check if connected
  bool get isConnected =>
      _currentConnection?.status == ConnectionStatus.connected;

  /// Check if using WiFi Direct for data transfer
  bool get isUsingWifiDirect => _usingWifiDirect;

  /// Check if WiFi Direct connection is available but not yet established
  /// Only available when BOTH devices are Android (WiFi Direct is Android-only)
  bool get canConnectWifiDirect =>
      Platform.isAndroid &&
      _remotePlatform == 'android' && // Remote device must also be Android
      isConnected &&
      !_usingWifiDirect &&
      !_wifiDirectAttempted;

  /// Manually trigger WiFi Direct connection attempt
  Future<void> connectWifiDirect() async {
    if (!Platform.isAndroid || !isConnected || _wifiDirectAttempted) {
      return;
    }
    await _attemptWiFiDirectUpgrade();
  }

  /// Get pending file offers
  Map<String, FileOffer> get pendingOffers => Map.unmodifiable(_pendingOffers);

  /// Get message history
  List<DeviceMessage> getMessageHistory() => List.unmodifiable(_messageHistory);

  /// Add message listener
  void addMessageListener(Function(DeviceMessage) listener) {
    _messageListeners.add(listener);
  }

  /// Remove message listener
  void removeMessageListener(Function(DeviceMessage) listener) {
    _messageListeners.remove(listener);
  }

  /// Add status listener
  void addStatusListener(Function(ConnectionInfo) listener) {
    _statusListeners.add(listener);
  }

  /// Remove status listener
  void removeStatusListener(Function(ConnectionInfo) listener) {
    _statusListeners.remove(listener);
  }

  /// Connect to a device
  Future<bool> connect(
    String deviceName,
    String ipAddress,
    int port, {
    String? p2pPeerId,
  }) async {
    debugPrint(
      '[ConnectionService] 🔌 Connecting to $deviceName at $ipAddress:$port (P2P: $p2pPeerId)',
    );

    if (currentConnection?.status == ConnectionStatus.connecting) return false;
    if (currentConnection?.status == ConnectionStatus.connected) return true;

    // CRITICAL: Prevent self-connections
    if (ipAddress == '127.0.0.1' ||
        ipAddress == '::1' ||
        ipAddress == '0.0.0.0') {
      debugPrint(
        '[ConnectionService] ❌ Cannot connect to loopback address: $ipAddress',
      );
      return false;
    }

    if (_sockets.isNotEmpty) {
      debugPrint('[ConnectionService] Disconnecting from previous connection');
      await disconnect();
    }

    _updateStatus(
      ConnectionInfo(
        deviceName: deviceName,
        ipAddress: ipAddress,
        port: port,
        status: ConnectionStatus.connecting,
      ),
    );

    try {
      // Step 0: Check for P2P priority
      if (p2pPeerId != null && Platform.isAndroid) {
        debugPrint(
          '[ConnectionService] 📡 Priority: Attempting WiFi Direct P2P connection first...',
        );

        try {
          final p2pConn = await _wifiDirectService.connect(p2pPeerId);
          if (p2pConn != null) {
            debugPrint(
              '[ConnectionService] 🚀 WiFi Direct connected! IP: ${p2pConn.ipAddress}, Port: ${p2pConn.port}',
            );
            ipAddress = p2pConn.ipAddress;
            port = p2pConn.port;
            _usingWifiDirect = true;
          } else {
            debugPrint(
              '[ConnectionService] ⚠️ WiFi Direct connection failed, falling back to standard IP: $ipAddress',
            );
          }
        } catch (e) {
          debugPrint(
            '[ConnectionService] ⚠️ WiFi Direct error: $e. Falling back.',
          );
        }
      } else if (ipAddress == '0.0.0.0' && p2pPeerId != null) {
        // P2P-only device but failed above? Retry strictly P2P or fail
        debugPrint(
          '[ConnectionService] 📡 P2P-only device, retrying P2P connect...',
        );
        final p2pConn = await _wifiDirectService.connect(p2pPeerId);
        if (p2pConn != null) {
          ipAddress = p2pConn.ipAddress;
          port = p2pConn.port;
          _usingWifiDirect = true;
        } else {
          throw SocketException(
            'Failed to connect to P2P device and no fallback IP available',
          );
        }
      }

      // Step 1: Connect primary socket
      final primarySocket = await Socket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 10),
      );
      _sockets.add(primarySocket);
      _sendChains.add(Future.value());
      _incomingChains.add(Future.value());
      _frameParsers.add(_FrameParser());
      primarySocket.setOption(SocketOption.tcpNoDelay, true);
      _optimizeSocketBuffers(primarySocket);
      final sub = primarySocket.listen(
        (data) => _handleIncomingData(data, 0),
        onError: (e) => _handleConnectionError(e.toString()),
        onDone: () => disconnect(),
      );
      _socketSubscriptions.add(sub);
      debugPrint('[ConnectionService] ✅ Primary socket connected');

      // Detect WiFi Direct P2P network by IP address (for QR-based connections)
      // Detect WiFi Direct P2P network by IP address
      if (ipAddress.startsWith('192.168.49.')) {
        // Don't set _usingWifiDirect = true yet! Wait for handshake to confirm peer is Android.
        debugPrint(
          '[ConnectionService] 📡 Detected potential WiFi Direct P2P network: $ipAddress (waiting for handshake)',
        );
      }

      // If we connected via standard TCP but have a p2pPeerId, we might want to upgrade later
      // The current _attemptWiFiDirectUpgrade logic handles this via "wifi_direct_offer"
      if (p2pPeerId != null && Platform.isAndroid) {
        _remoteWifiDirectPeerId = p2pPeerId;
        _attemptWiFiDirectUpgrade();
      }

      // Step 2: Send handshake and parallel request
      await _sendHandshake();
      final int streams = enableParallelTransfers ? parallelSockets : 1;
      if (streams > 1) {
        try {
          _parallelAckCompleter = Completer<void>();
          await sendMessage(
            DeviceMessage(
              type: 'parallel_request',
              content: streams.toString(),
              senderName: deviceName,
            ),
          );
          debugPrint(
            '[ConnectionService] 📤 Sent parallel_request for $streams streams',
          );

          await _parallelAckCompleter!.future.timeout(
            const Duration(seconds: 5),
          );
          debugPrint('[ConnectionService] ✅ Received parallel_ack');

          // Step 3: Connect parallel sockets
          for (int i = 1; i < streams; i++) {
            try {
              debugPrint(
                '[ConnectionService] 🔌 Connecting parallel socket ${i + 1}/$streams...',
              );
              final socket = await Socket.connect(
                ipAddress,
                port,
                timeout: const Duration(seconds: 10),
              );
              _sockets.add(socket);
              _sendChains.add(Future.value());
              _incomingChains.add(Future.value());
              _frameParsers.add(_FrameParser());
              socket.setOption(SocketOption.tcpNoDelay, true);
              _optimizeSocketBuffers(
                socket,
                verify: false,
              ); // Skip verify for parallel sockets
              final sub = socket.listen(
                (data) => _handleIncomingData(data, i),
                onError: (e) {
                  debugPrint(
                    '[ConnectionService] ❌ Parallel socket $i error: $e',
                  );
                  _handleConnectionError(e.toString());
                },
                onDone: () {
                  debugPrint(
                    '[ConnectionService] 🔌 Parallel socket $i closed',
                  );
                  disconnect();
                },
              );
              _socketSubscriptions.add(sub);
              debugPrint(
                '[ConnectionService] ✅ Socket ${i + 1}/$streams connected',
              );
            } catch (e) {
              debugPrint(
                '[ConnectionService] ❌ Failed to connect parallel socket ${i + 1}: $e',
              );
              // Don't fail the entire connection if one parallel socket fails
              // Just continue with fewer sockets
              break;
            }
          }

          debugPrint(
            '[ConnectionService] 📊 Connected ${_sockets.length}/$streams sockets',
          );

          // Wait a bit to ensure all sockets are fully established
          await Future.delayed(const Duration(milliseconds: 500));

          // Verify all sockets are still connected
          final connectedCount = _sockets.length;
          debugPrint(
            '[ConnectionService] 🔍 Verifying sockets: $connectedCount/$streams',
          );

          if (connectedCount < streams) {
            debugPrint(
              '[ConnectionService] ⚠️ Not all parallel sockets connected, expected $streams but got $connectedCount',
            );
            // Continue anyway with fewer sockets
          }

          // Step 4: Send ready message
          await sendMessage(
            DeviceMessage(
              type: 'parallel_ready',
              senderName: deviceName,
              content: connectedCount.toString(), // Send actual count
            ),
          );
          debugPrint(
            '[ConnectionService] 📤 Sent parallel_ready with $connectedCount sockets',
          );
        } on TimeoutException {
          debugPrint(
            '[ConnectionService] ⚠️ parallel_ack timeout, falling back to single stream',
          );
        }
      }

      // Don't set status to connected yet - wait for handshake response
      // The status will be updated to connected when we receive the handshake
      // response in _handleIncomingMessage
      // _updateStatus(
      //   _currentConnection!.copyWith(
      //     status: ConnectionStatus.connected,
      //     connectedAt: DateTime.now(),
      //   ),
      // );
      _startKeepAlive();
      _attemptWiFiDirectUpgrade();

      return true;
    } on SocketException catch (e) {
      await disconnect(); // Ensure cleanup on partial failure
      String userFriendlyError;
      if (e.osError?.errorCode == 61 ||
          e.message.contains('Connection refused')) {
        userFriendlyError =
            'The other device is not ready to accept connections.\n\n'
            'Please make sure:\n'
            '1. The app is running on the other device\n'
            '2. The app has been restarted recently (to apply updates)\n'
            '3. Both devices are on the same WiFi network';
      } else if (e.osError?.errorCode == 60 ||
          e.message.contains('timed out')) {
        userFriendlyError =
            'Connection timed out.\n\n'
            'Please check:\n'
            '1. The device is still on the network\n'
            '2. No firewall is blocking port 53318';
      } else {
        userFriendlyError = 'Network error: ${e.message}';
      }

      debugPrint('[ConnectionService] ❌ Connection failed: $e');
      debugPrint('[ConnectionService] 💡 User message: $userFriendlyError');

      _updateStatus(
        ConnectionInfo(
          deviceName: deviceName,
          ipAddress: ipAddress,
          port: port,
          status: ConnectionStatus.failed,
          error: userFriendlyError,
        ),
      );
      return false;
    } catch (e) {
      await disconnect(); // Ensure cleanup on partial failure
      debugPrint('[ConnectionService] ❌ Connection failed: $e');
      _updateStatus(
        ConnectionInfo(
          deviceName: deviceName,
          ipAddress: ipAddress,
          port: port,
          status: ConnectionStatus.failed,
          error: e.toString(),
        ),
      );
      return false;
    }
  }

  /// Accept an incoming connection (for server-side connections)
  Future<bool> acceptConnection(Socket socket, String deviceName) async {
    debugPrint(
      '[ConnectionService] 📞 Accepting incoming connection from $deviceName',
    );
    debugPrint(
      '[ConnectionService] 🔍 Socket info: ${socket.remoteAddress.address}:${socket.remotePort}',
    );

    // MODIFIED: Handle parallel connections
    final incomingIp = socket.remoteAddress.address;
    if (_currentConnection != null &&
        _normalizeIp(_currentConnection!.ipAddress) ==
            _normalizeIp(incomingIp) &&
        (_currentConnection!.status == ConnectionStatus.connecting ||
            _currentConnection!.status == ConnectionStatus.connected)) {
      debugPrint(
        '[ConnectionService] 📞 Accepting parallel stream from $deviceName',
      );
    } else if (_sockets.isNotEmpty) {
      debugPrint(
        '[ConnectionService] ⚠️  Existing connection, performing silent cleanup for replacement...',
      );
      await _cleanupForReplacement();
      await Future.delayed(const Duration(milliseconds: 100));
      debugPrint(
        '[ConnectionService] ✅ Previous connection cleaned up (silent)',
      );
    }

    try {
      _sockets.add(socket);
      _sendChains.add(Future.value());
      _incomingChains.add(Future.value());
      _frameParsers.add(_FrameParser());
      final ipAddress = socket.remoteAddress.address;
      final port = socket.remotePort;

      if (_currentConnection == null ||
          (_currentConnection!.status != ConnectionStatus.connecting &&
              _currentConnection!.status != ConnectionStatus.connected)) {
        _updateStatus(
          ConnectionInfo(
            deviceName: deviceName,
            ipAddress: ipAddress,
            port: port,
            status: ConnectionStatus.connecting,
          ),
        );
      }

      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
        _optimizeSocketBuffers(socket, verify: false); // Incoming socket
        debugPrint(
          '[ConnectionService] ✅ Socket options configured (tcpNoDelay)',
        );
      } catch (e) {
        debugPrint('[ConnectionService] ⚠️  Failed to set socket options: $e');
      }

      // Detect WiFi Direct P2P network by IP address (for incoming connections)
      // Detect WiFi Direct P2P network by IP address (for incoming connections)
      if (ipAddress.startsWith('192.168.49.')) {
        // Don't set _usingWifiDirect = true yet! Wait for handshake to confirm peer is Android.
        debugPrint(
          '[ConnectionService] 📡 Incoming connection from potential WiFi Direct P2P network: $ipAddress',
        );
      }

      debugPrint('[ConnectionService] 🎧 Setting up socket listener...');
      try {
        final sub = socket.listen(
          (data) => _handleIncomingData(data, _sockets.length - 1),
          onError: (error) {
            debugPrint('[ConnectionService] ❌ Socket error: $error');
            _handleConnectionError(error.toString());
          },
          onDone: () {
            debugPrint('[ConnectionService] 🔌 Socket closed by remote');
            disconnect();
          },
          cancelOnError: false,
        );
        _socketSubscriptions.add(sub);
        debugPrint(
          '[ConnectionService] ✅ Socket listener attached successfully',
        );
      } catch (e) {
        debugPrint(
          '[ConnectionService] ❌ Failed to attach socket listener: $e',
        );
        throw Exception('Failed to listen to socket: $e');
      }

      // Send handshake to notify the initiator that we've accepted the connection
      await _sendHandshake();
      debugPrint('[ConnectionService] 📤 Sent handshake to initiator');

      // Keep status as connecting - will transition to connected when we receive
      // the handshake response from the initiator
      // Update connection status
      // _updateStatus(
      //   ConnectionInfo(
      //     deviceName: deviceName,
      //     ipAddress: ipAddress,
      //     port: port,
      //     status: ConnectionStatus.connected,
      //     connectedAt: DateTime.now(),
      //   ),
      // );

      debugPrint('[ConnectionService] ✅ Accepted connection from $deviceName');
      return true;
    } catch (e) {
      debugPrint('[ConnectionService] ❌ Failed to accept connection: $e');
      _updateStatus(
        ConnectionInfo(
          deviceName: deviceName,
          ipAddress: socket.remoteAddress.address,
          port: socket.remotePort,
          status: ConnectionStatus.failed,
          error: e.toString(),
        ),
      );
      return false;
    }
  }

  /// Send handshake message
  Future<void> _sendHandshake() async {
    final handshake = DeviceMessage(
      type: 'handshake',
      content: 'Hello from $deviceName',
      senderName: deviceName,
      metadata: {
        'platform': Platform.operatingSystem, // Send our platform
      },
    );
    await sendMessage(handshake);
  }

  /// Attempt to upgrade connection to WiFi Direct for faster transfers
  Future<void> _attemptWiFiDirectUpgrade() async {
    if (_wifiDirectAttempted) return;
    _wifiDirectAttempted = true;
    // return;
    // Only attempt WiFi Direct on Android
    if (!Platform.isAndroid) {
      debugPrint('[ConnectionService] 📡 WiFi Direct: Not Android, skipping');
      return;
    }

    // Skip if already on WiFi Direct P2P network (192.168.49.x)
    if (_currentConnection?.ipAddress.startsWith('192.168.49.') ?? false) {
      debugPrint(
        '[ConnectionService] 📡 Already on WiFi Direct P2P network (${_currentConnection?.ipAddress}), skipping upgrade',
      );
      return;
    }

    wifiDirectStatusNotifier.value = WifiDirectStatus.connecting;

    // ⏰ Timeout fallback: If not connected within 60s, revert status so UI doesn't hang
    // This effectively falls back to standard DPFTP (since _usingWifiDirect remains false)
    Timer(const Duration(minutes: 1), () {
      if (!isUsingWifiDirect &&
          wifiDirectStatusNotifier.value == WifiDirectStatus.connecting) {
        debugPrint(
          '[ConnectionService] ⏰ WiFi Direct upgrade timed out after 60s. Fallback to DPFTP.',
        );
        wifiDirectStatusNotifier.value = WifiDirectStatus.disconnected;
        // _wifiDirectAttempted remains true to prevent retry loops
      }
    });

    try {
      debugPrint('[ConnectionService] 📡 Attempting WiFi Direct upgrade...');

      // Pre-fetch our local P2P id/name so we can exchange it.
      await _wifiDirectService.initialize();
      if (_wifiDirectService.isSupported) {
        final self = await _wifiDirectService.getThisDevice();
        _localWifiDirectPeerId = self?.id;
        _localWifiDirectName = self?.name;
      }

      debugPrint(
        '[ConnectionService] 📡 WiFi Direct: local p2pId=$_localWifiDirectPeerId, p2pName=$_localWifiDirectName',
      );

      // Send WiFi Direct capability announcement
      await sendMessage(
        DeviceMessage(
          type: 'wifi_direct_offer',
          content: 'WiFi Direct capable',
          senderName: deviceName,
          metadata: {
            'platform': 'android',
            if (_localWifiDirectPeerId != null) 'p2pId': _localWifiDirectPeerId,
            if (_localWifiDirectName != null) 'p2pName': _localWifiDirectName,
            'tieBreaker': _localWifiDirectTieBreaker,
          },
        ),
      );
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️  WiFi Direct upgrade failed: $e');
    }
  }

  Future<void> _prepareWiFiDirectUpgrade({required bool initiator}) async {
    if (!Platform.isAndroid) return;
    if (_wifiDirectPreparing) return;
    if (_wifiDirectDataSocket != null) return;

    _wifiDirectPreparing = true;
    try {
      await _wifiDirectService.initialize();
      if (!_wifiDirectService.isSupported) {
        debugPrint('[ConnectionService] 📡 WiFi Direct not supported');
        return;
      }

      final self = await _wifiDirectService.getThisDevice();
      _localWifiDirectPeerId = self?.id;
      _localWifiDirectName = self?.name;

      _wifiDirectConnSub ??= _wifiDirectService.connectionStream.listen(
        (event) {
          if (event.isLost) {
            debugPrint('[ConnectionService] 📡 WiFi Direct connection lost');
            _teardownWifiDirectDataSocket();
            return;
          }
          final ip = event.ipAddress;
          final port = event.port;
          if (ip == null || port == null) return;
          _usingWifiDirect = true;

          // Store connection details
          _wifiDirectIp = ip;
          _wifiDirectPort = port;
          _isWifiDirectGroupOwner = event.isGroupOwner;

          _ensureWifiDirectDataSocket(
            ipAddress: ip,
            port: port,
            isGroupOwner: event.isGroupOwner,
          );
        },
        onError: (e) {
          debugPrint('[ConnectionService] ⚠️  WiFi Direct event error: $e');
        },
      );

      // Start discovery on both sides to ensure receiver is registered.
      await _wifiDirectService.startDiscovery();

      if (!initiator) return;

      _wifiDirectPeersSub?.cancel();
      _wifiDirectPeersSub = _wifiDirectService.peersStream.listen(
        (peers) async {
          if (peers.isEmpty) return;

          // Match by p2pName (most reliable) or p2pId if available.
          final targetName = _remoteWifiDirectName;
          final targetId = _remoteWifiDirectPeerId;

          WiFiDirectPeer? match;
          if (targetName != null && targetName.isNotEmpty) {
            // Prefer exact name match
            match = peers.where((p) => p.name == targetName).firstOrNull;
            if (match == null) {
              debugPrint(
                '[ConnectionService] 📡 WiFi Direct: waiting for peer with name="$targetName" (found: ${peers.map((p) => p.name).join(", ")})',
              );
              return;
            }
          } else if (targetId != null && !targetId.startsWith('02:00:00:00')) {
            // Fallback to ID if not masked
            match = peers.where((p) => p.id == targetId).firstOrNull;
            if (match == null) return;
          } else {
            debugPrint(
              '[ConnectionService] 📡 WiFi Direct: no reliable remote identifier, skipping auto-connect',
            );
            return;
          }

          if (_remotePeerAddress == match.id)
            return; // already connecting/connected
          _remotePeerAddress = match.id;

          debugPrint(
            '[ConnectionService] 📡 WiFi Direct connecting to matched peer: ${match.name} (${match.id})',
          );

          try {
            await _wifiDirectService.connect(match.id);
          } catch (_) {
            _remotePeerAddress = null;
          }
        },
        onError: (e) {
          debugPrint('[ConnectionService] ⚠️  WiFi Direct peers error: $e');
        },
      );
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️  WiFi Direct prepare failed: $e');
    } finally {
      _wifiDirectPreparing = false;
    }
  }

  /// Get socket for data transfer (P2P if available, otherwise regular socket)
  Socket? _getTransferSocket({int? chunkIndex}) {
    if (_wifiDirectDataSocket != null) return _wifiDirectDataSocket;
    if (_sockets.isEmpty) return null;
    if (chunkIndex == null || _sockets.length == 1) return _sockets.first;
    return _sockets[chunkIndex % _sockets.length];
  }

  Future<void> _ensureWifiDirectDataSocket({
    required String ipAddress,
    required int port,
    required bool isGroupOwner,
  }) async {
    if (_wifiDirectDataSocket != null) return;
    if (_wifiDirectPreparing) return; // Already setting up

    _wifiDirectPreparing = true;
    _wifiDirectRetryTimer?.cancel();
    wifiDirectStatusNotifier.value = WifiDirectStatus.connecting;

    try {
      if (isGroupOwner) {
        debugPrint(
          '[ConnectionService] 🚀 WiFi Direct: binding server on :$port',
        );
        if (_wifiDirectServer == null) {
          _wifiDirectServer = await ServerSocket.bind(
            InternetAddress.anyIPv4,
            port,
            shared: true,
          );
        }
        // Use loop to filter out unwanted connections (e.g. self-connects from other services)
        await for (final socket in _wifiDirectServer!) {
          final remoteIp = socket.remoteAddress.address;
          debugPrint(
            '[ConnectionService] 📡 WiFi Direct: Accepted connection from $remoteIp',
          );

          // prevent self-connection (loopback or own IP)
          if (socket.remoteAddress.isLoopback ||
              remoteIp == '127.0.0.1' ||
              remoteIp == '::1' ||
              remoteIp == ipAddress) {
            debugPrint(
              '[ConnectionService] ⚠️  Ignoring loopback/self connection from $remoteIp',
            );
            socket.destroy();
            continue;
          }

          // Valid peer connection
          await _attachWifiDirectDataSocket(socket);
          break; // Stop accepting for now (1-to-1 P2P)
        }
      } else {
        debugPrint(
          '[ConnectionService] 🚀 WiFi Direct: connecting to $ipAddress:$port',
        );

        if (ipAddress == '127.0.0.1' ||
            ipAddress == '0.0.0.0' ||
            ipAddress == '::1') {
          throw StateError(
            'Cannot connect to loopback address ($ipAddress) in WiFi Direct Client mode',
          );
        }

        Socket? socket;
        for (int attempt = 1; attempt <= 5; attempt++) {
          try {
            socket = await Socket.connect(
              ipAddress,
              port,
              timeout: const Duration(seconds: 5),
            );
            break;
          } catch (e) {
            if (attempt == 5) rethrow;
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
        if (socket == null) {
          throw StateError('WiFi Direct connect failed');
        }
        await _attachWifiDirectDataSocket(socket);
      }

      await _wifiDirectService.stopDiscovery();
      debugPrint('[ConnectionService] ✅ WiFi Direct data socket ready');
      wifiDirectStatusNotifier.value = WifiDirectStatus.connected;

      // CRITICAL FIX: Store the PEER's IP for DPFTP usage
      // - Group Owner: Use client's IP (from socket.remoteAddress)
      // - Client: Use Group Owner's IP (from ipAddress parameter)
      if (isGroupOwner) {
        _wifiDirectIpAddress = _wifiDirectDataSocket!.remoteAddress.address;
        debugPrint(
          '[ConnectionService] 📍 Group Owner storing client IP for DPFTP: $_wifiDirectIpAddress',
        );
      } else {
        _wifiDirectIpAddress = ipAddress; // Client stores GO IP
        debugPrint(
          '[ConnectionService] 📍 Client storing GO IP for DPFTP: $_wifiDirectIpAddress',
        );
      }
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️  WiFi Direct data socket failed: $e');
      _teardownWifiDirectDataSocket();

      // 🔄 Retry logic: Keep trying to connect if failed
      wifiDirectStatusNotifier.value = WifiDirectStatus.failed;
      debugPrint(
        '[ConnectionService] 🔄 Scheduling WiFi Direct retry in 5s...',
      );
      _wifiDirectRetryTimer = Timer(const Duration(seconds: 5), () {
        debugPrint('[ConnectionService] 🔄 Retrying WiFi Direct connection...');
        _ensureWifiDirectDataSocket(
          ipAddress: ipAddress,
          port: port,
          isGroupOwner: isGroupOwner,
        );
      });
    } finally {
      _wifiDirectPreparing = false;
    }
  }

  Future<void> _attachWifiDirectDataSocket(Socket socket) async {
    final remoteAddr = socket.remoteAddress;
    debugPrint(
      '[ConnectionService] 🔗 Attaching WiFi Direct socket from ${remoteAddr.address}:${socket.remotePort}',
    );

    // CRITICAL: Final safety check - reject loopback connections
    if (remoteAddr.isLoopback ||
        remoteAddr.address == '127.0.0.1' ||
        remoteAddr.address == '::1' ||
        remoteAddr.address == '0.0.0.0') {
      debugPrint(
        '[ConnectionService] ❌ REJECTED loopback WiFi Direct socket from ${remoteAddr.address}',
      );
      socket.destroy();
      throw StateError('Cannot attach loopback WiFi Direct socket');
    }

    _wifiDirectDataSocket = socket;

    // 🚀 CRITICAL: Optimize WiFi Direct P2P socket for maximum throughput
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      debugPrint(
        '[ConnectionService] 🚀 WiFi Direct socket optimized (TCP_NODELAY)',
      );
    } catch (e) {
      debugPrint(
        '[ConnectionService] ⚠️  Could not optimize WiFi Direct socket: $e',
      );
    }

    await _wifiDirectDataSub?.cancel();
    _wifiDirectDataSub = socket.listen(
      _handleIncomingWiFiDirectData,
      onError: (error) {
        debugPrint('[ConnectionService] ⚠️  WiFi Direct socket error: $error');
        _teardownWifiDirectDataSocket();
      },
      onDone: () {
        debugPrint('[ConnectionService] 📡 WiFi Direct socket closed');
        _teardownWifiDirectDataSocket();
      },
      cancelOnError: false,
    );
  }

  void _handleIncomingWiFiDirectData(List<int> data) {
    _perfMetrics.recordBytes(data.length);

    _wifiDirectIncomingChain = _wifiDirectIncomingChain
        .then((_) async {
          await _wifiDirectFrameParser.process(Uint8List.fromList(data), this);
        })
        .catchError((e) {
          debugPrint('[ConnectionService] ❌ WiFi Direct incoming error: $e');
        });
  }

  void _teardownWifiDirectDataSocket() {
    wifiDirectStatusNotifier.value = WifiDirectStatus.disconnected;
    _wifiDirectRetryTimer?.cancel();

    try {
      _wifiDirectDataSub?.cancel();
    } catch (_) {}
    _wifiDirectDataSub = null;

    try {
      _wifiDirectDataSocket?.destroy();
    } catch (_) {}
    _wifiDirectDataSocket = null;

    try {
      _wifiDirectServer?.close();
    } catch (_) {}
    _wifiDirectServer = null;

    _wifiDirectFrameParser.reset();
    _wifiDirectIncomingChain = Future.value();
    _wifiDirectSendChain = Future.value();
  }

  /// Send a message to connected device
  Future<bool> sendMessage(DeviceMessage message) async {
    if (_primarySocket == null) {
      debugPrint('[ConnectionService] ❌ No active connection');
      return false;
    }
    try {
      final json = jsonEncode(message.toJson());
      await _enqueueFrame(
        0,
        Uint8List.fromList(utf8.encode(json)),
        forceFlush: true,
      );

      debugPrint(
        '[ConnectionService] 📤 Sent message: ${message.type} to $deviceName',
      );

      // Add outgoing message to history (not via listener to avoid duplicate notification)
      const historyTypes = {'text', 'file_complete', 'file_offer', 'goodbye'};
      if (historyTypes.contains(message.type)) {
        _messageHistory.add(message);
        // Persist outgoing message to DB
        if (_currentConnection != null) {
          DatabaseService().insertMessage(
            message,
            _currentConnection!.deviceName,
          );
        }
      }

      if (_consecutiveErrors > 0) {
        debugPrint(
          '[ConnectionService] ✅ Message sent successfully, resetting error count',
        );
        _consecutiveErrors = 0;
        _errorResetTimer?.cancel();
      }

      return true;
    } catch (e) {
      debugPrint('[ConnectionService] ❌ Failed to send message: $e');
      return false;
    }
  }

  /// Send a text message
  Future<bool> sendText(String text) async {
    final message = DeviceMessage(
      type: 'text',
      content: text,
      senderName: deviceName,
    );
    return await sendMessage(message);
  }

  /// Handle incoming data from socket
  void _handleIncomingData(List<int> data, int socketIndex) async {
    _perfMetrics.recordBytes(data.length);

    // Serialize processing per-socket, but allow sockets to be processed in parallel.
    final parser = _frameParsers[socketIndex];

    _incomingChains[socketIndex] = _incomingChains[socketIndex]
        .then((_) async {
          await parser.process(Uint8List.fromList(data), this);
        })
        .catchError((e) {
          debugPrint(
            '[ConnectionService] ❌ Incoming processing error on socket $socketIndex: $e',
          );
        });

    // Reset error count on successful data reception
    if (_consecutiveErrors > 0) {
      debugPrint(
        '[ConnectionService] ✅ Connection recovered, resetting error count',
      );
      _consecutiveErrors = 0;
      _errorResetTimer?.cancel();
    }

    // Note: JSON/binary payload parsing happens inside _FrameParser.
  }

  Future<void> _handleIncomingMessage(DeviceMessage message) async {
    debugPrint(
      '[ConnectionService] 📥 Received message: ${message.type} from ${message.senderName}',
    );

    if (message.type == 'reject') {
      debugPrint(
        '[ConnectionService] ❌ Connection explicitly rejected by ${message.senderName}',
      );
      if (_currentConnection != null &&
          _currentConnection!.status == ConnectionStatus.connecting) {
        _updateStatus(
          _currentConnection!.copyWith(
            status: ConnectionStatus.failed,
            error: 'Connection rejected by remote device',
          ),
        );
      }
      await disconnect();
      return;
    }

    if (message.type == 'handshake') {
      // Extract remote platform from handshake
      if (message.metadata != null &&
          message.metadata!.containsKey('platform')) {
        _remotePlatform = message.metadata!['platform'] as String?;
        debugPrint(
          '[ConnectionService] 🖥️ Remote platform detected: $_remotePlatform',
        );
      }

      // CRITICAL FIX: Only enable WiFi Direct mode if remote is Android AND we are on P2P subnet
      if (_remotePlatform == 'android' &&
          (_currentConnection?.ipAddress.startsWith('192.168.49.') ?? false)) {
        _usingWifiDirect = true;
        wifiDirectStatusNotifier.value = WifiDirectStatus.connected;
        debugPrint(
          '[ConnectionService] 📡 Confirmed WiFi Direct P2P connection with Android peer',
        );
      } else if (_remotePlatform != 'android') {
        // Explicitly disable WiFi Direct optimizations for non-Android peers
        _usingWifiDirect = false;
        debugPrint(
          '[ConnectionService] ℹ️ Peer is $_remotePlatform, disabling WiFi Direct mode',
        );
      }

      if (_currentConnection != null &&
          _currentConnection!.status == ConnectionStatus.connecting) {
        debugPrint(
          '[ConnectionService] 🤝 Handshake received from ${message.senderName}.',
        );

        // Send handshake response
        await _sendHandshake();

        // Now transition to connected state and update device name with actual remote device name
        _updateStatus(
          _currentConnection!.copyWith(
            deviceName:
                message.senderName, // Update with actual remote device name
            status: ConnectionStatus.connected,
            connectedAt: DateTime.now(),
          ),
        );
        debugPrint(
          '[ConnectionService] ✅ Handshake complete, connection established with ${message.senderName}',
        );
      } else if (isConnected) {
        debugPrint(
          '[ConnectionService] 🤝 Received handshake (already connected), ignoring',
        );
      }
      return;
    }

    if (message.type == 'parallel_request') {
      _expectedParallelStreams = int.tryParse(message.content) ?? 1;
      debugPrint(
        '[ConnectionService] 🤝 Received parallel_request for $_expectedParallelStreams streams',
      );
      await sendMessage(
        DeviceMessage(
          type: 'parallel_ack',
          senderName: deviceName,
          content: '',
        ),
      );
      return;
    }

    if (message.type == 'parallel_ack') {
      _parallelAckCompleter?.complete();
      return;
    }

    if (message.type == 'parallel_ready') {
      debugPrint('[ConnectionService] 🤝 Received parallel_ready');
      if (_sockets.length == _expectedParallelStreams) {
        if (_currentConnection!.status != ConnectionStatus.connected) {
          _updateStatus(
            _currentConnection!.copyWith(
              status: ConnectionStatus.connected,
              connectedAt: DateTime.now(),
            ),
          );
        } else {
          debugPrint(
            '[ConnectionService] 🤝 Parallel ready (already connected, skipping status update)',
          );
        }
        _startKeepAlive();
        _attemptWiFiDirectUpgrade();
        debugPrint('[ConnectionService] ✅ All parallel sockets connected');
      } else {
        debugPrint(
          '[ConnectionService] ❌ Parallel connection failed: expected $_expectedParallelStreams, got ${_sockets.length}',
        );
        disconnect();
      }
      return;
    }

    if (message.type == 'wifi_direct_offer') {
      debugPrint(
        '[ConnectionService] 📡 Received WiFi Direct offer from ${message.senderName}',
      );

      final remoteP2pId = message.metadata?['p2pId'] as String?;
      if (remoteP2pId != null) {
        _remoteWifiDirectPeerId = remoteP2pId;
      }
      final remoteP2pName = message.metadata?['p2pName'] as String?;
      if (remoteP2pName != null) {
        _remoteWifiDirectName = remoteP2pName;
      }
      final remoteTieBreaker = message.metadata?['tieBreaker'] as int? ?? 0;

      debugPrint(
        '[ConnectionService] 📡 WiFi Direct: remote p2pId=$_remoteWifiDirectPeerId, p2pName=$_remoteWifiDirectName, tieBreaker=$remoteTieBreaker',
      );

      // If both Android, negotiate roles
      if (Platform.isAndroid) {
        await _wifiDirectService.initialize();
        if (_wifiDirectService.isSupported) {
          final self = await _wifiDirectService.getThisDevice();
          _localWifiDirectPeerId = self?.id;
          _localWifiDirectName = self?.name;
        }

        // --- Role Negotiation Tie-Breaker ---
        // Determine who is the initiator (Group Owner). The initiator WAITS. The responder ACCEPTS and CONNECTS.
        // We compare strings/ints to get a deterministic winner on both sides.
        bool isInitiator = false;

        if (_localWifiDirectPeerId != null &&
            remoteP2pId != null &&
            _localWifiDirectPeerId != remoteP2pId) {
          isInitiator = _localWifiDirectPeerId!.compareTo(remoteP2pId) > 0;
          debugPrint('[ConnectionService] 📡 Negotiation by MAC: $isInitiator');
        } else if (deviceName != message.senderName) {
          isInitiator = deviceName.compareTo(message.senderName) > 0;
          debugPrint(
            '[ConnectionService] 📡 Negotiation by Device name: $isInitiator',
          );
        } else {
          isInitiator = _localWifiDirectTieBreaker > remoteTieBreaker;
          debugPrint(
            '[ConnectionService] 📡 Negotiation by TieBreaker: $isInitiator',
          );
        }

        if (isInitiator) {
          // We are the initiator. We don't send an accept. We just wait for the other side to accept.
          debugPrint(
            '[ConnectionService] 📡 Role: INITIATOR (waiting for accept)',
          );
        } else {
          // We are the responder. We send the accept and start listening.
          debugPrint('[ConnectionService] 📡 Role: RESPONDER (sending accept)');
          await sendMessage(
            DeviceMessage(
              type: 'wifi_direct_accept',
              content: 'Accepted',
              senderName: deviceName,
              metadata: {
                'platform': 'android',
                if (_localWifiDirectPeerId != null)
                  'p2pId': _localWifiDirectPeerId,
                if (_localWifiDirectName != null)
                  'p2pName': _localWifiDirectName,
              },
            ),
          );

          // Prepare responder side (register receiver + wait for group formation).
          unawaited(_prepareWiFiDirectUpgrade(initiator: false));
        }
      }
      return;
    }

    if (message.type == 'wifi_direct_accept') {
      debugPrint(
        '[ConnectionService] 📡 Received WiFi Direct acceptance from ${message.senderName}',
      );

      final remoteP2pId = message.metadata?['p2pId'] as String?;
      if (remoteP2pId != null) {
        _remoteWifiDirectPeerId = remoteP2pId;
      }
      final remoteP2pName = message.metadata?['p2pName'] as String?;
      if (remoteP2pName != null) {
        _remoteWifiDirectName = remoteP2pName;
      }

      debugPrint(
        '[ConnectionService] 📡 WiFi Direct: remote p2pId=$_remoteWifiDirectPeerId, p2pName=$_remoteWifiDirectName',
      );

      // Both devices support WiFi Direct - initiate P2P connection
      if (Platform.isAndroid) {
        unawaited(_prepareWiFiDirectUpgrade(initiator: true));
      }
      return;
    }

    if (message.type == 'wifi_direct_connected') {
      debugPrint(
        '[ConnectionService] 📡 Peer established WiFi Direct P2P connection',
      );
      final ip = message.metadata?['ip'] as String?;
      final port = message.metadata?['port'] as int?;

      if (ip != null && port != null) {
        _usingWifiDirect = true;
        debugPrint(
          '[ConnectionService] 🚀 Will use WiFi Direct for future transfers: $ip:$port',
        );

        // If we learned connection details via app protocol (e.g., future iOS support),
        // try establishing the data socket.
        unawaited(
          _ensureWifiDirectDataSocket(
            ipAddress: ip,
            port: port,
            isGroupOwner: false,
          ),
        );
      }
      return;
    }

    if (message.type == 'file_ack') {
      try {
        final ack = FileAck.fromJson(jsonDecode(message.content));
        final outgoing = _outgoingTransfers[ack.transferId];
        if (outgoing != null) {
          outgoing.initialAckReceived = true;
          final oldIndex = outgoing.lastAckIndex;
          final newIndex = ack.nextExpectedIndex - 1;

          debugPrint(
            '[ConnectionService] 📬 Sender received ACK: transferId=${ack.transferId}, oldIndex=$oldIndex, newIndex=$newIndex, sentBytes=${outgoing.sentBytes}',
          );

          for (int i = oldIndex + 1; i <= newIndex; i++) {
            final s = outgoing.chunkSizes[i] ?? 0;
            outgoing.sentBytes += s;
            outgoing.pendingBytes = (outgoing.pendingBytes - s).clamp(
              0,
              outgoing.totalSize,
            );
          }
          outgoing.lastAckIndex = newIndex;
          outgoing.resetWatchdog();

          if (outgoing.chunkPermit != null &&
              !outgoing.chunkPermit!.isCompleted) {
            outgoing.chunkPermit!.complete();
            outgoing.chunkPermit = null;
          }

          _notifyMessageListeners(
            DeviceMessage(
              type: 'file_progress',
              content: outgoing.fileName,
              senderName: deviceName,
              timestamp: DateTime.now(),
              metadata: {
                'transferId': ack.transferId,
                'bytes': outgoing.sentBytes,
                'total': outgoing.totalSize,
                'outgoing': true,
              },
            ),
          );

          if (ack.completed) {
            debugPrint(
              '[Sender-Debug] ✅ Completion COMPLETED signal (file_ack) received for ${ack.transferId}',
            );
            outgoing.watchdogTimer?.cancel();
            outgoing.completer?.complete();
            _outgoingTransfers.remove(ack.transferId);
            _notifyMessageListeners(
              DeviceMessage(
                type: 'file_complete',
                content: outgoing.fileName,
                senderName: deviceName,
                timestamp: DateTime.now(),
                metadata: {
                  'transferId': ack.transferId,
                  'outgoing': true,
                  'size': outgoing.totalSize,
                  if (outgoing.mime != null) 'mime': outgoing.mime,
                  if (outgoing.path != null) 'path': outgoing.path,
                },
              ),
            );

            NotificationService().showNotification(
              type: NotificationType.fileTransferCompleted,
              title: 'File Sent',
              body: 'Successfully sent ${outgoing.fileName}',
            );
          } else {
            outgoing.chunkPermit?.complete();
          }
        }
      } catch (e) {
        debugPrint('[ConnectionService] ⚠️ Failed to parse file_ack: $e');
      }
      return;
    }

    if (message.type == 'file_offer') {
      try {
        // On desktop, check if download location is set before accepting file
        if (!Platform.isAndroid && !Platform.isIOS) {
          final prefs = await SharedPreferences.getInstance();
          final savedPath = prefs.getString('download_save_path');

          if (savedPath == null || savedPath.isEmpty) {
            // No download location set, prompt user
            debugPrint(
              '[ConnectionService] No download location, prompting user...',
            );

            final selectedDirectory = await FilePicker.platform
                .getDirectoryPath(dialogTitle: 'Choose Download Location');

            if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
              // Save the chosen location
              await prefs.setString('download_save_path', selectedDirectory);
              debugPrint(
                '[ConnectionService] Download location saved: $selectedDirectory',
              );

              // Initialize DPFTP receiver with the chosen location
              await DpftpService().startReceiver(
                saveDirectory: selectedDirectory,
              );
              // Progress listener already set up in constructor
            } else {
              // User cancelled, reject the file
              debugPrint(
                '[ConnectionService] User cancelled download location selection, rejecting file',
              );
              return; // Don't process the file_offer
            }
          }
        }

        final offer = FileOffer.fromJson(
          (message.metadata?['payload'] as Map?)?.cast<String, dynamic>() ?? {},
        );
        _pendingOffers[offer.transferId] = offer;

        NotificationService().showFileTransferNotification(
          senderDisplayName: deviceName,
          fileName: offer.fileName,
          fileSize: offer.fileSize,
          transferId: offer.transferId,
          deviceName: deviceName,
        );

        _notifyMessageListeners(
          DeviceMessage(
            type: 'file_offer',
            content: offer.fileName,
            senderName: message.senderName,
            timestamp: DateTime.now(),
            metadata: {
              'transferId': offer.transferId,
              'size': offer.fileSize,
              'mime': offer.mimeType,
            },
          ),
        );
      } catch (e) {
        debugPrint('[ConnectionService] ⚠️ Failed to parse file_offer: $e');
      }
      return;
    }

    if (message.type == 'file_resume_request') {
      try {
        final transferId = message.content;
        final inc = _incomingFiles[transferId];
        if (inc != null) {
          final ack = FileAck(
            transferId: transferId,
            nextExpectedIndex: inc.nextIndex,
            completed: false,
          );
          await sendMessage(
            DeviceMessage(
              type: 'file_ack',
              content: jsonEncode(ack.toJson()),
              senderName: deviceName,
            ),
          );
          debugPrint(
            '[ConnectionService] 🔁 Resume-request: resent ACK for $transferId at ${inc.nextIndex}',
          );
        } else {
          debugPrint(
            '[ConnectionService] ⚠️ Resume-request: no incoming state for $transferId',
          );
        }
      } catch (e) {
        debugPrint(
          '[ConnectionService] ⚠️ Failed to handle resume request: $e',
        );
      }
      return;
    }

    if (message.type == 'file_offer_request') {
      try {
        final reqTransferId = message.content;
        final ot = _outgoingTransfers[reqTransferId];
        if (ot != null) {
          final offer = FileOffer(
            transferId: reqTransferId,
            fileName: ot.fileName,
            fileSize: ot.totalSize,
            mimeType: ot.mime ?? 'application/octet-stream',
            sha256: null,
          );
          await sendMessage(
            DeviceMessage(
              type: 'file_offer',
              content: ot.fileName,
              senderName: deviceName,
              metadata: {'payload': offer.toJson(), 'name': ot.fileName},
            ),
          );
          debugPrint(
            '[ConnectionService] 🔄 Resent file_offer for $reqTransferId',
          );
        } else {
          debugPrint(
            '[ConnectionService] ⚠️ Offer request: no outgoing state for $reqTransferId',
          );
        }
      } catch (e) {
        debugPrint(
          '[ConnectionService] ⚠️ Failed to handle file_offer_request: $e',
        );
      }
      return;
    }

    if (message.type == 'request_ack') {
      try {
        final reqTransferId = message.content;
        final inc = _incomingFiles[reqTransferId];
        if (inc != null) {
          final ack = FileAck(
            transferId: reqTransferId,
            nextExpectedIndex: inc.nextIndex,
            completed: false,
          );
          await sendMessage(
            DeviceMessage(
              type: 'file_ack',
              content: jsonEncode(ack.toJson()),
              senderName: deviceName,
            ),
          );
          debugPrint(
            '[ConnectionService] 🔄 Resent ACK for $reqTransferId at index ${inc.nextIndex}',
          );
        }
      } catch (e) {
        debugPrint('[ConnectionService] ⚠️ Failed to resend ACK: $e');
      }
      return;
    }

    if (message.type == 'file_cancel') {
      try {
        final cancel = FileCancel.fromJson(jsonDecode(message.content));
        final inc = _incomingFiles.remove(cancel.transferId);
        if (inc != null) {
          await inc.sink?.close();
        }
        _pendingOffers.remove(cancel.transferId);
        _outgoingTransfers.remove(cancel.transferId);
        _notifyMessageListeners(
          DeviceMessage(
            type: 'text',
            content: 'Transfer cancelled: ${cancel.reason}',
            senderName: message.senderName,
            timestamp: DateTime.now(),
          ),
        );
      } catch (e) {
        debugPrint('[ConnectionService] ⚠️ Failed to parse file_cancel: $e');
      }
      return;
    }

    if (message.type == 'ping') {
      debugPrint('[ConnectionService] 🏓 Received ping, sending pong');
      final pong = DeviceMessage(
        type: 'pong',
        content: 'keep-alive',
        senderName: deviceName,
      );
      sendMessage(pong);
      return;
    }

    if (message.type == 'dpftp_start') {
      try {
        final transferId = message.content;
        final ot = _outgoingTransfers[transferId];
        if (ot != null) {
          // Use WiFi Direct IP if available/active, otherwise fallback to connection IP
          final ip = (_usingWifiDirect && _wifiDirectIpAddress != null)
              ? _wifiDirectIpAddress
              : _currentConnection?.ipAddress;

          if (ip != null && ot.path != null) {
            debugPrint(
              '[ConnectionService] 🚀 Starting DPFTP Transfer for $transferId to $ip (WiFi Direct: $_usingWifiDirect)',
            );

            // Cancel legacy watchdog to prevent "Initial ACK not received"
            ot.watchdogTimer?.cancel();
            ot.initialAckReceived = true;
            if (ot.chunkPermit != null && !ot.chunkPermit!.isCompleted) {
              ot.chunkPermit!.complete();
            }

            // Optimize DPFTP parameters based on remote platform
            final bool isRemoteWindows = _remotePlatform == 'windows';
            final bool isRemoteLinux = _remotePlatform == 'linux';
            final bool isRemoteAndroid = _remotePlatform == 'android';
            final bool isRemoteMacOS = _remotePlatform == 'macos';
            final bool isRemoteIOS = _remotePlatform == 'ios';

            // Moderate connection count for router compatibility
            final int parallelConns = Platform.isIOS
                ? 2 // iOS: Strict limit of 2 parallel connections
                : (isRemoteWindows
                      ? 10 // Windows: 10 connections
                      : (isRemoteLinux
                            ? 3 // Linux: 2 connections (reduced for stability)
                            : (isRemoteMacOS
                                  ? 6 // macOS: 6 connections
                                  : (isRemoteAndroid
                                        ? 4 // Android: 4 connections
                                        : (isRemoteIOS
                                              ? 1
                                              : 2))))); // iOS: 1 connection, Others: 2

            // FIXED: Use 2MB chunks for Windows to reduce CPU/Header overhead
            // 4MB for optimal throughput on other platforms
            final int chunkSizeMB = (isRemoteWindows || isRemoteLinux)
                ? 2 * 1024 * 1024
                : (isRemoteAndroid ? 1024 * 1024 : 4 * 1024 * 1024);

            // Windows-specific: Tighter window to consume data faster and reduce RTT
            // 32MB is enough for 30+ MB/s even with high RTT.
            // 512MB caused massive bufferbloat (RTT > 5s).
            // Windows-specific: Aggressive Window for 10 connections
            // 128MB allows 12.8MB per connection.
            final int windowMB = isRemoteWindows
                ? (128 * 1024 * 1024) // 128MB for Windows
                : (isRemoteMacOS
                      ? (256 *
                            1024 *
                            1024) // 256MB for macOS (good default buffers)
                      : (isRemoteLinux
                            ? (256 * 1024 * 1024) // 256MB for Linux
                            : (isRemoteAndroid
                                  ? (64 *
                                        1024 *
                                        1024) // 64MB for Android (prevent bufferbloat on Redmi etc)
                                  : (128 * 1024 * 1024)))); // 128MB for others

            debugPrint(
              'dpftp-new-file: Config → ${isRemoteWindows
                  ? "Windows"
                  : isRemoteAndroid
                  ? "Android"
                  : isRemoteLinux
                  ? "Linux"
                  : isRemoteMacOS
                  ? "macOS"
                  : "Standard"} | Connections: $parallelConns | Chunk: ${chunkSizeMB ~/ (1024 * 1024)}MB | Window: ${windowMB ~/ (1024 * 1024)}MB)',
            );

            debugPrint(
              'dpftp-new-file: 🔍 Platform detection: _remotePlatform="$_remotePlatform", isWindows=$isRemoteWindows, isAndroid=$isRemoteAndroid, isLinux=$isRemoteLinux, isMacOS=$isRemoteMacOS',
            );

            // Start DPFTP transfer
            unawaited(
              DpftpService().sendFile(
                ip: ip,
                file: File(ot.path!),
                transferId: transferId,
                parallelConnections: parallelConns,
                chunkSize: chunkSizeMB,
                maxInFlightBytes: windowMB,
              ),
            );
          } else {
            debugPrint(
              '[ConnectionService] ❌ DPFTP Start Failed: IP($ip) or Path(${ot.path}) null',
            );
          }
        }
      } catch (e) {
        debugPrint('[ConnectionService] ❌ DPFTP Start Error: $e');
      }
      return;
    }

    if (message.type == 'pong') {
      debugPrint('[ConnectionService] 🏓 Received pong (connection alive)');
      return;
    }

    _notifyMessageListeners(message);
    if (message.type == 'text') {
      NotificationService().showNotification(
        type: NotificationType.messageReceived,
        title: 'New Message',
        body: '${message.senderName}: ${message.content}',
      );
    }
  }

  /// Public API: Pick and send a file (basic MVP)
  /// Public API: Send a list of files (called after picking)
  Future<void> sendFiles(List<PlatformFile> files) async {
    if (!isConnected || _primarySocket == null) {
      debugPrint('[ConnectionService] ⚠️ Not connected; cannot send files');
      return;
    }

    for (final file in files) {
      final name = file.name;
      final size = file.size;
      final mime = file.extension != null
          ? 'application/${file.extension}'
          : 'application/octet-stream';
      final transferId = generateTransferId();

      // Optional: compute sha256 in isolate for integrity
      String? sha;
      try {
        if (file.bytes != null) {
          sha = sha256.convert(file.bytes!).toString();
        }
      } catch (_) {}

      final offer = FileOffer(
        transferId: transferId,
        fileName: name,
        fileSize: size,
        mimeType: mime,
        sha256: sha,
      );

      await sendMessage(
        DeviceMessage(
          type: 'file_offer',
          content: name, // provide filename directly for dialog display
          senderName: deviceName,
          metadata: {'payload': offer.toJson(), 'name': name},
        ),
      );

      // Stream chunk size
      // 🚀 PERF: Use 32MB for iOS/Desktop to maximize throughput on high-bandwidth links.
      // Android uses 16MB to balance memory usage on diverse hardware.
      final int chunkSize = (Platform.isAndroid)
          ? 16 *
                1024 *
                1024 // 16MB Android
          : 32 * 1024 * 1024; // 32MB iOS/Desktop
      int index = 0;

      // Register outgoing transfer BEFORE waiting for ACK/streaming
      _outgoingTransfers[transferId] = _OutgoingTransfer(
        fileName: name,
        lastAckIndex: -1,
        totalSize: size,
        mime: mime,
        path: file.path,
      );

      // Emit initial progress event to render UI tile
      _notifyMessageListeners(
        DeviceMessage(
          type: 'file_progress',
          content: name,
          senderName: deviceName,
          timestamp: DateTime.now(),
          metadata: {
            'transferId': transferId,
            'bytes': 0,
            'total': size,
            'mime': mime,
            'outgoing': true,
          },
        ),
      );

      // Wait for initial ACK (nextExpectedIndex = 0) which is sent after receiver accepts
      final starter = _outgoingTransfers[transferId];
      if (starter != null) {
        const maxInitialAckWait = Duration(minutes: 2);
        const stepTimeout = Duration(seconds: 10);
        final startedAt = DateTime.now();
        int attempts = 0;

        debugPrint(
          '[ConnectionService] ⏳ Waiting for initial ACK for transfer $transferId',
        );

        try {
          while (true) {
            final current = _outgoingTransfers[transferId];
            if (current == null) {
              throw StateError('Transfer cancelled');
            }
            if (current.initialAckReceived) break;

            final elapsed = DateTime.now().difference(startedAt);
            if (elapsed >= maxInitialAckWait) {
              throw TimeoutException('No initial ACK received');
            }
            final remaining = maxInitialAckWait - elapsed;
            final waitFor = remaining < stepTimeout ? remaining : stepTimeout;

            final permit = current.chunkPermit ??= Completer<void>();
            try {
              await permit.future.timeout(waitFor);
            } on TimeoutException {
              attempts++;
              debugPrint(
                '[ConnectionService] ⚠️ Initial ACK still not received for $transferId (attempt $attempts), requesting ACK resend',
              );
              // Ask receiver to resend its current ACK if it already accepted.
              try {
                await sendMessage(
                  DeviceMessage(
                    type: 'file_resume_request',
                    content: transferId,
                    senderName: deviceName,
                  ),
                );
              } catch (_) {}

              // If the offer was lost, periodically resend it to re-trigger UI.
              if (attempts % 3 == 0) {
                try {
                  await sendMessage(
                    DeviceMessage(
                      type: 'file_offer',
                      content: name,
                      senderName: deviceName,
                      metadata: {'payload': offer.toJson(), 'name': name},
                    ),
                  );
                  debugPrint(
                    '[ConnectionService] 🔄 Resent file_offer for $transferId (no initial ACK yet)',
                  );
                } catch (_) {}
              }
            }
          }

          // 🚀 ALWAYS Use DPFTP (parallel sockets) if enabled, even for WiFi Direct
          // This bypasses the slower single-socket legacy WiFi Direct path
          if (useDpftp) {
            debugPrint(
              '[ConnectionService] 🚀 DPFTP took over. Legacy sender logic stopping.',
            );
            continue; // Skip to next file (or finish if last)
          }

          if (_usingWifiDirect && _wifiDirectDataSocket != null) {
            debugPrint(
              '[ConnectionService] 🚀 WiFi Direct active - using direct socket transfer (bypassing DPFTP)',
            );
          }

          debugPrint(
            '[ConnectionService] ✅ Initial ACK received, starting chunk stream for $transferId',
          );
          // Start watchdog for sender side
          _startOutgoingWatchdog(transferId);
        } catch (e) {
          debugPrint('[ConnectionService] ❌ Initial ACK error: $e');
          _outgoingTransfers.remove(transferId);
          // Continue to next file if this one fails
          continue;
        }
      }

      // Stream chunks AFTER initial ACK
      if (file.path != null) {
        // 🚀 WiFi Direct: When P2P is established, transfers automatically use the direct connection
        // This provides faster speeds without router bottleneck
        if (_usingWifiDirect) {
          debugPrint(
            '[ConnectionService] 🚀 Using WiFi Direct P2P for file transfer',
          );
        }

        final f = File(file.path!);
        final raf = await f.open(mode: FileMode.read);
        try {
          // 🚀 PERF: Preallocate read buffer to avoid per-chunk allocations
          final readBuffer = Uint8List(chunkSize);
          int flowControlWaits = 0;
          int totalChunks = 0;
          final sendStartTime = DateTime.now();

          while (true) {
            // Read into preallocated buffer
            final bytesRead = await raf.readInto(readBuffer);
            if (bytesRead == 0) break;

            final ot = _outgoingTransfers[transferId];
            if (ot == null) break;
            // Flow-control based on in-flight bytes (pendingBytes)
            if (ot.pendingBytes >= ConnectionService._maxPendingBytes) {
              flowControlWaits++;
              ot.chunkPermit = Completer<void>();
              debugPrint(
                '[ConnectionService] ⏳ Flow control: waiting at chunk $index (pendingBytes=${ot.pendingBytes}, lastAck=${ot.lastAckIndex}, waits=$flowControlWaits)',
              );
              await ot.chunkPermit!.future;
              debugPrint(
                '[ConnectionService] ✅ Flow control released at chunk $index',
              );
            }

            // Create view into buffer (avoids copy if bytesRead == chunkSize)
            final chunkData = bytesRead == chunkSize
                ? readBuffer
                : Uint8List.sublistView(readBuffer, 0, bytesRead);

            ot.chunkSizes[index] = bytesRead;

            // Record size & send
            ot.chunkSizes[index] = bytesRead;
            // 🚀 PERF: Send all chunks, only await flush every 8 chunks to maximize throughput (64MB buffer for 8MB chunks)
            final shouldAwaitFlush = (index % 8 == 0);
            await _sendBinaryChunk(
              transferId: transferId,
              index: index++,
              isLast: false,
              bytes: chunkData,
              flush: shouldAwaitFlush,
            );
            // Track in-flight bytes
            ot.pendingBytes += bytesRead;
            totalChunks++;
            ot.resetWatchdog();
            if (index % 128 == 0) {
              final elapsed = DateTime.now()
                  .difference(sendStartTime)
                  .inSeconds;
              final mbps =
                  (totalChunks *
                      chunkSize *
                      8.0 /
                      (elapsed > 0 ? elapsed : 1)) /
                  1000000;
              debugPrint(
                '[SENDER-PERF] Chunk $index: ${mbps.toStringAsFixed(1)} Mbps, flowControlWaits=$flowControlWaits',
              );
              await Future.microtask(() {});
            }
          }
        } finally {
          await raf.close();
        }
      } else {
        final stream = file.readStream;
        if (stream != null) {
          await for (final data in stream) {
            int offset = 0;
            while (offset < data.length) {
              final end = (offset + chunkSize).clamp(0, data.length).toInt();
              final slice = data.sublist(offset, end);
              final ot = _outgoingTransfers[transferId];
              if (ot == null) break; // Cancelled

              // Flow-control based on pending bytes
              if (ot.pendingBytes >= ConnectionService._maxPendingBytes) {
                ot.chunkPermit = Completer<void>();
                debugPrint(
                  '[ConnectionService] ⏳ Flow control: waiting at chunk $index (pendingBytes=${ot.pendingBytes}, lastAck=${ot.lastAckIndex})',
                );
                await ot.chunkPermit!.future;
                debugPrint(
                  '[ConnectionService] ✅ Flow control released at chunk $index',
                );
              }

              ot.chunkSizes[index] = slice.length;

              await _sendBinaryChunk(
                transferId: transferId,
                index: index++,
                isLast: false,
                bytes: Uint8List.fromList(slice),
                flush: (index % 8 == 0),
              );
              // Track in-flight bytes
              ot.pendingBytes += slice.length;
              ot.resetWatchdog();

              if (index % 128 == 0) {
                await Future.microtask(() {});
              }

              offset = end;
            }
          }
        }
      }
      // Final marker
      final otFinal = _outgoingTransfers[transferId];
      if (otFinal != null) {
        if (otFinal.pendingBytes >= ConnectionService._maxPendingBytes) {
          otFinal.chunkPermit = Completer<void>();
          debugPrint(
            '[ConnectionService] ⏳ Final: waiting for flow control (pendingBytes=${otFinal.pendingBytes})',
          );
          await otFinal.chunkPermit!.future;
        }

        // Send final marker as binary chunk
        otFinal.completer = Completer<void>();
        debugPrint(
          '[Sender-Debug] 📤 Sending final marker for $transferId at index $index',
        );
        await _sendBinaryChunk(
          transferId: transferId,
          index: index,
          isLast: true,
          bytes: Uint8List(0),
          flush: true,
        );
        debugPrint(
          '[Sender-Debug] ⏳ Sent final marker, waiting for Final ACK...',
        );
        await otFinal.completer!.future; // Wait for final ack
        debugPrint('[Sender-Debug] ✅ Final ACK received for $transferId');
      }
    }
  }

  /// Public API: Pick and send a file (basic MVP)
  Future<void> pickAndSendFile() async {
    if (!isConnected || _primarySocket == null) {
      debugPrint('[ConnectionService] ⚠️ Not connected; cannot send file');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      withReadStream: true,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    // Use the new sendFiles method
    await sendFiles(result.files);
  }

  /// Send shared files from share intent
  Future<void> sendSharedFiles(List<SharedMediaFile> sharedFiles) async {
    debugPrint(
      '[ConnectionService] 📤 sendSharedFiles called with ${sharedFiles.length} files',
    );
    if (!isConnected || _primarySocket == null) {
      debugPrint(
        '[ConnectionService] ⚠️ Not connected; cannot send shared files',
      );
      return;
    }

    // Work with a copy to avoid concurrent modification issues
    final filesToSend = List<SharedMediaFile>.from(sharedFiles);

    for (final sharedFile in filesToSend) {
      debugPrint(
        '[ConnectionService] 📄 Processing shared file: ${sharedFile.path}',
      );
      final filePath = sharedFile.path;
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint(
          '[ConnectionService] ⚠️ Shared file does not exist: $filePath',
        );
        continue;
      }

      debugPrint(
        '[ConnectionService] ✅ File exists, size: ${await file.length()} bytes',
      );
      final name = sharedFile.path.split('/').last;
      final size = await file.length();
      final mime = sharedFile.mimeType ?? 'application/octet-stream';
      final transferId = generateTransferId();

      // Optional: compute sha256 in isolate for integrity
      String? sha;
      try {
        final bytes = await file.readAsBytes();
        sha = sha256.convert(bytes).toString();
      } catch (_) {}

      final offer = FileOffer(
        transferId: transferId,
        fileName: name,
        fileSize: size,
        mimeType: mime,
        sha256: sha,
      );

      await sendMessage(
        DeviceMessage(
          type: 'file_offer',
          content: name,
          senderName: deviceName,
          metadata: {'payload': offer.toJson(), 'name': name},
        ),
      );

      // Stream chunks
      // 🚀 PERF: Use 32MB for iOS/Desktop to maximize throughput on high-bandwidth links.
      // Android uses 16MB to balance memory usage on diverse hardware.
      final int chunkSize = (Platform.isAndroid)
          ? 16 *
                1024 *
                1024 // 16MB Android
          : 32 * 1024 * 1024; // 32MB iOS/Desktop
      int index = 0;
      // Stream the file with controlled chunk size using RandomAccessFile to avoid tiny default chunks
      final raf = await file.open(mode: FileMode.read);

      // Register outgoing transfer
      _outgoingTransfers[transferId] = _OutgoingTransfer(
        fileName: name,
        lastAckIndex: -1,
        totalSize: size,
        mime: mime,
        path: filePath,
      );

      // Emit initial progress event
      _notifyMessageListeners(
        DeviceMessage(
          type: 'file_progress',
          content: name,
          senderName: deviceName,
          timestamp: DateTime.now(),
          metadata: {
            'transferId': transferId,
            'bytes': 0,
            'total': size,
            'mime': mime,
            'outgoing': true,
          },
        ),
      );

      // Wait for initial ACK
      final starter = _outgoingTransfers[transferId];
      if (starter != null) {
        const maxInitialAckWait = Duration(minutes: 2);
        const stepTimeout = Duration(seconds: 10);
        final startedAt = DateTime.now();
        int attempts = 0;

        debugPrint(
          '[ConnectionService] ⏳ Waiting for initial ACK for shared transfer $transferId',
        );

        try {
          while (true) {
            final current = _outgoingTransfers[transferId];
            if (current == null) {
              throw StateError('Transfer cancelled');
            }
            if (current.initialAckReceived) break;

            final elapsed = DateTime.now().difference(startedAt);
            if (elapsed >= maxInitialAckWait) {
              throw TimeoutException('No initial ACK received');
            }
            final remaining = maxInitialAckWait - elapsed;
            final waitFor = remaining < stepTimeout ? remaining : stepTimeout;

            final permit = current.chunkPermit ??= Completer<void>();
            try {
              await permit.future.timeout(waitFor);
            } on TimeoutException {
              attempts++;
              debugPrint(
                '[ConnectionService] ⚠️ Initial ACK still not received for shared $transferId (attempt $attempts), requesting ACK resend',
              );
              try {
                await sendMessage(
                  DeviceMessage(
                    type: 'file_resume_request',
                    content: transferId,
                    senderName: deviceName,
                  ),
                );
              } catch (_) {}

              if (attempts % 3 == 0) {
                try {
                  await sendMessage(
                    DeviceMessage(
                      type: 'file_offer',
                      content: name,
                      senderName: deviceName,
                      metadata: {'payload': offer.toJson(), 'name': name},
                    ),
                  );
                  debugPrint(
                    '[ConnectionService] 🔄 Resent file_offer for shared $transferId (no initial ACK yet)',
                  );
                } catch (_) {}
              }
            }
          }

          debugPrint(
            '[ConnectionService] ✅ Initial ACK received, starting chunk stream for shared $transferId',
          );
          _startOutgoingWatchdog(transferId);
        } catch (e) {
          debugPrint('[ConnectionService] ❌ Initial ACK error: $e');
          _outgoingTransfers.remove(transferId);
          continue;
        }
      }

      try {
        while (true) {
          final chunk = await raf.read(chunkSize);
          if (chunk.isEmpty) break;

          final ot = _outgoingTransfers[transferId];
          if (ot == null) break;

          if (ot.pendingBytes >= ConnectionService._maxPendingBytes) {
            ot.chunkPermit = Completer<void>();
            debugPrint(
              '[ConnectionService] ⏳ Flow control: waiting at chunk $index (pendingBytes=${ot.pendingBytes})',
            );
            await ot.chunkPermit!.future;
          }

          ot.chunkSizes[index] = chunk.length;

          await _sendBinaryChunk(
            transferId: transferId,
            index: index++,
            isLast: false,
            bytes: Uint8List.fromList(chunk),
            flush: (index % 8 == 0),
          );
          // Track in-flight bytes
          ot.pendingBytes += chunk.length;

          ot.resetWatchdog();

          if (index % 128 == 0) {
            await Future.microtask(() {});
          }
        }
      } finally {
        await raf.close();
      }

      // Final marker
      final otFinal = _outgoingTransfers[transferId];
      if (otFinal != null) {
        if (otFinal.pendingBytes >= ConnectionService._maxPendingBytes) {
          otFinal.chunkPermit = Completer<void>();
          debugPrint(
            '[ConnectionService] ⏳ Final: waiting for ACK (pendingBytes=${otFinal.pendingBytes})',
          );
          await otFinal.chunkPermit!.future;
        }

        // Send final marker as binary chunk
        otFinal.completer = Completer<void>();
        await _sendBinaryChunk(
          transferId: transferId,
          index: index,
          isLast: true,
          bytes: Uint8List(0),
          flush: true,
        );
        await otFinal.completer!.future;
      }
    }
  }

  /// Accept a pending incoming file offer, prepares file path/sink and signals sender to start
  Future<void> acceptFileOffer(String transferId, {String? saveDir}) async {
    final offer = _pendingOffers.remove(transferId);
    if (offer == null) {
      debugPrint('[ConnectionService] No pending offer for $transferId');
      return;
    }

    // 🚀 ALWAYS Use DPFTP (parallel sockets) if enabled, even for WiFi Direct
    // This bypasses the slower single-socket legacy WiFi Direct path
    if (useDpftp) {
      debugPrint('[ConnectionService] 🚀 Accepting with DPFTP for $transferId');
      await sendMessage(
        DeviceMessage(
          type: 'dpftp_start',
          content: transferId,
          senderName: deviceName,
        ),
      );
      return;
    }

    if (_usingWifiDirect && _wifiDirectDataSocket != null) {
      debugPrint(
        '[ConnectionService] 🚀 WiFi Direct active - using direct socket receive (bypassing DPFTP)',
      );
    }

    // Choose directory: Downloads on desktop, Documents on mobile
    Directory dir;
    if (saveDir != null && saveDir.isNotEmpty) {
      dir = Directory(saveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final downloads = await getDownloadsDirectory();
      dir = downloads ?? await getApplicationDocumentsDirectory();
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    final safeName = offer.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    String path = '${dir.path}/$safeName';
    // Collision handling
    int dup = 1;
    while (await File(path).exists()) {
      final extIndex = safeName.lastIndexOf('.');
      if (extIndex > 0) {
        final base = safeName.substring(0, extIndex);
        final ext = safeName.substring(extIndex);
        path = '${dir.path}/$base($dup)$ext';
      } else {
        path = '${dir.path}/$safeName($dup)';
      }
      dup++;
    }

    RandomAccessFile? raf;
    if (Platform.isAndroid && useNativeReceiver) {
      // Native receiver writes the file on Android; just ensure the file exists.
      await File(path).create(recursive: true);
    } else {
      raf = await File(path).open(mode: FileMode.write);
    }

    _incomingFiles[offer.transferId] = _IncomingFile(
      offer: offer,
      path: path,
      sink: raf,
      receivedBytes: 0,
      nextIndex: 0,
    );
    // Inform UI about chosen path
    _notifyMessageListeners(
      DeviceMessage(
        type: 'file_progress',
        content: offer.fileName,
        senderName: deviceName,
        timestamp: DateTime.now(),
        metadata: {
          'transferId': offer.transferId,
          'bytes': 0,
          'total': offer.fileSize,
          'outgoing': false,
          'path': path,
        },
      ),
    );
    // On Android, start the native receiver and register the file BEFORE sending initial ACK.
    if (Platform.isAndroid && useNativeReceiver) {
      try {
        const nativeReceiverChannel = MethodChannel(
          'com.omnity.fylooo/native_receiver_method',
        );
        await nativeReceiverChannel.invokeMethod('startReceiver');
        await nativeReceiverChannel.invokeMethod('registerIncoming', {
          'transferId': offer.transferId,
          'path': path,
        });
        debugPrint(
          '[ConnectionService] 📱 Android native receiver started and registered for $transferId',
        );
      } catch (e) {
        debugPrint(
          '[ConnectionService] ❌ Failed to start/register native receiver: $e',
        );
      }
    }

    // Send initial ack to let sender start
    final ack = FileAck(
      transferId: offer.transferId,
      nextExpectedIndex: 0,
      completed: false,
    );
    await sendMessage(
      DeviceMessage(
        type: 'file_ack',
        content: jsonEncode(ack.toJson()),
        senderName: deviceName,
      ),
    );
    debugPrint(
      '[ConnectionService] 📤 Initial ACK sent for transfer ${offer.transferId}',
    );

    // Flush any buffered binary chunks that arrived early
    final pending = _pendingBinary.remove(offer.transferId);
    if (pending != null && pending.isNotEmpty) {
      debugPrint(
        '[ConnectionService] 📦 Flushing ${pending.length} buffered chunks for ${offer.transferId}',
      );
      for (final p in pending) {
        await _handleBinaryChunk(
          transferId: offer.transferId,
          index: p.index,
          isLast: p.isLast,
          bytes: p.data,
        );
      }

      // CRITICAL: ensure sender is unblocked after flushing early chunks.
      final inc = _incomingFiles[offer.transferId];
      if (inc != null) {
        await _sendAck(offer.transferId, inc.nextIndex);
      }
    }

    // Start watchdog for receiver side
    _startIncomingWatchdog(offer.transferId);
  }

  /// Decline a pending incoming file offer
  Future<void> declineFileOffer(
    String transferId, {
    String reason = 'Declined by receiver',
  }) async {
    final offer = _pendingOffers.remove(transferId);
    if (offer == null) return;
    final cancel = FileCancel(transferId: transferId, reason: reason);
    await sendMessage(
      DeviceMessage(
        type: 'file_cancel',
        content: jsonEncode(cancel.toJson()),
        senderName: deviceName,
      ),
    );
  }

  Future<void> cancelTransfer(
    String transferId, {
    String reason = 'Cancelled by user',
  }) async {
    // Notify remote
    final cancel = FileCancel(transferId: transferId, reason: reason);
    await sendMessage(
      DeviceMessage(
        type: 'file_cancel',
        content: jsonEncode(cancel.toJson()),
        senderName: deviceName,
      ),
    );
    // Clean local state
    final inc = _incomingFiles.remove(transferId);
    if (inc != null) {
      inc.watchdogTimer?.cancel(); // Stop watchdog
      try {
        await inc.sink?.close();
      } catch (_) {}
    }
    final out = _outgoingTransfers.remove(transferId);
    if (out != null) {
      out.watchdogTimer?.cancel(); // Stop watchdog
    }
    _pendingOffers.remove(transferId);

    // Clean up native receiver socket for this transfer
    try {
      _nativeReceiverSockets[transferId]?.close();
    } catch (_) {}
    _nativeReceiverSockets.remove(transferId);
    _nativeReceiverLastFlush.remove(transferId);
  }

  /// Ask the peer (receiver) to resend its last ACK for a stuck outgoing transfer
  Future<void> requestResume(String transferId) async {
    try {
      final msg = DeviceMessage(
        type: 'file_resume_request',
        content: transferId,
        senderName: deviceName,
      );
      await sendMessage(msg);
      debugPrint('[ConnectionService] ▶️ Sent resume request for $transferId');
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️ Failed to send resume request: $e');
    }
  }

  /// For an incoming transfer, resend the last ACK to nudge the sender
  Future<void> resumeIncoming(String transferId) async {
    try {
      final inc = _incomingFiles[transferId];
      if (inc == null) {
        debugPrint(
          '[ConnectionService] No incoming state to resume for $transferId',
        );
        return;
      }
      final ack = FileAck(
        transferId: transferId,
        nextExpectedIndex: inc.nextIndex,
        completed: false,
      );
      await sendMessage(
        DeviceMessage(
          type: 'file_ack',
          content: jsonEncode(ack.toJson()),
          senderName: deviceName,
        ),
      );
      debugPrint(
        '[ConnectionService] 🔁 Resent ACK for $transferId at index ${inc.nextIndex}',
      );
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️ Failed to resume incoming: $e');
    }
  }

  /// Handle connection error
  void _handleConnectionError(String error) {
    _consecutiveErrors++;
    debugPrint(
      '[ConnectionService] ⚠️ Socket error #$_consecutiveErrors: $error',
    );

    // Reset error count after 10 seconds of no errors
    _errorResetTimer?.cancel();
    _errorResetTimer = Timer(const Duration(seconds: 10), () {
      if (_consecutiveErrors > 0) {
        debugPrint(
          '[ConnectionService] 🔄 Resetting error count after timeout',
        );
        _consecutiveErrors = 0;
      }
    });

    // Only mark as disconnected after multiple consecutive errors (not failed)
    // This prevents removal from activeConnections, allowing UI to show disconnected state
    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      debugPrint(
        '[ConnectionService] ❌ Too many consecutive errors, marking connection as disconnected (not failed)',
      );
      if (_currentConnection != null) {
        _updateStatus(
          _currentConnection!.copyWith(
            status: ConnectionStatus.disconnected,
            error: 'Connection lost: $error',
          ),
        );
      }
      _consecutiveErrors = 0; // Reset for potential reconnection
    }
  }

  /// Update connection status
  void _updateStatus(ConnectionInfo info) {
    // 🛡️ Guard: If we are on WiFi Direct P2P, do NOT overwrite the P2P IP with a LAN IP (e.g. from mDNS)
    // This prevents falling back to slow WiFi when both devices are also on office/home WiFi.
    if (_usingWifiDirect &&
        _currentConnection != null &&
        _currentConnection!.ipAddress.startsWith('192.168.49.') &&
        !info.ipAddress.startsWith('192.168.49.') &&
        info.status == ConnectionStatus.connected) {
      debugPrint(
        '[ConnectionService] 🛡️ Preserving P2P IP ${_currentConnection!.ipAddress} against update to ${info.ipAddress}',
      );
      // Keep the new status/device name but force the P2P IP
      info = info.copyWith(ipAddress: _currentConnection!.ipAddress);
    }

    // Check for connection transition to load history
    final wasConnected =
        _currentConnection?.status == ConnectionStatus.connected;
    final isConnected = info.status == ConnectionStatus.connected;

    _currentConnection = info;

    if (!wasConnected && isConnected) {
      _loadHistory(info.deviceName);
    }

    for (final listener in List.of(_statusListeners)) {
      listener(info);
    }
  }

  Future<void> _loadHistory(String deviceName) async {
    try {
      final history = await DatabaseService().getMessagesForDevice(deviceName);
      _messageHistory.clear();
      _messageHistory.addAll(history);
      debugPrint(
        '[ConnectionService] 📜 Loaded ${history.length} messages from history for $deviceName',
      );

      // Notify listeners to reload history in UI
      _notifyMessageListeners(
        DeviceMessage(
          type: 'history_reload',
          senderName: 'system',
          timestamp: DateTime.now(),
          content: 'reload',
        ),
      );
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️ Failed to load history: $e');
    }
  }

  /// Notify message listeners
  void _notifyMessageListeners(DeviceMessage message) {
    const historyTypes = {'text', 'file_complete', 'goodbye'};
    if (historyTypes.contains(message.type)) {
      if (message.type == 'file_complete' && _messageHistory.isNotEmpty) {
        final last = _messageHistory.last;
        if (last.type == 'file_complete' && last.content == message.content) {
          // Skip storing duplicate completion event
        } else {
          _messageHistory.add(message);
          // Persist incoming message to DB
          if (_currentConnection != null) {
            DatabaseService().insertMessage(
              message,
              _currentConnection!.deviceName,
            );
          }
        }
      } else {
        _messageHistory.add(message);
        // Persist incoming message to DB
        if (_currentConnection != null) {
          DatabaseService().insertMessage(
            message,
            _currentConnection!.deviceName,
          );
        }
      }
    }
    for (final listener in _messageListeners) {
      try {
        listener(message);
      } catch (e) {
        debugPrint(
          '[ConnectionService] ❌ Error notifying message listener: $e',
        );
      }
    }
  }

  /// Expose immutable view of message history
  List<DeviceMessage> get messageHistory => List.unmodifiable(_messageHistory);

  /// Clean up previous connection resources WITHOUT emitting disconnected status.
  /// This is used when replacing a connection (glare resolution) to prevent
  /// the manager from removing the service.
  Future<void> _cleanupForReplacement() async {
    debugPrint(
      '[ConnectionService] 🧹 Cleaning up previous connection for replacement...',
    );

    // Cancel subscriptions to prevent onDone/onError triggering disconnect()
    for (final sub in _socketSubscriptions) {
      await sub.cancel();
    }
    _socketSubscriptions.clear();

    _wifiDirectConnSub?.cancel();
    _wifiDirectConnSub = null;
    _teardownWifiDirectDataSocket();

    // Stop keep-alive timer
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;

    // Close sockets
    for (final socket in _sockets) {
      try {
        socket.destroy();
      } catch (_) {}
    }
    _sockets.clear();
    _sendChains.clear();
    _incomingChains.clear();

    for (final p in _frameParsers) {
      p.reset();
    }
    _frameParsers.clear();

    // NOTE: Status is purposefully NOT updated to disconnected here.
    // The caller (acceptConnection) will immediately set it to Connected/Connecting.
  }

  /// Clean up session files (received only) when disconnecting
  Future<void> cleanupSessionFiles() async {
    debugPrint('[ConnectionService] 🧹 Cleaning up session files...');

    // On Desktop (macOS, Windows, Linux), files are saved to user-specified locations or Downloads.
    // On Mobile (Android, iOS), files are saved to app docs dir.
    // To preserve history, we should NOT delete them on disconnect.
    // We only clean up if explicitly requested or if they are partial temps (handled elsewhere)

    debugPrint('[ConnectionService] 🖥️ Session file cleanup disabled');

    // Clear history so next session starts fresh
    _messageHistory.clear();
    debugPrint('[ConnectionService] 🧹 Cleared in-memory history');
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    if (_primarySocket != null &&
        _currentConnection?.status == ConnectionStatus.connected) {
      try {
        final goodbye = DeviceMessage(
          type: 'goodbye',
          content: 'Disconnecting',
          senderName: deviceName,
        );
        // timeout to prevent hanging on disconnect
        await sendMessage(
          goodbye,
        ).timeout(const Duration(milliseconds: 500), onTimeout: () => false);
      } catch (e) {
        // Ignore any errors during goodbye (socket likely closed)
        debugPrint(
          '[ConnectionService] ⚠️  Could not send goodbye message (ignored): $e',
        );
      }
    }
    wifiDirectStatusNotifier.value = WifiDirectStatus.disconnected;

    for (final sub in _socketSubscriptions) {
      await sub.cancel();
    }
    _socketSubscriptions.clear();

    _wifiDirectConnSub?.cancel();
    _wifiDirectConnSub = null;
    _wifiDirectPeersSub?.cancel();
    _wifiDirectPeersSub = null;
    _teardownWifiDirectDataSocket();
    try {
      await _wifiDirectService.stopDiscovery();
      await _wifiDirectService.disconnect();
    } catch (_) {}

    // Stop keep-alive timer
    debugPrint(
      '[ConnectionService] 🛑 Cancelling keep-alive timer (was ${_keepAliveTimer != null ? "active" : "null"})',
    );
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    debugPrint(
      '[ConnectionService] 🛑 Keep-alive timer cancelled and nullified',
    );

    // Stop all watchdog timers
    for (final transfer in _incomingFiles.values) {
      transfer.watchdogTimer?.cancel();
    }
    for (final transfer in _outgoingTransfers.values) {
      transfer.watchdogTimer?.cancel();
    }

    for (final socket in _sockets) {
      try {
        await socket.close();
      } catch (e) {
        debugPrint('[ConnectionService] ⚠️  Error closing socket: $e');
      }
    }
    _sockets.clear();
    _sendChains.clear();
    _incomingChains.clear();

    for (final p in _frameParsers) {
      p.reset();
    }
    _frameParsers.clear();

    _remotePeerAddress = null;
    _remoteWifiDirectPeerId = null;
    _localWifiDirectPeerId = null;
    _remoteWifiDirectName = null;
    _localWifiDirectName = null;
    _wifiDirectAttempted = false;
    _usingWifiDirect = false;

    // Perform session cleanup (delete temp files and clear history)
    await cleanupSessionFiles();

    // Update status
    if (_currentConnection != null) {
      _updateStatus(
        _currentConnection!.copyWith(status: ConnectionStatus.disconnected),
      );
    }
    debugPrint('[ConnectionService] ✅ Disconnected');
  }

  /// Start keep-alive timer to prevent connection timeout
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_primarySocket != null && isConnected) {
        final ping = DeviceMessage(
          type: 'ping',
          content: 'keep-alive',
          senderName: deviceName,
        );
        sendMessage(ping).then((success) {
          if (!success) {
            debugPrint('[ConnectionService] ⚠️  Keep-alive ping failed');
          } else {
            debugPrint(
              '[ConnectionService] ✅ Keep-alive ping sent successfully',
            );
          }
        });
      } else {
        debugPrint(
          '[ConnectionService] ⏸️  Keep-alive timer fired but NOT sending (socket=${_primarySocket != null}, isConnected=$isConnected)',
        );
      }
    });
  }

  /// Start watchdog for outgoing transfer - auto-resume if stalled
  void _startOutgoingWatchdog(String transferId) {
    final transfer = _outgoingTransfers[transferId];
    if (transfer == null) return;

    transfer.watchdogTimer?.cancel();
    transfer.watchdogTimer = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) async {
      final ot = _outgoingTransfers[transferId];
      if (ot == null) {
        timer.cancel();
        return;
      }

      final timeSinceActivity = DateTime.now()
          .difference(ot.lastActivity)
          .inSeconds;
      if (timeSinceActivity > 5 &&
          ot.chunkPermit != null &&
          !ot.chunkPermit!.isCompleted) {
        // Transfer appears stalled - auto-resume
        ot.resumeAttempts++;
        if (ot.resumeAttempts <= 3) {
          debugPrint(
            '[ConnectionService] 🔄 Auto-resuming stalled outgoing transfer $transferId (attempt ${ot.resumeAttempts})',
          );
          // Request receiver to resend ACK for current state
          await sendMessage(
            DeviceMessage(
              type: 'request_ack',
              content: transferId,
              senderName: deviceName,
            ),
          );
          // Release permit to allow progress
          if (ot.chunkPermit != null && !ot.chunkPermit!.isCompleted) {
            ot.chunkPermit!.complete();
            ot.chunkPermit = null;
          }
          ot.resetWatchdog();
        } else {
          debugPrint(
            '[ConnectionService] ❌ Outgoing transfer $transferId failed after ${ot.resumeAttempts} resume attempts',
          );
          timer.cancel();
        }
      }
    });
  }

  /// Start watchdog for incoming transfer - request resend if stalled
  void _startIncomingWatchdog(String transferId) {
    final transfer = _incomingFiles[transferId];
    if (transfer == null) return;

    transfer.watchdogTimer?.cancel();
    transfer.watchdogTimer = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) async {
      final inc = _incomingFiles[transferId];
      if (inc == null) {
        timer.cancel();
        return;
      }

      final timeSinceActivity = DateTime.now()
          .difference(inc.lastActivity)
          .inSeconds;
      if (timeSinceActivity > 5) {
        // No chunks received recently - request sender to resume
        debugPrint(
          '[ConnectionService] 🔄 Auto-resuming stalled incoming transfer $transferId',
        );
        // Send ACK with current nextIndex to tell sender where to resume
        final ack = FileAck(
          transferId: transferId,
          nextExpectedIndex: inc.nextIndex,
          completed: false,
        );
        await sendMessage(
          DeviceMessage(
            type: 'file_ack',
            content: jsonEncode(ack.toJson()),
            senderName: deviceName,
          ),
        );
        inc.resetWatchdog();
      }
    });
  }

  /// Clean up old received files on Android to prevent storage bloat
  /// Removes files older than specified days from Documents directory
  static Future<void> cleanupOldReceivedFiles({int olderThanDays = 7}) async {
    if (!Platform.isAndroid) {
      debugPrint('[ConnectionService] 🧹 Cleanup skipped - not Android');
      return;
    }

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      int deletedCount = 0;
      int deletedBytes = 0;
      int totalFiles = 0;

      debugPrint(
        '[ConnectionService] 🧹 Starting cleanup: files older than $olderThanDays days',
      );
      debugPrint('[ConnectionService] 📂 Directory: ${docsDir.path}');
      debugPrint('[ConnectionService] 🕐 Current time: $now');

      await for (final entity in docsDir.list()) {
        if (entity is File) {
          totalFiles++;
          try {
            final stat = await entity.stat();
            final age = now.difference(stat.modified).inDays;
            final fileName = entity.path.split('/').last;

            debugPrint(
              '[ConnectionService] 📄 File: $fileName, Modified: ${stat.modified}, Age: $age days',
            );

            if (age > olderThanDays) {
              final size = await entity.length();
              await entity.delete();
              deletedCount++;
              deletedBytes += size;
              final mbSize = (size / 1024 / 1024).toStringAsFixed(2);
              debugPrint(
                '[ConnectionService] ✅ Deleted: $fileName ($age days old, $mbSize MB)',
              );
            } else {
              debugPrint(
                '[ConnectionService] ⏭️ Kept: $fileName (Age: $age days <= $olderThanDays)',
              );
            }
          } catch (e) {
            debugPrint(
              '[ConnectionService] ⚠️ Error processing file ${entity.path}: $e',
            );
          }
        }
      }

      debugPrint(
        '[ConnectionService] 📊 Scan complete: $totalFiles files found',
      );

      if (deletedCount > 0) {
        final freedMB = deletedBytes / 1024 / 1024;
        debugPrint(
          '[ConnectionService] ✅ Cleanup complete: Deleted $deletedCount files, freed ${freedMB.toStringAsFixed(2)} MB',
        );

        // Show notification if significant storage freed (>10 MB)
        if (freedMB > 10) {
          NotificationService().showNotification(
            type: NotificationType.fileTransferCompleted,
            title: 'Storage Cleanup',
            body:
                'Freed ${freedMB.toStringAsFixed(1)} MB by removing $deletedCount old files',
          );
        }
      } else {
        debugPrint(
          '[ConnectionService] ✅ Cleanup complete: No old files to delete (scanned $totalFiles files)',
        );
      }
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️ Cleanup failed: $e');
    }
  }

  /// Clean temporary directory on startup to remove leftover transient files.
  /// If [olderThanSeconds] > 0, only files older than that will be removed.
  /// This runs safely and does not block startup (call with .catchError to observe failures).
  static Future<void> cleanupTempFiles({int olderThanSeconds = 0}) async {
    try {
      final tmp = await getTemporaryDirectory();
      final now = DateTime.now();
      int deletedCount = 0;
      int deletedBytes = 0;

      debugPrint(
        '[ConnectionService] 🧹 Starting temp cleanup: dir=${tmp.path}',
      );

      await for (final entity in tmp.list(recursive: false)) {
        try {
          if (entity is File) {
            final stat = await entity.stat();
            final ageSec = now.difference(stat.modified).inSeconds;
            if (olderThanSeconds <= 0 || ageSec > olderThanSeconds) {
              deletedBytes += stat.size;
              await entity.delete();
              deletedCount++;
            }
          } else if (entity is Directory) {
            final stat = await entity.stat();
            final ageSec = now.difference(stat.modified).inSeconds;
            if (olderThanSeconds <= 0 || ageSec > olderThanSeconds) {
              try {
                await entity.delete(recursive: true);
                deletedCount++;
              } catch (_) {
                // Ignore directories that cannot be removed (in use)
              }
            }
          }
        } catch (e) {
          debugPrint('[ConnectionService] ⚠️ Temp cleanup item failed: $e');
        }
      }

      if (deletedCount > 0) {
        final freedMB = deletedBytes / 1024 / 1024;
        debugPrint(
          '[ConnectionService] ✅ Temp cleanup complete: deleted $deletedCount items, freed ${freedMB.toStringAsFixed(2)} MB',
        );
      } else {
        debugPrint(
          '[ConnectionService] ✅ Temp cleanup complete: nothing to delete',
        );
      }
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️ Temp cleanup failed: $e');
    }
  }

  /// Dispose the service
  Future<void> dispose() async {
    debugPrint(
      '[ConnectionService] 🗑️  DISPOSE called for ${_currentConnection?.deviceName ?? deviceName} ($hashCode)',
    );
    await disconnect();
    _errorResetTimer?.cancel();
    _messageListeners.clear();
    _statusListeners.clear();
    debugPrint(
      '[ConnectionService] 🗑️  DISPOSE completed for ${_currentConnection?.deviceName ?? deviceName} ($hashCode)',
    );
  }

  Future<void> _handleBinaryChunk({
    required String transferId,
    required int index,
    required bool isLast,
    required Uint8List bytes,
  }) async {
    // Check if transfer is accepted (file path registered)
    final inc = _incomingFiles[transferId];
    if (inc == null) {
      // Buffer chunks that arrive before acceptFileOffer is called
      _pendingBinary
          .putIfAbsent(transferId, () => [])
          .add(_PendingBinaryChunk(index, Uint8List.fromList(bytes), isLast));
      return;
    }

    // On Android, forward to native receiver (fast path)
    if (Platform.isAndroid && useNativeReceiver) {
      try {
        final t1 = DateTime.now();
        await _forwardToNativeReceiver(transferId, index, isLast, bytes);
        final t2 = DateTime.now();
        if (_enablePerfLogs && index % 256 == 0) {
          debugPrint(
            '[PERF] Forward to native: ${t2.difference(t1).inMilliseconds}ms for chunk $index (${bytes.length} bytes)',
          );
        }
      } catch (e) {
        debugPrint(
          '[ConnectionService] ❌ Failed to forward to native receiver: $e',
        );
      }
      return;
    }

    if (isLast) {
      inc.markFinal(index);
    }

    final t1 = DateTime.now();
    // Ensure bytes are stable beyond this call for the non-native path.
    await inc.processBinary(index, Uint8List.fromList(bytes));
    final t2 = DateTime.now();

    // 🔬 PERF: Always report progress to UI, even if buffering
    // (UI uses this to calculate speed, so accuracy matters)
    _notifyMessageListeners(
      DeviceMessage(
        type: 'file_progress',
        content: inc.offer.fileName,
        senderName: deviceName,
        timestamp: DateTime.now(),
        metadata: {
          'transferId': transferId,
          'bytes': inc.receivedBytes,
          'total': inc.offer.fileSize,
          'mime': inc.offer.mimeType,
          'outgoing': false,
        },
      ),
    );

    // ACK regularly and under buffer pressure
    // 🚀 PERF: ACK every chunk (8MB/16MB) to ensure sender progress bar is in sync with receiver
    if (inc.nextIndex % 1 == 0 ||
        inc._chunkBuffer.length > (ConnectionService._maxPendingChunks ~/ 3)) {
      final t3 = DateTime.now();
      // 🚀 PERF: Don't force flush to disk on every ACK. Let processBinary handle it based on buffer size.
      // await inc._flushWrites();
      await _sendAck(transferId, inc.nextIndex);
      final t4 = DateTime.now();
      if (_enablePerfLogs && index % 256 == 0) {
        debugPrint(
          '[PERF] processBinary: ${t2.difference(t1).inMilliseconds}ms, ACK: ${t4.difference(t3).inMilliseconds}ms @ index $index',
        );
      }
    } else if (_enablePerfLogs && index % 256 == 0) {
      debugPrint(
        '[PERF] processBinary: ${t2.difference(t1).inMilliseconds}ms @ index $index (no ACK)',
      );
    }

    // Completion requires final marker AND all chunks up to it processed
    if (inc.isComplete()) {
      await inc.finish();

      if (inc.offer.sha256 != null) {
        // Stream hash to avoid loading whole file into memory.
        final digest = await sha256.bind(File(inc.path).openRead()).first;
        final calc = digest.toString();
        if (calc != inc.offer.sha256) {
          _notifyMessageListeners(
            DeviceMessage(
              type: 'text',
              content: 'File verification failed: ${inc.offer.fileName}',
              senderName: deviceName,
              timestamp: DateTime.now(),
            ),
          );
        }
      }

      _notifyMessageListeners(
        DeviceMessage(
          type: 'file_complete',
          content: inc.offer.fileName,
          senderName: _currentConnection?.deviceName ?? 'Unknown',
          timestamp: DateTime.now(),
          metadata: {
            'transferId': transferId,
            'size': inc.offer.fileSize,
            'mime': inc.offer.mimeType,
            'path': inc.path,
            'outgoing': false,
          },
        ),
      );

      inc.watchdogTimer?.cancel();
      _incomingFiles.remove(transferId);

      NotificationService().showNotification(
        type: NotificationType.fileTransferCompleted,
        title: 'File Received',
        body: 'Successfully received ${inc.offer.fileName}',
      );

      await _sendAck(transferId, inc.nextIndex, completed: true);
    }
  }

  /// Handle progress updates from native Android receiver
  Future<void> _handleNativeReceiverProgress(MethodCall call) async {
    try {
      if (call.method != 'onProgress' && call.method != 'onAck') return;

      final args = Map<String, dynamic>.from(call.arguments as Map);
      final transferId = (args['transferId'] ?? '') as String;
      if (transferId.isEmpty) return;

      final inc = _incomingFiles[transferId];

      if (call.method == 'onAck') {
        final nextExpectedIndex = (args['nextExpectedIndex'] ?? 0) as int;
        final bytesReceived = (args['bytesReceived'] ?? 0) as int;
        final completed = (args['completed'] ?? false) as bool;

        debugPrint(
          '[ConnectionService] 📨 Native ACK received: transferId=$transferId, nextExpectedIndex=$nextExpectedIndex, bytes=$bytesReceived',
        );

        if (inc != null) {
          inc.resetWatchdog();
          inc.receivedBytes = bytesReceived;
        }

        final ack = FileAck(
          transferId: transferId,
          nextExpectedIndex: nextExpectedIndex,
          completed: completed,
        );

        await _sendControlMessage(
          DeviceMessage(
            type: 'file_ack',
            content: jsonEncode(ack.toJson()),
            senderName: deviceName,
          ),
          // If WiFi Direct is up, keep the ACK path on the same fast link.
          preferWifiDirect: _usingWifiDirect,
        );

        debugPrint(
          '[ConnectionService] 📤 Forwarded ACK to sender: nextExpectedIndex=$nextExpectedIndex',
        );

        return;
      }

      // call.method == 'onProgress'
      final bytes = (args['bytes'] ?? 0) as int;
      final isLast = (args['isLast'] ?? false) as bool;
      final filePath = args['filePath'] as String?;

      if (_enablePerfLogs || isLast) {
        debugPrint(
          '[ConnectionService] 📊 Native receiver progress: $transferId, bytes=$bytes, isLast=$isLast, filePath=$filePath',
        );
      }

      if (inc != null) {
        inc.resetWatchdog();
        inc.receivedBytes = bytes;
      }

      _notifyMessageListeners(
        DeviceMessage(
          type: 'file_progress',
          content: inc?.offer.fileName ?? 'Unknown file',
          senderName: deviceName,
          timestamp: DateTime.now(),
          metadata: {
            'transferId': transferId,
            'bytes': bytes,
            'total': inc?.offer.fileSize ?? 0,
            'mime': inc?.offer.mimeType,
            'outgoing': false,
          },
        ),
      );

      if (isLast && filePath != null && filePath.isNotEmpty) {
        final completedInc = _incomingFiles.remove(transferId);
        completedInc?.watchdogTimer?.cancel();

        if (completedInc != null) {
          // Notify sender of success
          await sendMessage(
            DeviceMessage(
              type: 'file_status',
              content: completedInc.offer.fileName,
              senderName: deviceName,
              timestamp: DateTime.now(),
              metadata: {
                'transferId': transferId,
                'status': 'success',
                'path': filePath,
              },
            ),
          );

          // Force send final ACK to ensure sender unblocks
          await _sendControlMessage(
            DeviceMessage(
              type: 'file_ack',
              senderName: deviceName,
              content: jsonEncode(
                FileAck(
                  transferId: transferId,
                  nextExpectedIndex: completedInc
                      .offer
                      .fileSize, // Use size as index proxy or just assume completed handles it
                  completed: true,
                ).toJson(),
              ),
            ),
          );

          _notifyMessageListeners(
            DeviceMessage(
              type: 'file_complete',
              content: completedInc.offer.fileName,
              senderName: _currentConnection?.deviceName ?? 'Unknown',
              timestamp: DateTime.now(),
              metadata: {
                'transferId': transferId,
                'size': completedInc.offer.fileSize,
                'mime': completedInc.offer.mimeType,
                'path': filePath,
                'outgoing': false,
              },
            ),
          );

          NotificationService().showNotification(
            type: NotificationType.fileTransferCompleted,
            title: 'File Received',
            body: 'Successfully received ${completedInc.offer.fileName}',
          );
        }
      }
    } catch (e, st) {
      debugPrint('[ConnectionService] ❌ Native receiver handler error: $e');
      debugPrint('$st');
    }
  }

  /// Normalize IP address to handle IPv6 mapped IPv4 addresses
  String _normalizeIp(String ip) {
    if (ip.startsWith('::ffff:')) {
      return ip.substring(7);
    }
    return ip;
  }
}

class _IncomingFile {
  final FileOffer offer;
  final String path;
  final RandomAccessFile? sink;
  int receivedBytes;
  int nextIndex;
  final Map<int, Uint8List> _chunkBuffer = {}; // Buffer for out-of-order chunks

  // 🚀 PERF: Buffer writes in memory to reduce disk syscalls
  final BytesBuilder _writeBuffer = BytesBuilder();
  int _writeBufferBytes = 0;
  static const int _writeBufferLimit =
      64 * 1024 * 1024; // 64MB write buffer for maximum batching

  bool _finalSeen = false;
  int? _finalIndex;

  Timer? watchdogTimer;
  DateTime lastActivity = DateTime.now();

  _IncomingFile({
    required this.offer,
    required this.path,
    required this.sink,
    required this.receivedBytes,
    required this.nextIndex,
  }) {
    _startWatchdog();
  }

  void _startWatchdog() {
    watchdogTimer?.cancel();
    watchdogTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      final elapsed = DateTime.now().difference(lastActivity);
      if (elapsed.inSeconds >= 5) {
        debugPrint(
          '[ConnectionService] ⚠️ Transfer stalled? Waiting for chunk $nextIndex (buffered: ${_chunkBuffer.length}) for ${elapsed.inSeconds}s',
        );
      }
    });
  }

  void resetWatchdog() {
    lastActivity = DateTime.now();
  }

  void cancelWatchdog() {
    watchdogTimer?.cancel();
    watchdogTimer = null;
  }

  void markFinal(int index) {
    _finalSeen = true;
    _finalIndex = index;
  }

  /// Flush accumulated writes to disk
  Future<void> _flushWrites() async {
    if (_writeBufferBytes == 0) return;

    final s = sink;
    if (s == null) return;

    final data = _writeBuffer.takeBytes();
    await s.writeFrom(data);
    _writeBufferBytes = 0;
    debugPrint('[PERF] Flushed ${data.length ~/ (1024 * 1024)}MB to disk');
  }

  // Process a binary chunk (new method for binary protocol)
  Future<void> processBinary(int index, Uint8List bytes) async {
    resetWatchdog();

    final s = sink;
    if (s == null) {
      throw StateError('Incoming sink is null (native receiver path)');
    }

    if (index == nextIndex) {
      // Buffer the chunk instead of writing immediately
      _writeBuffer.add(bytes);
      _writeBufferBytes += bytes.length;
      receivedBytes += bytes.length;
      nextIndex++;

      // Write any buffered chunks that are now in sequence
      while (_chunkBuffer.containsKey(nextIndex)) {
        final bufferedBytes = _chunkBuffer.remove(nextIndex)!;
        _writeBuffer.add(bufferedBytes);
        _writeBufferBytes += bufferedBytes.length;
        receivedBytes += bufferedBytes.length;
        nextIndex++;
      }

      // Flush if buffer is full OR every 32MB of buffered data
      // This ensures we don't report stale progress from old buffered data
      if (_writeBufferBytes >= _writeBufferLimit) {
        await _flushWrites();
      }

      debugPrint(
        '[ConnectionService] ✅ Processed binary chunk $index, next expected: $nextIndex, buffered: ${_chunkBuffer.length}, writeBuffer: ${_writeBufferBytes ~/ (1024 * 1024)}MB',
      );
    } else if (index > nextIndex) {
      // Future chunk, buffer it
      _chunkBuffer[index] = bytes;
      debugPrint(
        '[ConnectionService] 📦 Buffered binary chunk $index (expecting $nextIndex), buffer size: ${_chunkBuffer.length}',
      );
    } else {
      // Duplicate or past chunk, ignore
      debugPrint(
        '[ConnectionService] ⚠️ Ignoring duplicate/past binary chunk $index (expecting $nextIndex)',
      );
    }
  }

  // Process a chunk, handling out-of-order arrival (legacy JSON method)
  Future<void> processChunk(FileChunk chunk) async {
    final bytes = base64Decode(chunk.dataBase64);
    resetWatchdog(); // Reset on any chunk receive

    final s = sink;
    if (s == null) {
      throw StateError('Incoming sink is null (native receiver path)');
    }

    if (chunk.index == nextIndex) {
      // This is the expected chunk, write it immediately
      await s.writeFrom(bytes);
      receivedBytes += bytes.length;
      nextIndex++;

      // Write any buffered chunks that are now in sequence
      while (_chunkBuffer.containsKey(nextIndex)) {
        final bufferedBytes = _chunkBuffer.remove(nextIndex)!;
        await s.writeFrom(bufferedBytes);
        receivedBytes += bufferedBytes.length;
        nextIndex++;
      }
      debugPrint(
        '[ConnectionService] ✅ Processed chunk ${chunk.index}, next expected: $nextIndex, buffered: ${_chunkBuffer.length}',
      );
    } else if (chunk.index > nextIndex) {
      // Future chunk, buffer it
      _chunkBuffer[chunk.index] = bytes;
      debugPrint(
        '[ConnectionService] 📦 Buffered chunk ${chunk.index} for transfer (expecting $nextIndex), buffer size: ${_chunkBuffer.length}',
      );
    } else {
      // Duplicate or past chunk, ignore
      debugPrint(
        '[ConnectionService] ⚠️ Ignoring duplicate/past chunk ${chunk.index} (expecting $nextIndex)',
      );
    }
  }

  // Finish transfer and verify
  Future<void> finish() async {
    // 🚀 Flush remaining writes before closing
    await _flushWrites();
    await sink?.flush();
    await sink?.close();
    debugPrint('[ConnectionService] ✅ Transfer complete and file closed');
  }

  // Check if transfer is complete (all chunks received up to the final marker)
  bool isComplete() {
    if (!_finalSeen || _finalIndex == null) return false;
    return _chunkBuffer.isEmpty && nextIndex == _finalIndex! + 1;
  }
}

class _OutgoingTransfer {
  final String fileName;
  int lastAckIndex; // last index confirmed by receiver
  final int totalSize; // total bytes
  final Map<int, int> chunkSizes = {}; // index -> bytes
  int pendingBytes = 0; // bytes sent but not yet ACKed
  int sentBytes = 0; // bytes confirmed by ACKs
  bool initialAckReceived = false;
  Completer<void>? chunkPermit; // completed when next chunk may be sent
  Completer<void>? completer; // completed when transfer fully done
  Timer? watchdogTimer;
  DateTime lastActivity = DateTime.now();
  int resumeAttempts = 0;

  // Optional metadata for better UI on sender side
  final String? mime;
  final String? path;

  void resetWatchdog() {
    lastActivity = DateTime.now();
  }

  _OutgoingTransfer({
    required this.fileName,
    required this.lastAckIndex,
    required this.totalSize,
    this.mime,
    this.path,
  });
}

/// Binary frame parser for file chunks
class _FrameParser {
  Uint8List _buf = Uint8List(0);
  int _start = 0;
  int _end = 0;

  void reset() {
    _buf = Uint8List(0);
    _start = 0;
    _end = 0;
  }

  Future<void> process(Uint8List data, ConnectionService svc) async {
    if (data.isEmpty) return;
    _append(data);

    while (true) {
      final available = _end - _start;
      if (available < 9) return; // need [MAGIC(4)] + [len(4)] + [type(1)]

      // Check magic byte
      final magic = _readInt32(_buf, _start);
      if (magic != ConnectionService._frameMagic) {
        // Fast scan to find next magic byte
        final found = _scanForMagic();
        if (!found) return; // wait for more data to find magic
        // If found, _start is updated to point to magic
        continue;
      }

      final payloadLen = _readInt32(_buf, _start + 4);
      if (payloadLen <= 0 ||
          payloadLen > ConnectionService._maxFramePayloadBytes) {
        // If this looks like an HTTP request accidentally hitting the P2P port,
        // close the connection to avoid endless garbage parsing.
        if (_looksLikeHttp(_buf, _start, _end)) {
          debugPrint(
            '[FrameParser] ⚠️ Detected HTTP on P2P socket; disconnecting',
          );
          reset();
          await svc.disconnect();
          return;
        }

        debugPrint(
          '[FrameParser] ⚠️ Invalid payloadLen=$payloadLen, skipping current magic and rescanning.',
        );
        _start += 1; // Advance past this valid magic to look for another one
        continue;
      }

      final frameLen = 4 + 4 + payloadLen; // MAGIC + LEN + PAYLOAD
      if (available < frameLen) return; // wait for more

      final type = _buf[_start + 8];

      // Validate frame type before extracting payload
      if (type != 0 && type != 1) {
        debugPrint(
          '[FrameParser] ⚠️ Unknown frame type=$type at offset $_start. Skipping current magic.',
        );
        _start += 1;
        continue;
      }

      // Additional validation: JSON control messages (type 0) should be reasonably small
      if (type == 0 && payloadLen > 1024 * 1024) {
        debugPrint(
          '[FrameParser] ⚠️ Suspiciously large control message: $payloadLen bytes. Skipping.',
        );
        _start += 1;
        continue;
      }

      final payloadStart = _start + 9; // MAGIC(4) + LEN(4) + TYPE(1)
      final payloadEnd = _start + frameLen;
      final payload = Uint8List.sublistView(_buf, payloadStart, payloadEnd);

      try {
        if (type == 0) {
          final jsonStr = utf8.decode(payload, allowMalformed: false);
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          final message = DeviceMessage.fromJson(json);
          await svc._handleIncomingMessage(message);
        } else if (type == 1) {
          await _parseBinaryChunkPayload(payload, svc);
        }
      } catch (e) {
        debugPrint('[FrameParser] ❌ Frame parse error: $e');
        // If parsing fails despite magic byte, it might be a collision or corruption
        _start += 1;
        continue;
      }

      _start += frameLen;
      if (_start == _end) {
        // fully consumed
        _start = 0;
        _end = 0;
        return;
      }

      // Compact occasionally to avoid unbounded growth.
      if (_start > 0 && _start > (_buf.length ~/ 2)) {
        _compact();
      }
    }
  }

  bool _scanForMagic() {
    // efficient byte-by-byte scan for magic
    final magicBytes = [0xAC, 0xDC, 0x12, 0x34];

    // We start at _start to see if we need to advance
    // But since we already checked that _start isn't magic (in the caller),
    // we should start scanning from _start + 1

    for (int i = _start + 1; i <= _end - 4; i++) {
      if (_buf[i] == magicBytes[0] &&
          _buf[i + 1] == magicBytes[1] &&
          _buf[i + 2] == magicBytes[2] &&
          _buf[i + 3] == magicBytes[3]) {
        _start = i;
        return true;
      }
    }

    // If not found, discard everything except the last 3 bytes
    // (which might be the start of a magic sequence arriving later)
    if (_end > _start + 3) {
      _start = _end - 3;
    }
    return false;
  }

  bool _looksLikeHttp(Uint8List buf, int start, int end) {
    final available = end - start;
    if (available < 4) return false;

    final b0 = buf[start];
    final b1 = buf[start + 1];
    final b2 = buf[start + 2];
    final b3 = buf[start + 3];

    // "GET ", "POST", "HEAD", "PUT ", "HTTP"
    final isGet = b0 == 0x47 && b1 == 0x45 && b2 == 0x54 && b3 == 0x20;
    final isPost = b0 == 0x50 && b1 == 0x4F && b2 == 0x53 && b3 == 0x54;
    final isHead = b0 == 0x48 && b1 == 0x45 && b2 == 0x41 && b3 == 0x44;
    final isPut = b0 == 0x50 && b1 == 0x55 && b2 == 0x54 && b3 == 0x20;
    final isHttp = b0 == 0x48 && b1 == 0x54 && b2 == 0x54 && b3 == 0x50;

    return isGet || isPost || isHead || isPut || isHttp;
  }

  Future<void> _parseBinaryChunkPayload(
    Uint8List payload,
    ConnectionService svc,
  ) async {
    // payload = [tidLen(1)][tid][index(4)][isLast(1)][bytes...]
    if (payload.isEmpty) return;
    int offset = 0;

    final tidLen = payload[offset++];
    if (tidLen <= 0 || tidLen > ConnectionService._maxTransferIdBytes) {
      throw StateError('Invalid transferId length: $tidLen');
    }
    if (payload.length < 1 + tidLen + 4 + 1) {
      throw StateError('Truncated binary chunk header');
    }

    final transferId = utf8.decode(payload.sublist(offset, offset + tidLen));
    offset += tidLen;

    final index = _readInt32(payload, offset);
    offset += 4;
    if (index < 0) {
      throw StateError('Invalid chunk index: $index');
    }

    final isLast = payload[offset++] == 1;
    // Avoid copying here; copy only when we must retain bytes.
    final bytes = Uint8List.sublistView(payload, offset);

    if (ConnectionService._enableBinaryChunkLogs &&
        (isLast || (index % ConnectionService._binaryChunkLogEveryN == 0))) {
      debugPrint(
        '[FrameParser] 📥 Binary chunk: transferId=$transferId, index=$index, isLast=$isLast, bytes=${bytes.length}',
      );
    }

    await svc._handleBinaryChunk(
      transferId: transferId,
      index: index,
      isLast: isLast,
      bytes: bytes,
    );
  }

  void _append(Uint8List data) {
    final needed = (_end - _start) + data.length;
    if (_buf.isEmpty) {
      _buf = Uint8List(needed);
      _buf.setRange(0, data.length, data);
      _start = 0;
      _end = data.length;
      return;
    }

    // Ensure capacity.
    if (_buf.length < needed) {
      final newCap = _nextPow2(needed);
      final newBuf = Uint8List(newCap);
      final remaining = _end - _start;
      if (remaining > 0) {
        // Create a copy to avoid concurrent modification error
        final oldData = Uint8List.fromList(_buf.sublist(_start, _end));
        newBuf.setRange(0, remaining, oldData);
      }
      _buf = newBuf;
      _start = 0;
      _end = remaining;
    } else if (_start > 0 && (_buf.length - _end) < data.length) {
      _compact();
    }

    _buf.setRange(_end, _end + data.length, data);
    _end += data.length;
  }

  void _compact() {
    final remaining = _end - _start;
    if (remaining <= 0) {
      _start = 0;
      _end = 0;
      return;
    }
    _buf.setRange(0, remaining, _buf, _start);
    _start = 0;
    _end = remaining;
  }

  int _nextPow2(int v) {
    int n = 1;
    while (n < v) {
      n <<= 1;
    }
    return n;
  }
}

/// Pending binary chunk that arrived before file was accepted
class _PendingBinaryChunk {
  final int index;
  final Uint8List data;
  final bool isLast;

  _PendingBinaryChunk(this.index, this.data, this.isLast);
}
