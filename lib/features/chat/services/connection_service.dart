import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';

import '../models/connection_state.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cpft/models/file_transfer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cpft/services/notification_service.dart';

/// Service for managing device-to-device connections
class ConnectionService {
  final String deviceName;
  Socket? _socket;
  ConnectionInfo? _currentConnection;
  final List<Function(DeviceMessage)> _messageListeners = [];
  final List<Function(ConnectionInfo)> _statusListeners = [];
  // Persist message history so reopening a chat screen shows prior conversation.
  final List<DeviceMessage> _messageHistory = [];
  StreamSubscription? _socketSubscription;
  final StringBuffer _messageBuffer = StringBuffer();
  Timer? _keepAliveTimer;
  // Track consecutive socket errors to avoid premature disconnection
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  Timer? _errorResetTimer;
  // Track incoming file transfers
  final Map<String, _IncomingFile> _incomingFiles = {};
  // Pending offers awaiting user decision
  final Map<String, FileOffer> _pendingOffers = {};
  // Backpressure: track outgoing transfers waiting for ACKs
  final Map<String, _OutgoingTransfer> _outgoingTransfers = {};

  ConnectionService({required this.deviceName}) {
    debugPrint('[ConnectionService] 🆕 NEW ConnectionService instance created for device: $deviceName ($hashCode)');
  }

  /// Get current connection info
  ConnectionInfo? get currentConnection => _currentConnection;

  /// Check if connected
  bool get isConnected => _currentConnection?.status == ConnectionStatus.connected;

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
    debugPrint('[ConnectionService] 🔌 Connecting to $deviceName at $ipAddress:$port');

    // Prevent duplicate connection attempts
    if (currentConnection?.status == ConnectionStatus.connecting) {
      debugPrint('[ConnectionService] ⚠️ Already connecting to ${currentConnection?.deviceName}, ignoring duplicate connect()');
      return false;
    }
    if (currentConnection?.status == ConnectionStatus.connected) {
      debugPrint('[ConnectionService] ⚠️ Already connected to ${currentConnection?.deviceName}, ignoring duplicate connect()');
      return true;
    }

    // If socket exists from previous connection, disconnect first
    if (_socket != null) {
      debugPrint('[ConnectionService] Disconnecting from previous connection');
      await disconnect();
    }

    _updateStatus(ConnectionInfo(
      deviceName: deviceName,
      ipAddress: ipAddress,
      port: port,
      status: ConnectionStatus.connecting,
    ));

