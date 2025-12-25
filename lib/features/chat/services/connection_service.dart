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

// Binary frame helpers
Uint8List _int32(int value) {
  final b = ByteData(4);
  b.setInt32(0, value, Endian.big);
  return b.buffer.asUint8List();
}

int _readInt32(Uint8List data, int offset) {
  return ByteData.sublistView(data, offset, offset + 4).getInt32(0, Endian.big);
}

/// Service for managing device-to-device connections
class ConnectionService {
  final String deviceName;
  Socket? _socket;
  ConnectionInfo? _currentConnection;
  final List<Function(DeviceMessage)> _messageListeners = [];
  final List<Function(ConnectionInfo)> _statusListeners = [];
  final List<DeviceMessage> _messageHistory = [];
  StreamSubscription? _socketSubscription;
  Timer? _keepAliveTimer;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  Timer? _errorResetTimer;
  final Map<String, _IncomingFile> _incomingFiles = {};
  final Map<String, FileOffer> _pendingOffers = {};
  final Map<String, _OutgoingTransfer> _outgoingTransfers = {};
  final Map<String, List<_PendingBinaryChunk>> _pendingBinary = {};
  // Keep this conservative to avoid OOM on mobile (chunkSize is 1MB).
  static const int _maxPendingChunks = 128;
  Future<void> _sendChain = Future.value();
  Future<void> _incomingChain = Future.value();
  final _frameParser = _FrameParser();

  static const int _maxFramePayloadBytes = 8 * 1024 * 1024; // 8MB
  static const int _maxTransferIdBytes = 128;

  Future<void> _writeFrame(
    int type,
    Uint8List payload, {
    bool forceFlush = false,
  }) async {
    if (_socket == null) return;

    // frame = [payloadLen:int32][type:1][payload]
    final payloadLen = 1 + payload.length;

    final buffer = BytesBuilder(copy: false);
    buffer.add(_int32(payloadLen));
    buffer.add([type & 0xFF]);
    buffer.add(payload);
    _socket!.add(buffer.takeBytes());
    if (forceFlush) {
      await _socket!.flush();
    }
  }

  Future<void> _enqueueFrame(
    int type,
    Uint8List payload, {
    bool forceFlush = false,
  }) async {
    // Serialize ALL socket writes (JSON + binary) to preserve ordering.
    _sendChain = _sendChain.then((_) async {
      await _writeFrame(type, payload, forceFlush: forceFlush);
    });
    await _sendChain;
  }

  /// Send binary file chunk without JSON/base64 overhead
  Future<void> _sendBinaryChunk({
    required String transferId,
    required int index,
    required bool isLast,
    required Uint8List bytes,
    bool flush = false,
  }) async {
    final tid = utf8.encode(transferId);

    if (tid.length > _maxTransferIdBytes) {
      throw StateError('transferId too long (${tid.length} bytes)');
    }

    final buffer = BytesBuilder();
    buffer.add([tid.length]);
    buffer.add(tid);
    buffer.add(_int32(index));
    buffer.add([isLast ? 1 : 0]);
    buffer.add(bytes);

    // Wrap into unified framing: type=1, payload is the chunk fields above.
    await _enqueueFrame(1, buffer.takeBytes(), forceFlush: flush);
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
    await sendMessage(
      DeviceMessage(
        type: 'file_ack',
        content: jsonEncode(ack.toJson()),
        senderName: deviceName,
      ),
    );
  }

  ConnectionService({required this.deviceName}) {
    debugPrint(
      '[ConnectionService] 🆕 NEW ConnectionService instance created for device: $deviceName ($hashCode)',
    );
  }

  /// Get current connection info
  ConnectionInfo? get currentConnection => _currentConnection;

  /// Check if connected
  bool get isConnected =>
      _currentConnection?.status == ConnectionStatus.connected;

  /// Get pending file offers
  Map<String, FileOffer> get pendingOffers => Map.unmodifiable(_pendingOffers);

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
  Future<bool> connect(String deviceName, String ipAddress, int port) async {
    debugPrint(
      '[ConnectionService] 🔌 Connecting to $deviceName at $ipAddress:$port',
    );

    // Prevent duplicate connection attempts
    if (currentConnection?.status == ConnectionStatus.connecting) {
      return false;
    }
    if (currentConnection?.status == ConnectionStatus.connected) {
      return true;
    }

    // If socket exists from previous connection, disconnect first
    if (_socket != null) {
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
      // Attempt to connect with timeout
      _socket = await Socket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 10),
      );

      debugPrint('[ConnectionService] ✅ Socket connected successfully');
      _socket!.setOption(SocketOption.tcpNoDelay, true);

