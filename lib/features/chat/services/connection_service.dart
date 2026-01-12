import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/connection_state.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fylooo/models/file_transfer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fylooo/services/notification_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter/services.dart';
import 'package:fylooo/features/netcat/netcat_service.dart';
import 'package:fylooo/features/wifi_direct/wifi_direct_service.dart';

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
  final Map<String, FileOffer> _pendingOffers = {};
  final Map<String, String> _outgoingFiles = {};
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

  bool _wifiDirectPreparing = false;
  StreamSubscription<WiFiDirectConnectionEvent>? _wifiDirectConnSub;
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


  Future<void> _sendFile(String remoteIp, String path, String transferId) async {
    final file = File(path);
    if (!await file.exists()) {
      _sendTextMessage(remoteIp, 'File not found: $path');
      return;
    }
    try {
      final ip = (_usingWifiDirect && _wifiDirectIpAddress != null)
          ? _wifiDirectIpAddress!
          : remoteIp;
      await NetcatService().sendFile(
        ip: ip,
        file: file,
        transferId: transferId,
      );
      _notifyMessageListeners(
        DeviceMessage(
          type: 'file_complete',
          content: transferId,
          senderName: deviceName,
          timestamp: DateTime.now(),
          metadata: {
            'transferId': transferId,
            'path': file.path,
            'size': await file.length(),
            'outgoing': true,
          },
        ),
      );
    } catch (e) {
      _sendTextMessage(remoteIp, 'Failed to send file: $e');
    } finally {
      _outgoingFiles.remove(transferId);
    }
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
      // If socket is in bad state, trigger reconnection
      if (e.toString().contains('StreamSink is bound') ||
          e.toString().contains('Socket is closed')) {
        debugPrint(
          '[ConnectionService] Socket is in bad state, will attempt to recover',
        );
        _handleConnectionError('Socket write error: $e');
      }
      rethrow;
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
    socket.add(buffer.takeBytes());
    if (forceFlush) {
      await socket.flush();
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


  ConnectionService({required this.deviceName}) {
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

    _initNetcat();
  }

  Future<void> _initNetcat() async {
    try {
      Directory? dir;
      if (Platform.isAndroid || Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        dir = await getDownloadsDirectory();
        dir ??= await getApplicationDocumentsDirectory();
      }
      if (dir != null) {
        await NetcatService().startReceiver(saveDirectory: dir.path);
      }

      NetcatService().incomingProgress.listen((progressData) {
        final transferId = progressData['transferId'];
        final totalSize = progressData['totalSize'];
        final progress = progressData['progress'];
        final path = progressData['path'];
        _notifyMessageListeners(
          DeviceMessage(
            type: 'file_progress',
            content: transferId,
            senderName: deviceName,
            timestamp: DateTime.now(),
            metadata: {
              'transferId': transferId,
              'bytes': (progress * totalSize).toInt(),
              'total': totalSize,
              'outgoing': false,
              'path': path,
            },
          ),
        );
      });
      NetcatService().completion.listen((completionData) {
        final transferId = completionData['transferId'];
        final path = completionData['path'];
        final size = completionData['size'];
        _notifyMessageListeners(
          DeviceMessage(
            type: 'file_complete',
            content: transferId,
            senderName: deviceName,
            timestamp: DateTime.now(),
            metadata: {
              'transferId': transferId,
              'path': path,
              'size': size,
              'outgoing': false,
            },
          ),
        );
      });
      NetcatService().outgoingProgress.listen((progressData) {
        final transferId = progressData['transferId'];
        final totalSize = progressData['totalSize'];
        final progress = progressData['progress'];
        _notifyMessageListeners(
          DeviceMessage(
            type: 'file_progress',
            content: transferId,
            senderName: deviceName,
            timestamp: DateTime.now(),
            metadata: {
              'transferId': transferId,
              'bytes': (progress * totalSize).toInt(),
              'total': totalSize,
              'outgoing': true,
              'path': _outgoingFiles[transferId],
            },
          ),
        );
      });
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️ Failed to init Netcat: $e');
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
    return;
    // Only attempt WiFi Direct on Android
    if (!Platform.isAndroid) {
      debugPrint('[ConnectionService] 📡 WiFi Direct: Not Android, skipping');
      return;
    }

    wifiDirectStatusNotifier.value = WifiDirectStatus.connecting;

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
        final socket = await _wifiDirectServer!.first;
        await _attachWifiDirectDataSocket(socket);
      } else {
        debugPrint(
          '[ConnectionService] 🚀 WiFi Direct: connecting to $ipAddress:$port',
        );
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
      _wifiDirectIpAddress = ipAddress; // Store for DPFTP usage
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

      debugPrint(
        '[ConnectionService] 📡 WiFi Direct: remote p2pId=$_remoteWifiDirectPeerId, p2pName=$_remoteWifiDirectName',
      );

      // If both Android, respond with acceptance
      if (Platform.isAndroid) {
        await _wifiDirectService.initialize();
        if (_wifiDirectService.isSupported) {
          final self = await _wifiDirectService.getThisDevice();
          _localWifiDirectPeerId = self?.id;
          _localWifiDirectName = self?.name;
        }

        debugPrint(
          '[ConnectionService] 📡 WiFi Direct: sending accept with local p2pId=$_localWifiDirectPeerId, p2pName=$_localWifiDirectName',
        );
        await sendMessage(
          DeviceMessage(
            type: 'wifi_direct_accept',
            content: 'Accepted',
            senderName: deviceName,
            metadata: {
              'platform': 'android',
              if (_localWifiDirectPeerId != null)
                'p2pId': _localWifiDirectPeerId,
              if (_localWifiDirectName != null) 'p2pName': _localWifiDirectName,
            },
          ),
        );
        debugPrint('[ConnectionService] 📡 Sent WiFi Direct acceptance');

        // Prepare responder side (register receiver + wait for group formation).
        unawaited(_prepareWiFiDirectUpgrade(initiator: false));
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

      if (file.path != null) {
        _outgoingFiles[transferId] = file.path!;
        await _sendFile(_currentConnection!.ipAddress, file.path!, transferId);
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

    // Choose directory: Downloads on desktop, Documents on mobile
    Directory? dir;
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

    if (dir == null) {
      debugPrint('[ConnectionService] Could not get a save directory');
      return;
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

    NetcatService().acceptFile(transferId, path, offer.fileSize);
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
    _currentConnection = info;
    for (final listener in List.of(_statusListeners)) {
      listener(info);
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
        }
      } else {
        _messageHistory.add(message);
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
        await sendMessage(goodbye);
      } catch (e) {
        debugPrint(
          '[ConnectionService] ⚠️  Could not send goodbye message: $e',
        );
      }
    }

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
      final tmp = await getApplicationDocumentsDirectory();
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



  /// Normalize IP address to handle IPv6 mapped IPv4 addresses
  String _normalizeIp(String ip) {
    if (ip.startsWith('::ffff:')) {
      return ip.substring(7);
    }
    return ip;
  }
}