    try {
      // Attempt to connect with timeout
      _socket = await Socket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 10),
      );

      debugPrint('[ConnectionService] ✅ Socket connected successfully');

      // Configure socket options to keep connection alive
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

  // Do NOT send anything yet. Wait for remote acceptance handshake.
  debugPrint('[ConnectionService] ⏳ Waiting for acceptance from $deviceName');
  return true; // TCP is up; logical connection will switch to connected on handshake
    } on SocketException catch (e) {
      String userFriendlyError;
      if (e.osError?.errorCode == 61 || e.message.contains('Connection refused')) {
        userFriendlyError = 'The other device is not ready to accept connections.\n\n'
            'Please make sure:\n'
            '1. The app is running on the other device\n'
            '2. The app has been restarted recently (to apply updates)\n'
            '3. Both devices are on the same WiFi network';
      } else if (e.osError?.errorCode == 60 || e.message.contains('timed out')) {
        userFriendlyError = 'Connection timed out.\n\n'
            'Please check:\n'
            '1. The device is still on the network\n'
            '2. No firewall is blocking port 53318';
      } else {
        userFriendlyError = 'Network error: ${e.message}';
      }
      
      debugPrint('[ConnectionService] ❌ Connection failed: $e');
      debugPrint('[ConnectionService] 💡 User message: $userFriendlyError');
      
      _updateStatus(ConnectionInfo(
        deviceName: deviceName,
        ipAddress: ipAddress,
        port: port,
        status: ConnectionStatus.failed,
        error: userFriendlyError,
      ));
      return false;
    } catch (e) {
      debugPrint('[ConnectionService] ❌ Connection failed: $e');
      _updateStatus(ConnectionInfo(
        deviceName: deviceName,
        ipAddress: ipAddress,
        port: port,
        status: ConnectionStatus.failed,
        error: e.toString(),
      ));
      return false;
    }
  }

  /// Accept an incoming connection (for server-side connections)
  Future<bool> acceptConnection(Socket socket, String deviceName) async {
    debugPrint('[ConnectionService] 📞 Accepting incoming connection from $deviceName');
    debugPrint('[ConnectionService] 🔍 Socket info: ${socket.remoteAddress.address}:${socket.remotePort}');

    // If already connected, disconnect first and wait for stream to be released
    if (_socket != null) {
      debugPrint('[ConnectionService] ⚠️  Already have a socket, disconnecting...');
      await disconnect();
      // Wait a bit for the stream to be fully released
      await Future.delayed(const Duration(milliseconds: 100));
      debugPrint('[ConnectionService] ✅ Previous connection cleaned up');
    }

    try {
      _socket = socket;
      final ipAddress = socket.remoteAddress.address;
      final port = socket.remotePort;

      _updateStatus(ConnectionInfo(
        deviceName: deviceName,
        ipAddress: ipAddress,
        port: port,
        status: ConnectionStatus.connecting,
      ));

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
        debugPrint('[ConnectionService] ✅ Socket listener attached successfully');
      } catch (e) {
        debugPrint('[ConnectionService] ❌ Failed to attach socket listener: $e');
        throw Exception('Failed to listen to socket: $e');
      }

      // Send handshake response
      debugPrint('[ConnectionService] 📤 Sending handshake response...');
      await _sendHandshake();

      // Start keep-alive timer
      _startKeepAlive();

      // Update connection status
      _updateStatus(ConnectionInfo(
        deviceName: deviceName,
        ipAddress: ipAddress,
        port: port,
        status: ConnectionStatus.connected,
        connectedAt: DateTime.now(),
      ));

      debugPrint('[ConnectionService] ✅ Accepted connection from $deviceName');
      return true;
    } catch (e) {
      debugPrint('[ConnectionService] ❌ Failed to accept connection: $e');
      _updateStatus(ConnectionInfo(
        deviceName: deviceName,
        ipAddress: socket.remoteAddress.address,
        port: socket.remotePort,
        status: ConnectionStatus.failed,
        error: e.toString(),
      ));
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
      final data = '$json\n'; // Add newline as delimiter
      final bytes = utf8.encode(data);
      _socket!.add(bytes);
      await _socket!.flush();
      debugPrint('[ConnectionService] 📤 Sent message: ${message.type} to $deviceName');

      // Add outgoing message to history (not via listener to avoid duplicate notification)
      const historyTypes = {'text', 'file_complete', 'file_offer', 'goodbye'};
      if (historyTypes.contains(message.type)) {
        _messageHistory.add(message);
      }

      // Reset error count on successful send
      if (_consecutiveErrors > 0) {
        debugPrint('[ConnectionService] ✅ Message sent successfully, resetting error count');
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
    // Reset error count on successful data reception
    if (_consecutiveErrors > 0) {
      debugPrint('[ConnectionService] ✅ Connection recovered, resetting error count');
      _consecutiveErrors = 0;
      _errorResetTimer?.cancel();
    }

    try {
      final text = utf8.decode(data);
      _messageBuffer.write(text);

      // Process complete messages (delimited by newline)
      String bufferContent = _messageBuffer.toString();
      final messages = bufferContent.split('\n');

      // Keep the last incomplete message in buffer
      _messageBuffer.clear();
      if (!bufferContent.endsWith('\n')) {
        _messageBuffer.write(messages.last);
        messages.removeLast();
      }

      // Process complete messages
      for (final messageText in messages) {
        if (messageText.trim().isEmpty) continue;

        try {
          final json = jsonDecode(messageText) as Map<String, dynamic>;
          final message = DeviceMessage.fromJson(json);
          debugPrint('[ConnectionService] 📥 Received message: ${message.type} from ${message.senderName}');

          // Handle explicit reject messages (new): remote declined connection before handshake
          if (message.type == 'reject') {
            debugPrint('[ConnectionService] ❌ Connection explicitly rejected by ${message.senderName}');
            if (_currentConnection != null && _currentConnection!.status == ConnectionStatus.connecting) {
              _updateStatus(_currentConnection!.copyWith(
                status: ConnectionStatus.failed,
                error: 'Connection rejected by remote device',
              ));
            }
            // Close socket proactively
            await disconnect();
            continue;
          }
          
          // Handle handshake messages
          if (message.type == 'handshake') {
            final wasConnected = isConnected;
            if (!wasConnected && _currentConnection != null && _currentConnection!.status == ConnectionStatus.connecting) {
              // Transition to connected upon first handshake from peer
              debugPrint('[ConnectionService] 🤝 Acceptance received from ${message.senderName}. Marking as connected.');
              _updateStatus(_currentConnection!.copyWith(
                status: ConnectionStatus.connected,
                connectedAt: DateTime.now(),
              ));
              // Start keep-alive now that session is accepted
              _startKeepAlive();
              // Send our handshake response (now that we know the peer accepted)
              await _sendHandshake();
            } else {
              debugPrint('[ConnectionService] 🤝 Received handshake (already connected), ignoring');
            }
            continue;
          }
          // Handle file_ack for backpressure
          if (message.type == 'file_ack') {
            try {
              final ack = FileAck.fromJson(jsonDecode(message.content));
              final outgoing = _outgoingTransfers[ack.transferId];
              if (outgoing != null) {
                // Advance pointer
                final oldIndex = outgoing.lastAckIndex;
                final newIndex = ack.nextExpectedIndex - 1;
                // Accumulate bytes for acknowledged chunks
                for (int i = oldIndex + 1; i <= newIndex; i++) {
                  outgoing.sentBytes += outgoing.chunkSizes[i] ?? 0;
                }
                outgoing.lastAckIndex = newIndex;
                // Emit progress for UI
                _notifyMessageListeners(DeviceMessage(
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
                ));
                // Complete if finished
                if (ack.completed) {
                  outgoing.completer?.complete();
                  _outgoingTransfers.remove(ack.transferId);
                  _notifyMessageListeners(DeviceMessage(
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
                  ));

                  // Show notification for completed file transfer
                  NotificationService().showNotification(
                    type: NotificationType.fileTransferCompleted,
                    title: 'File Sent',
                    body: 'Successfully sent ${outgoing.fileName}',
                  );
                } else {
                  // Release next chunk permit
                  outgoing.chunkPermit?.complete();
                }
              }
            } catch (e) {
              debugPrint('[ConnectionService] ⚠️ Failed to parse file_ack: $e');
            }
            continue;
          }
          
          // Handle file transfer control & data
      if (message.type == 'file_offer') {
            try {
        final offer = FileOffer.fromJson((message.metadata?['payload'] as Map?)?.cast<String, dynamic>() ?? {});
              // Defer accepting until UI approves; store pending
              _pendingOffers[offer.transferId] = offer;
              
              // Show notification for incoming file offer
              // Use this.deviceName for both display and connection lookup
              // since it's the consistent identifier for this peer
              NotificationService().showFileTransferNotification(
                senderDisplayName: deviceName, // Use peer's device name
                fileName: offer.fileName,
                fileSize: offer.fileSize,
                transferId: offer.transferId,
                deviceName: deviceName, // Connection lookup name
              );
              
              _notifyMessageListeners(DeviceMessage(
                type: 'file_offer',
                content: offer.fileName,
                senderName: message.senderName,
                timestamp: DateTime.now(),
                metadata: {
                  'transferId': offer.transferId,
                  'size': offer.fileSize,
                  'mime': offer.mimeType,
                },
              ));
            } catch (e) {
              debugPrint('[ConnectionService] ⚠️ Failed to parse file_offer: $e');
            }
            continue;
          }

          // Handle resume request: receiver should resend last ACK
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
                await sendMessage(DeviceMessage(
                  type: 'file_ack',
                  content: jsonEncode(ack.toJson()),
                  senderName: deviceName,
                ));
                debugPrint('[ConnectionService] 🔁 Resume-request: resent ACK for $transferId at ${inc.nextIndex}');
              } else {
                debugPrint('[ConnectionService] ⚠️ Resume-request: no incoming state for $transferId');
              }
            } catch (e) {
              debugPrint('[ConnectionService] ⚠️ Failed to handle resume request: $e');
            }
            continue;
          }

      if (message.type == 'file_chunk') {
            try {
        final chunk = FileChunk.fromJson((message.metadata?['payload'] as Map?)?.cast<String, dynamic>() ?? {});
              final incoming = _incomingFiles[chunk.transferId];
              if (incoming == null) {
                debugPrint('[ConnectionService] ⚠️ No state for transfer ${chunk.transferId}');
              } else {
                await incoming.processChunk(chunk);

                // Emit progress update for UI
                _notifyMessageListeners(DeviceMessage(
                  type: 'file_progress',
                  content: incoming.offer.fileName,
                  senderName: message.senderName,
                  timestamp: DateTime.now(),
                  metadata: {
                    'transferId': chunk.transferId,
                    'bytes': incoming.receivedBytes,
                    'total': incoming.offer.fileSize,
                    'outgoing': false,
                  },
                ));
                if (chunk.isLast) {
                  debugPrint('[ConnectionService] 📍 Final chunk received for transfer ${chunk.transferId}, waiting for all chunks...');

                  // Wait longer to ensure all buffered chunks are processed
                  // With parallel channels, chunks can arrive significantly out of order
                  await Future.delayed(const Duration(seconds: 10));

                  // Check if all chunks have been received and processed
                  if (!incoming.isComplete()) {
                    debugPrint('[ConnectionService] ⚠️ Final chunk received but transfer ${chunk.transferId} is not complete. Buffered chunks remaining: ${incoming._chunkBuffer.length}');
                    debugPrint('[ConnectionService] 📊 Buffer contents: ${incoming._chunkBuffer.keys.toList()}');
                    // Don't complete yet, wait for more chunks
                    continue;
                  }

                  debugPrint('[ConnectionService] ✅ All chunks received and processed for transfer ${chunk.transferId}');
                  await incoming.sink.flush();
                  await incoming.sink.close();
                  // Hash verify
                  if (incoming.offer.sha256 != null) {
                    final fb = await File(incoming.path).readAsBytes();
                    final calc = sha256.convert(fb).toString();
                    if (calc != incoming.offer.sha256) {
                      debugPrint('[ConnectionService] ❌ Hash mismatch for ${incoming.offer.fileName}');
                      _notifyMessageListeners(DeviceMessage(
                        type: 'text',
                        content: 'Integrity failed: ${incoming.offer.fileName}',
                        senderName: deviceName,
                        timestamp: DateTime.now(),
                      ));
                    } else {
                      debugPrint('[ConnectionService] ✅ Hash verified for ${incoming.offer.fileName}');
                      _notifyMessageListeners(DeviceMessage(
                        type: 'text',
                        content: 'File verified: ${incoming.offer.fileName}',
                        senderName: deviceName,
                        timestamp: DateTime.now(),
                      ));
                    }
                  }
                  _notifyMessageListeners(DeviceMessage(
                    type: 'file_complete',
                    content: incoming.offer.fileName,
                    senderName: message.senderName,
                    timestamp: DateTime.now(),
                    metadata: {
          'transferId': chunk.transferId,
                      'path': incoming.path,
                      'size': incoming.offer.fileSize,
                      'mime': incoming.offer.mimeType,
                      'received': incoming.receivedBytes,
                    },
                  ));
                  _incomingFiles.remove(chunk.transferId);

                  // Show notification for completed file transfer
                  NotificationService().showNotification(
                    type: NotificationType.fileTransferCompleted,
                    title: 'File Received',
                    body: 'Successfully received ${incoming.offer.fileName}',
                  );

                  // Send final completion ack
                  final completionAck = FileAck(transferId: chunk.transferId, nextExpectedIndex: chunk.index + 1, completed: true);
                  await sendMessage(DeviceMessage(type: 'file_ack', content: jsonEncode(completionAck.toJson()), senderName: deviceName));
                }
              }
              // Send ack for this chunk (never completed here - completion ack sent after processing)
              final ack = FileAck(transferId: chunk.transferId, nextExpectedIndex: chunk.index + 1, completed: false);
              await sendMessage(DeviceMessage(type: 'file_ack', content: jsonEncode(ack.toJson()), senderName: deviceName));
            } catch (e) {
              debugPrint('[ConnectionService] ⚠️ Failed to parse file_chunk: $e');
            }
            continue;
          }
          if (message.type == 'file_cancel') {
            try {
              final cancel = FileCancel.fromJson(jsonDecode(message.content));
              // Close & remove incoming/outgoing state
              final inc = _incomingFiles.remove(cancel.transferId);
              if (inc != null) {
                await inc.sink.close();
              }
        // Also clear pending offers
        _pendingOffers.remove(cancel.transferId);
              _outgoingTransfers.remove(cancel.transferId);
              _notifyMessageListeners(DeviceMessage(
                type: 'text',
                content: 'Transfer cancelled: ${cancel.reason}',
                senderName: message.senderName,
                timestamp: DateTime.now(),
              ));
            } catch (e) {
              debugPrint('[ConnectionService] ⚠️ Failed to parse file_cancel: $e');
            }
            continue;
          }
          
          // Handle ping/pong messages for keep-alive (don't notify listeners)
          if (message.type == 'ping') {
            debugPrint('[ConnectionService] 🏓 Received ping, sending pong');
            final pong = DeviceMessage(
              type: 'pong',
              content: 'keep-alive',
              senderName: deviceName,
            );
            sendMessage(pong);
          } else if (message.type == 'pong') {
            debugPrint('[ConnectionService] 🏓 Received pong (connection alive)');
          } else {
            // Normal message - notify listeners
            _notifyMessageListeners(message);

            // Show notification for text messages
            if (message.type == 'text') {
              NotificationService().showNotification(
                type: NotificationType.messageReceived,
                title: 'New Message',
                body: '${message.senderName}: ${message.content}',
              );
            }
          }
        } catch (e) {
          debugPrint('[ConnectionService] ⚠️  Failed to parse message: $e');
        }
      }
    } catch (e) {
      debugPrint('[ConnectionService] ❌ Error handling incoming data: $e');
    }
  }

  /// Public API: Pick and send a file (basic MVP)
  Future<void> pickAndSendFile() async {
    if (!isConnected || _socket == null) {
      debugPrint('[ConnectionService] ⚠️ Not connected; cannot send file');
      return;
    }
    final result = await FilePicker.platform.pickFiles(withReadStream: true, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    for (final file in result.files) {
      final name = file.name;
      final size = file.size;
      final mime = file.extension != null ? 'application/${file.extension}' : 'application/octet-stream';
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
      await sendMessage(DeviceMessage(
        type: 'file_offer',
        content: name, // provide filename directly for dialog display
        senderName: deviceName,
        metadata: {
          'payload': offer.toJson(),
          'name': name,
        },
      ));

      // Stream chunks
      const chunkSize = 64 * 1024; // 64KB per chunk
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
      
      // Show "Sending..." message immediately
      // _notifyMessageListeners(DeviceMessage(
      //   type: 'text',
      //   content: 'Sending: $name (${_formatFileSize(size)})',
      //   senderName: deviceName,
      //   timestamp: DateTime.now(),
      // ));
      
      // Emit initial progress event to render UI tile
      _notifyMessageListeners(DeviceMessage(
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
      ));

      // Wait for initial ACK (nextExpectedIndex = 0) which is sent after receiver accepts
      final starter = _outgoingTransfers[transferId];
      if (starter != null) {
        starter.chunkPermit = Completer<void>();
        await starter.chunkPermit!.future;
      }

      await for (final data in stream) {
        int offset = 0;
        while (offset < data.length) {
          final end = (offset + chunkSize).clamp(0, data.length);
          final slice = data.sublist(offset, end);
          // Wait for permit if previous chunk not acked
          final ot = _outgoingTransfers[transferId];
          if (ot == null) break; // Cancelled
          if (ot.lastAckIndex != index - 1) {
            ot.chunkPermit = Completer<void>();
            await ot.chunkPermit!.future;
          }
          // Record chunk size for accurate progress
          ot.chunkSizes[index] = slice.length;
          final chunk = FileChunk(
            transferId: transferId,
            index: index++,
            dataBase64: base64Encode(slice),
            isLast: false,
          );
          await sendMessage(DeviceMessage(type: 'file_chunk', content: '', senderName: deviceName, metadata: {'payload': chunk.toJson()}));
          offset = end;
        }
      }
      // Final marker
      final otFinal = _outgoingTransfers[transferId];
      if (otFinal != null) {
        if (otFinal.lastAckIndex != index - 1) {
          otFinal.chunkPermit = Completer<void>();
          await otFinal.chunkPermit!.future;
        }
        final finalChunk = FileChunk(
          transferId: transferId,
          index: index,
          dataBase64: base64Encode(Uint8List(0)),
          isLast: true,
        );
        otFinal.completer = Completer<void>();
        await sendMessage(DeviceMessage(type: 'file_chunk', content: '', senderName: deviceName, metadata: {'payload': finalChunk.toJson()}));
        await otFinal.completer!.future; // Wait for final ack
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
    _notifyMessageListeners(DeviceMessage(
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
    ));
    // Send initial ack to let sender start
    final ack = FileAck(transferId: offer.transferId, nextExpectedIndex: 0, completed: false);
    await sendMessage(DeviceMessage(type: 'file_ack', content: jsonEncode(ack.toJson()), senderName: deviceName));
  }

  /// Decline a pending incoming file offer
  Future<void> declineFileOffer(String transferId, {String reason = 'Declined by receiver'}) async {
    final offer = _pendingOffers.remove(transferId);
    if (offer == null) return;
    final cancel = FileCancel(transferId: transferId, reason: reason);
    await sendMessage(DeviceMessage(type: 'file_cancel', content: jsonEncode(cancel.toJson()), senderName: deviceName));
  }

  Future<void> cancelTransfer(String transferId, {String reason = 'Cancelled by user'}) async {
    // Notify remote
    final cancel = FileCancel(transferId: transferId, reason: reason);
    await sendMessage(DeviceMessage(type: 'file_cancel', content: jsonEncode(cancel.toJson()), senderName: deviceName));
    // Clean local state
    final inc = _incomingFiles.remove(transferId);
    if (inc != null) {
      try { await inc.sink.close(); } catch (_) {}
    }
  _pendingOffers.remove(transferId);
    _outgoingTransfers.remove(transferId);
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
        debugPrint('[ConnectionService] No incoming state to resume for $transferId');
        return;
      }
      final ack = FileAck(
        transferId: transferId,
        nextExpectedIndex: inc.nextIndex,
        completed: false,
      );
      await sendMessage(DeviceMessage(
        type: 'file_ack',
        content: jsonEncode(ack.toJson()),
        senderName: deviceName,
      ));
      debugPrint('[ConnectionService] 🔁 Resent ACK for $transferId at index ${inc.nextIndex}');
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️ Failed to resume incoming: $e');
    }
  }

  /// Handle connection error
  void _handleConnectionError(String error) {
    _consecutiveErrors++;
    debugPrint('[ConnectionService] ⚠️ Socket error #$_consecutiveErrors: $error');

    // Reset error count after 10 seconds of no errors
    _errorResetTimer?.cancel();
    _errorResetTimer = Timer(const Duration(seconds: 10), () {
      if (_consecutiveErrors > 0) {
        debugPrint('[ConnectionService] 🔄 Resetting error count after timeout');
        _consecutiveErrors = 0;
      }
    });

    // Only mark as disconnected after multiple consecutive errors (not failed)
    // This prevents removal from activeConnections, allowing UI to show disconnected state
    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      debugPrint('[ConnectionService] ❌ Too many consecutive errors, marking connection as disconnected (not failed)');
      if (_currentConnection != null) {
        _updateStatus(_currentConnection!.copyWith(
          status: ConnectionStatus.disconnected,
          error: 'Connection lost: $error',
        ));
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
    // Persist only user-relevant messages to history to avoid duplicate technical entries.
    const historyTypes = {
      'text',
      'file_complete',
      // 'file_offer' removed - offers are prompts, not chat messages
      'goodbye',
      // add future types here (e.g. 'reaction')
    };
    if (historyTypes.contains(message.type)) {
      // Avoid consecutive duplicates for file_complete with same name
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
        debugPrint('[ConnectionService] ❌ Error notifying message listener: $e');
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
    debugPrint('[ConnectionService] 🔌 DISCONNECT CALLED for ${_currentConnection?.deviceName ?? "unknown"}');
    debugPrint('[ConnectionService] 🔌 Current status: ${_currentConnection?.status}, socket: ${_socket != null}, timer: ${_keepAliveTimer != null}');

    // Send goodbye message if connected
    if (_socket != null && _currentConnection?.status == ConnectionStatus.connected) {
      try {
        final goodbye = DeviceMessage(
          type: 'goodbye',
          content: 'Disconnecting',
          senderName: deviceName,
        );
        await sendMessage(goodbye);
      } catch (e) {
        debugPrint('[ConnectionService] ⚠️  Could not send goodbye message: $e');
      }
    }

    // Cancel socket subscription
    await _socketSubscription?.cancel();
    _socketSubscription = null;

    // Stop keep-alive timer
    debugPrint('[ConnectionService] 🛑 Cancelling keep-alive timer (was ${_keepAliveTimer != null ? "active" : "null"})');
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    debugPrint('[ConnectionService] 🛑 Keep-alive timer cancelled and nullified');

    // Close socket
    try {
      await _socket?.close();
    } catch (e) {
      debugPrint('[ConnectionService] ⚠️  Error closing socket: $e');
    }
    _socket = null;

    // Clear message buffer
    _messageBuffer.clear();

    // Update status
    if (_currentConnection != null) {
      _updateStatus(_currentConnection!.copyWith(
        status: ConnectionStatus.disconnected,
      ));
    }

    debugPrint('[ConnectionService] ✅ Disconnected');
  }

  /// Start keep-alive timer to prevent connection timeout
  void _startKeepAlive() {
    debugPrint('[ConnectionService] 🔄 Starting keep-alive timer (cancelling old one first if exists)');
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      debugPrint('[ConnectionService] ⏰ Keep-alive timer fired: socket=${_socket != null}, isConnected=$isConnected');
      if (_socket != null && isConnected) {
        final ping = DeviceMessage(
          type: 'ping',
          content: 'keep-alive',
          senderName: deviceName,
        );
        debugPrint('[ConnectionService] 📤 Sending keep-alive ping to ${_currentConnection?.deviceName ?? "unknown"}');
        sendMessage(ping).then((success) {
          if (!success) {
            debugPrint('[ConnectionService] ⚠️  Keep-alive ping failed');
          } else {
            debugPrint('[ConnectionService] ✅ Keep-alive ping sent successfully');
          }
        });
      } else {
        debugPrint('[ConnectionService] ⏸️  Keep-alive timer fired but NOT sending (socket=${_socket != null}, isConnected=$isConnected)');
      }
    });
    debugPrint('[ConnectionService] 🔄 Keep-alive timer started successfully');
  }

  /// Dispose the service
  Future<void> dispose() async {
    debugPrint('[ConnectionService] 🗑️  DISPOSE called for ${_currentConnection?.deviceName ?? deviceName} ($hashCode)');
    await disconnect();
    _errorResetTimer?.cancel();
    _messageListeners.clear();
    _statusListeners.clear();
    debugPrint('[ConnectionService] 🗑️  DISPOSE completed for ${_currentConnection?.deviceName ?? deviceName} ($hashCode)');
  }
  
  // removed unused _formatFileSize helper
}