      // Set up socket listener
      _socketSubscription = _socket!.listen(
        _handleIncomingData,
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

      return true; // TCP is up; logical connection will switch to connected on handshake
    } on SocketException catch (e) {
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

    // If already connected, disconnect first and wait for stream to be released
    if (_socket != null) {
      debugPrint(
        '[ConnectionService] ⚠️  Already have a socket, disconnecting...',
      );
      await disconnect();
      // Wait a bit for the stream to be fully released
      await Future.delayed(const Duration(milliseconds: 100));
      debugPrint('[ConnectionService] ✅ Previous connection cleaned up');
    }

    try {
      _socket = socket;
      final ipAddress = socket.remoteAddress.address;
      final port = socket.remotePort;

      _updateStatus(
        ConnectionInfo(
          deviceName: deviceName,
          ipAddress: ipAddress,
          port: port,
          status: ConnectionStatus.connecting,
        ),
      );

      // Configure socket options
      try {
        _socket!.setOption(SocketOption.tcpNoDelay, true);
        debugPrint('[ConnectionService] ✅ Socket options configured');
      } catch (e) {
        debugPrint('[ConnectionService] ⚠️  Failed to set socket options: $e');
      }

      // Set up socket listener directly (no broadcast stream)
      debugPrint('[ConnectionService] 🎧 Setting up socket listener...');
      try {
        _socketSubscription = _socket!.listen(
          _handleIncomingData,
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
        debugPrint(
          '[ConnectionService] ✅ Socket listener attached successfully',
        );
      } catch (e) {
        debugPrint(
          '[ConnectionService] ❌ Failed to attach socket listener: $e',
        );
        throw Exception('Failed to listen to socket: $e');
      }

      // Send handshake response
      debugPrint('[ConnectionService] 📤 Sending handshake response...');
      await _sendHandshake();

      // Start keep-alive timer
      _startKeepAlive();

      // Update connection status
      _updateStatus(
        ConnectionInfo(
          deviceName: deviceName,
          ipAddress: ipAddress,
          port: port,
          status: ConnectionStatus.connected,
          connectedAt: DateTime.now(),
        ),
      );

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
    );
    await sendMessage(handshake);
  }

  /// Send a message to connected device
  Future<bool> sendMessage(DeviceMessage message) async {
    if (_socket == null) {
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
  void _handleIncomingData(List<int> data) async {
    // IMPORTANT: Socket.listen can invoke this callback again before an async
    // invocation has finished. Serialize all inbound parsing/handling to avoid
    // concurrent RandomAccessFile operations.
    _incomingChain = _incomingChain
        .then((_) async {
          await _frameParser.process(Uint8List.fromList(data), this);
        })
        .catchError((e) {
          debugPrint('[ConnectionService] ❌ Incoming processing error: $e');
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
      final wasConnected = isConnected;
      if (!wasConnected &&
          _currentConnection != null &&
          _currentConnection!.status == ConnectionStatus.connecting) {
        debugPrint(
          '[ConnectionService] 🤝 Acceptance received from ${message.senderName}. Marking as connected.',
        );
        _updateStatus(
          _currentConnection!.copyWith(
            status: ConnectionStatus.connected,
            connectedAt: DateTime.now(),
          ),
        );
        _startKeepAlive();
        await _sendHandshake();
      } else {
        debugPrint(
          '[ConnectionService] 🤝 Received handshake (already connected), ignoring',
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
          for (int i = oldIndex + 1; i <= newIndex; i++) {
            outgoing.sentBytes += outgoing.chunkSizes[i] ?? 0;
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
          await inc.sink.close();
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
  Future<void> pickAndSendFile() async {
    if (!isConnected || _socket == null) {
      debugPrint('[ConnectionService] ⚠️ Not connected; cannot send file');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      withReadStream: true,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    for (final file in result.files) {
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

      // Stream chunks
      final int chunkSize = (Platform.isAndroid || Platform.isIOS)
          ? 1024 *
                1024 // 1MB mobile
          : 4 * 1024 * 1024; // 4MB desktop
      int index = 0;
      final stream = file.readStream;
      if (stream == null) continue;

      // Register outgoing transfer
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

          debugPrint(
            '[ConnectionService] ✅ Initial ACK received, starting chunk stream for $transferId',
          );
          // Start watchdog for sender side
          _startOutgoingWatchdog(transferId);
        } catch (e) {
          debugPrint('[ConnectionService] ❌ Initial ACK error: $e');
          _outgoingTransfers.remove(transferId);
          rethrow;
        }
      }

      await for (final data in stream) {
        int offset = 0;
        while (offset < data.length) {
          final end = (offset + chunkSize).clamp(0, data.length);
          final slice = data.sublist(offset, end);
          // Wait for permit if previous chunk not acked
          final ot = _outgoingTransfers[transferId];
          if (ot == null) break; // Cancelled

          final pendingChunks = index - ot.lastAckIndex - 1;
          if (pendingChunks >= _maxPendingChunks) {
            ot.chunkPermit = Completer<void>();
            debugPrint(
              '[ConnectionService] ⏳ Flow control: waiting at chunk $index (pending=$pendingChunks, lastAck=${ot.lastAckIndex})',
            );
            await ot.chunkPermit!.future;
            debugPrint(
              '[ConnectionService] ✅ Flow control released at chunk $index',
            );
          }

          // Record chunk size for accurate progress
          ot.chunkSizes[index] = slice.length;

          // Send binary chunk directly (no JSON, no base64)
          await _sendBinaryChunk(
            transferId: transferId,
            index: index++,
            isLast: false,
            bytes: Uint8List.fromList(slice),
            flush: (index % 8 == 0),
          );
          ot.resetWatchdog(); // Reset on successful chunk send

          // Yield periodically to allow ACKs to be received and processed
          if (index % 128 == 0) {
            await Future.microtask(() {});
          }

          offset = end;
        }
      }
      // Final marker
      final otFinal = _outgoingTransfers[transferId];
      if (otFinal != null) {
        final pendingChunks = index - otFinal.lastAckIndex - 1;
        if (pendingChunks >= _maxPendingChunks) {
          otFinal.chunkPermit = Completer<void>();
          debugPrint(
            '[ConnectionService] ⏳ Final: waiting for ACK (pending=$pendingChunks)',
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
        await otFinal.completer!.future; // Wait for final ack
      }
    }
  }

  /// Send shared files from share intent
  Future<void> sendSharedFiles(List<SharedMediaFile> sharedFiles) async {
    debugPrint(
      '[ConnectionService] 📤 sendSharedFiles called with ${sharedFiles.length} files',
    );
    if (!isConnected || _socket == null) {
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
      final int chunkSize = (Platform.isAndroid || Platform.isIOS)
          ? 1024 *
                1024 // 1MB mobile
          : 4 * 1024 * 1024; // 4MB desktop
      int index = 0;
      final stream = file.openRead();

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

      await for (final data in stream) {
        int offset = 0;
        while (offset < data.length) {
          final end = (offset + chunkSize).clamp(0, data.length);
          final slice = data.sublist(offset, end);
          final ot = _outgoingTransfers[transferId];
          if (ot == null) break;

          final pendingChunks = index - ot.lastAckIndex - 1;
          if (pendingChunks >= _maxPendingChunks) {
            ot.chunkPermit = Completer<void>();
            debugPrint(
              '[ConnectionService] ⏳ Flow control: waiting at chunk $index (pending=$pendingChunks)',
            );
            await ot.chunkPermit!.future;
          }

          ot.chunkSizes[index] = slice.length;

          // Send binary chunk directly (no JSON, no base64)
          await _sendBinaryChunk(
            transferId: transferId,
            index: index++,
            isLast: false,
            bytes: Uint8List.fromList(slice),
            flush: (index % 8 == 0),
          );

          ot.resetWatchdog();

          // Yield periodically to allow ACKs to be received and processed
          if (index % 128 == 0) {
            await Future.microtask(() {});
          }

          offset = end;
        }
      }

      // Final marker
      final otFinal = _outgoingTransfers[transferId];
      if (otFinal != null) {
        final pendingChunks = index - otFinal.lastAckIndex - 1;
        if (pendingChunks >= _maxPendingChunks) {
          otFinal.chunkPermit = Completer<void>();
          debugPrint(
            '[ConnectionService] ⏳ Final: waiting for ACK (pending=$pendingChunks)',
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
    final raf = await File(path).open(mode: FileMode.write);
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
        await inc.sink.close();
      } catch (_) {}
    }
    final out = _outgoingTransfers.remove(transferId);
    if (out != null) {
      out.watchdogTimer?.cancel(); // Stop watchdog
    }
    _pendingOffers.remove(transferId);
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
    _notifyStatusListeners(info);
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

  /// Notify status listeners
  void _notifyStatusListeners(ConnectionInfo info) {
    for (final listener in _statusListeners) {
      try {
        listener(info);
      } catch (e) {
        debugPrint('[ConnectionService] ❌ Error notifying status listener: $e');
      }
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    // Send goodbye message if connected
    if (_socket != null &&
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

    // Cancel socket subscription
    await _socketSubscription?.cancel();
    _socketSubscription = null;

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

    try {
      await _socket?.close();
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️  Error closing socket: $e');
    }
    _socket = null;

    // Reset parser state
    _frameParser.reset();
    _incomingChain = Future.value();

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
      if (_socket != null && isConnected) {
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
          '[ConnectionService] ⏸️  Keep-alive timer fired but NOT sending (socket=${_socket != null}, isConnected=$isConnected)',
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
  static Future<void> cleanupOldReceivedFiles({int olderThanDays = 1}) async {
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
              debugPrint(
                '[ConnectionService] ✅ Deleted: $fileName (${age} days old, ${(size / 1024 / 1024).toStringAsFixed(2)} MB)',
              );
            } else {
              debugPrint(
                '[ConnectionService] ⏭️  Kept: $fileName (only $age days old)',
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
    final inc = _incomingFiles[transferId];
    if (inc == null) {
      _pendingBinary
          .putIfAbsent(transferId, () => [])
          .add(_PendingBinaryChunk(index, bytes, isLast));
      return;
    }

    if (isLast) {
      inc.markFinal(index);
    }

    await inc.processBinary(index, bytes);

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
    if (inc.nextIndex % 32 == 0 ||
        inc._chunkBuffer.length > (ConnectionService._maxPendingChunks ~/ 3)) {
      await _sendAck(transferId, inc.nextIndex);
    }

    // Completion requires final marker AND all chunks up to it processed
    if (isLast && inc.isComplete()) {
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
          senderName: deviceName,
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

      if (Platform.isAndroid) {
        ConnectionService.cleanupOldReceivedFiles().catchError((e) {
          debugPrint('[ConnectionService] ⚠️ Cleanup error: $e');
        });
      }

      await _sendAck(transferId, inc.nextIndex, completed: true);
    }
  }
}

class _IncomingFile {
  final FileOffer offer;
  final String path;
  final RandomAccessFile sink;
  int receivedBytes;
  int nextIndex;
  final Map<int, Uint8List> _chunkBuffer = {}; // Buffer for out-of-order chunks

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
  });

  void resetWatchdog() {
    lastActivity = DateTime.now();
  }

  void markFinal(int index) {
    _finalSeen = true;
    _finalIndex = index;
  }

  // Process a binary chunk (new method for binary protocol)
  Future<void> processBinary(int index, Uint8List bytes) async {
    resetWatchdog();

    if (index == nextIndex) {
      // This is the expected chunk, write it immediately
      await sink.writeFrom(bytes);
      receivedBytes += bytes.length;
      nextIndex++;

      // Write any buffered chunks that are now in sequence
      while (_chunkBuffer.containsKey(nextIndex)) {
        final bufferedBytes = _chunkBuffer.remove(nextIndex)!;
        await sink.writeFrom(bufferedBytes);
        receivedBytes += bufferedBytes.length;
        nextIndex++;
      }
      debugPrint(
        '[ConnectionService] ✅ Processed binary chunk $index, next expected: $nextIndex, buffered: ${_chunkBuffer.length}',
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

    if (chunk.index == nextIndex) {
      // This is the expected chunk, write it immediately
      await sink.writeFrom(bytes);
      receivedBytes += bytes.length;
      nextIndex++;

      // Write any buffered chunks that are now in sequence
      while (_chunkBuffer.containsKey(nextIndex)) {
        final bufferedBytes = _chunkBuffer.remove(nextIndex)!;
        await sink.writeFrom(bufferedBytes);
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
    await sink.flush();
    await sink.close();
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
      if (available < 5) return; // need [len(4)] + [type(1)]

      final payloadLen = _readInt32(_buf, _start);
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

        // Attempt to resynchronize to the next plausible frame boundary.
        final resynced = _tryResync();
        if (!resynced) {
          debugPrint(
            '[FrameParser] ⚠️ Invalid payloadLen=$payloadLen, dropping buffer',
          );
          reset();
          return;
        }
        continue;
      }

      final frameLen = 4 + payloadLen;
      if (available < frameLen) return; // wait for more

      final type = _buf[_start + 4];
      final payloadStart = _start + 5;
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
        } else {
          debugPrint('[FrameParser] ⚠️ Unknown frame type=$type, skipping');
        }
      } catch (e) {
        debugPrint('[FrameParser] ❌ Frame parse error: $e');
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

  bool _tryResync() {
    final available = _end - _start;
    if (available < 6) return false;

    // Scan forward for a plausible header: [len:int32][type:0|1]
    // We require len within bounds and enough bytes for at least header.
    for (int i = _start + 1; i <= _end - 5; i++) {
      final len = _readInt32(_buf, i);
      if (len <= 0 || len > ConnectionService._maxFramePayloadBytes) continue;
      final type = _buf[i + 4];
      if (type != 0 && type != 1) continue;
      _start = i;
      return true;
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
    final bytes = payload.sublist(offset);

    debugPrint(
      '[FrameParser] 📥 Binary chunk: transferId=$transferId, index=$index, isLast=$isLast, bytes=${bytes.length}',
    );

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
        newBuf.setRange(0, remaining, _buf, _start);
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