class _IncomingFile {
  final FileOffer offer;
  final String path;
  final RandomAccessFile sink;
  int receivedBytes;
  int nextIndex;
  final Map<int, Uint8List> _chunkBuffer = {}; // Buffer for out-of-order chunks

  _IncomingFile({
    required this.offer,
    required this.path,
    required this.sink,
    required this.receivedBytes,
    required this.nextIndex,
  });

  // Process a chunk, handling out-of-order arrival
  Future<void> processChunk(FileChunk chunk) async {
    final bytes = base64Decode(chunk.dataBase64);

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
      debugPrint('[ConnectionService] ✅ Processed chunk ${chunk.index}, next expected: $nextIndex, buffered: ${_chunkBuffer.length}');
    } else if (chunk.index > nextIndex) {
      // Future chunk, buffer it
      _chunkBuffer[chunk.index] = bytes;
      debugPrint('[ConnectionService] 📦 Buffered chunk ${chunk.index} for transfer (expecting $nextIndex), buffer size: ${_chunkBuffer.length}');
    } else {
      // Duplicate or past chunk, ignore
      debugPrint('[ConnectionService] ⚠️ Ignoring duplicate/past chunk ${chunk.index} (expecting $nextIndex)');
    }
  }

  // Check if transfer is complete (all chunks received up to the final marker)
  bool isComplete() {
    return _chunkBuffer.isEmpty; // All chunks should be written when buffer is empty
  }
}

class _OutgoingTransfer {
  final String fileName;
  int lastAckIndex; // last index confirmed by receiver
  final int totalSize; // total bytes
  final Map<int, int> chunkSizes = {}; // index -> bytes
  int sentBytes = 0; // bytes confirmed by ACKs
  Completer<void>? chunkPermit; // completed when next chunk may be sent
  Completer<void>? completer; // completed when transfer fully done

  // Optional metadata for better UI on sender side
  final String? mime;
  final String? path;

  _OutgoingTransfer({
    required this.fileName,
    required this.lastAckIndex,
    required this.totalSize,
    this.mime,
    this.path,
  });
}
