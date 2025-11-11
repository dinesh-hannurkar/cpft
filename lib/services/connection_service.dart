import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/connection_state.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import '../models/file_transfer.dart';
import 'package:path_provider/path_provider.dart';

/// Service for managing device-to-device connections
class ConnectionService {
  final String deviceName;
  Socket? _socket;
  ConnectionInfo? _currentConnection;
  final List<Function(DeviceMessage)> _messageListeners = [];
  final List<Function(ConnectionInfo)> _statusListeners = [];
  StreamSubscription? _socketSubscription;
  final StringBuffer _messageBuffer = StringBuffer();
  Timer? _keepAliveTimer;
  // Track incoming file transfers
  final Map<String, _IncomingFile> _incomingFiles = {};
  // Pending offers awaiting user decision
  final Map<String, FileOffer> _pendingOffers = {};
  // Backpressure: track outgoing transfers waiting for ACKs
  final Map<String, _OutgoingTransfer> _outgoingTransfers = {};

  ConnectionService({required this.deviceName});

  /// Get current connection info
  ConnectionInfo? get currentConnection => _currentConnection;

  /// Check if connected
  bool get isConnected => _currentConnection?.status == ConnectionStatus.connected;

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
    print('[ConnectionService] 🔌 Connecting to $deviceName at $ipAddress:$port');

    // If already connected, disconnect first
    if (_socket != null) {
      print('[ConnectionService] Disconnecting from previous connection');
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

      print('[ConnectionService] ✅ Socket connected successfully');

      // Configure socket options to keep connection alive
      _socket!.setOption(SocketOption.tcpNoDelay, true);

      // Set up socket listener
      _socketSubscription = _socket!.listen(
        _handleIncomingData,
        onError: (error) {
          print('[ConnectionService] ❌ Socket error: $error');
          _handleConnectionError(error.toString());
        },
        onDone: () {
          print('[ConnectionService] 🔌 Socket closed by remote');
          disconnect();
        },
        cancelOnError: false,
      );

  // Do NOT send anything yet. Wait for remote acceptance handshake.
  print('[ConnectionService] ⏳ Waiting for acceptance from $deviceName');
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
      
      print('[ConnectionService] ❌ Connection failed: $e');
      print('[ConnectionService] 💡 User message: $userFriendlyError');
      
      _updateStatus(ConnectionInfo(
        deviceName: deviceName,
        ipAddress: ipAddress,
        port: port,
        status: ConnectionStatus.failed,
        error: userFriendlyError,
      ));
      return false;
    } catch (e) {
      print('[ConnectionService] ❌ Connection failed: $e');
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
    print('[ConnectionService] 📞 Accepting incoming connection from $deviceName');
    print('[ConnectionService] 🔍 Socket info: ${socket.remoteAddress.address}:${socket.remotePort}');

    // If already connected, disconnect first and wait for stream to be released
    if (_socket != null) {
      print('[ConnectionService] ⚠️  Already have a socket, disconnecting...');
      await disconnect();
      // Wait a bit for the stream to be fully released
      await Future.delayed(const Duration(milliseconds: 100));
      print('[ConnectionService] ✅ Previous connection cleaned up');
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
        print('[ConnectionService] ✅ Socket options configured');
      } catch (e) {
        print('[ConnectionService] ⚠️  Failed to set socket options: $e');
      }

      // Set up socket listener directly (no broadcast stream)
      print('[ConnectionService] 🎧 Setting up socket listener...');
      try {
        _socketSubscription = _socket!.listen(
          _handleIncomingData,
          onError: (error) {
            print('[ConnectionService] ❌ Socket error: $error');
            _handleConnectionError(error.toString());
          },
          onDone: () {
            print('[ConnectionService] 🔌 Socket closed by remote');
            disconnect();
          },
          cancelOnError: false,
        );
        print('[ConnectionService] ✅ Socket listener attached successfully');
      } catch (e) {
        print('[ConnectionService] ❌ Failed to attach socket listener: $e');
        throw Exception('Failed to listen to socket: $e');
      }

      // Send handshake response
      print('[ConnectionService] 📤 Sending handshake response...');
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

      print('[ConnectionService] ✅ Accepted connection from $deviceName');
      return true;
    } catch (e) {
      print('[ConnectionService] ❌ Failed to accept connection: $e');
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
      print('[ConnectionService] ❌ No active connection');
      return false;
    }

    try {
      final json = jsonEncode(message.toJson());
      final data = '$json\n'; // Add newline as delimiter
      final bytes = utf8.encode(data);
      _socket!.add(bytes);
      await _socket!.flush();
      print('[ConnectionService] 📤 Sent message: ${message.type}');
      return true;
    } catch (e) {
      print('[ConnectionService] ❌ Failed to send message: $e');
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
          print('[ConnectionService] 📥 Received message: ${message.type} from ${message.senderName}');
          
          // Handle handshake messages
          if (message.type == 'handshake') {
            final wasConnected = isConnected;
            if (!wasConnected && _currentConnection != null && _currentConnection!.status == ConnectionStatus.connecting) {
              // Transition to connected upon first handshake from peer
              print('[ConnectionService] 🤝 Acceptance received from ${message.senderName}. Marking as connected.');
              _updateStatus(_currentConnection!.copyWith(
                status: ConnectionStatus.connected,
                connectedAt: DateTime.now(),
              ));
              // Start keep-alive now that session is accepted
              _startKeepAlive();
              // Send our handshake response (now that we know the peer accepted)
              await _sendHandshake();
            } else {
              print('[ConnectionService] 🤝 Received handshake (already connected), ignoring');
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
                    },
                  ));
                } else {
                  // Release next chunk permit
                  outgoing.chunkPermit?.complete();
                }
              }
            } catch (e) {
              print('[ConnectionService] ⚠️ Failed to parse file_ack: $e');
            }
            continue;
          }
          
          // Handle file transfer control & data
      if (message.type == 'file_offer') {
            try {
        final offer = FileOffer.fromJson((message.metadata?['payload'] as Map?)?.cast<String, dynamic>() ?? {});
              // Defer accepting until UI approves; store pending
              _pendingOffers[offer.transferId] = offer;
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
              print('[ConnectionService] ⚠️ Failed to parse file_offer: $e');
            }
            continue;
          }

      if (message.type == 'file_chunk') {
            try {
        final chunk = FileChunk.fromJson((message.metadata?['payload'] as Map?)?.cast<String, dynamic>() ?? {});
              final incoming = _incomingFiles[chunk.transferId];
              if (incoming == null) {
                print('[ConnectionService] ⚠️ No state for transfer ${chunk.transferId}');
              } else {
                if (chunk.index != incoming.nextIndex) {
                  print('[ConnectionService] ⚠️ Unexpected chunk index ${chunk.index} expected ${incoming.nextIndex}');
                }
                final bytes = base64Decode(chunk.dataBase64);
                await incoming.sink.writeFrom(bytes);
                incoming.receivedBytes += bytes.length;
                incoming.nextIndex = chunk.index + 1;
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
                  await incoming.sink.flush();
                  await incoming.sink.close();
                  // Hash verify
                  if (incoming.offer.sha256 != null) {
                    final fb = await File(incoming.path).readAsBytes();
                    final calc = sha256.convert(fb).toString();
                    if (calc != incoming.offer.sha256) {
                      print('[ConnectionService] ❌ Hash mismatch for ${incoming.offer.fileName}');
                      _notifyMessageListeners(DeviceMessage(
                        type: 'text',
                        content: 'Integrity failed: ${incoming.offer.fileName}',
                        senderName: deviceName,
                        timestamp: DateTime.now(),
                      ));
                    } else {
                      print('[ConnectionService] ✅ Hash verified for ${incoming.offer.fileName}');
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
                      'received': incoming.receivedBytes,
                    },
                  ));
                  _incomingFiles.remove(chunk.transferId);
                }
              }
              final ack = FileAck(transferId: chunk.transferId, nextExpectedIndex: chunk.index + 1, completed: chunk.isLast);
              await sendMessage(DeviceMessage(type: 'file_ack', content: jsonEncode(ack.toJson()), senderName: deviceName));
            } catch (e) {
              print('[ConnectionService] ⚠️ Failed to parse file_chunk: $e');
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
              print('[ConnectionService] ⚠️ Failed to parse file_cancel: $e');
            }
            continue;
          }
          
          // Handle ping/pong messages for keep-alive (don't notify listeners)
          if (message.type == 'ping') {
            print('[ConnectionService] 🏓 Received ping, sending pong');
            final pong = DeviceMessage(
              type: 'pong',
              content: 'keep-alive',
              senderName: deviceName,
            );
            sendMessage(pong);
          } else if (message.type == 'pong') {
            print('[ConnectionService] 🏓 Received pong (connection alive)');
          } else {
            // Normal message - notify listeners
            _notifyMessageListeners(message);
          }
        } catch (e) {
          print('[ConnectionService] ⚠️  Failed to parse message: $e');
        }
      }
    } catch (e) {
      print('[ConnectionService] ❌ Error handling incoming data: $e');
    }
  }

  /// Public API: Pick and send a file (basic MVP)
  Future<void> pickAndSendFile() async {
    if (!isConnected || _socket == null) {
      print('[ConnectionService] ⚠️ Not connected; cannot send file');
      return;
    }
    final result = await FilePicker.platform.pickFiles(withReadStream: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
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
  await sendMessage(DeviceMessage(type: 'file_offer', content: '', senderName: deviceName, metadata: {'payload': offer.toJson()}));

    // Stream chunks
    const chunkSize = 64 * 1024; // 64KB per chunk
    int index = 0;
    final stream = file.readStream;
    if (stream == null) return;

    // Register outgoing transfer
    _outgoingTransfers[transferId] = _OutgoingTransfer(
      fileName: name,
      lastAckIndex: -1,
      totalSize: size,
    );
    
    // Show "Sending..." message immediately
    _notifyMessageListeners(DeviceMessage(
      type: 'text',
      content: 'Sending: $name (${_formatFileSize(size)})',
      senderName: deviceName,
      timestamp: DateTime.now(),
    ));
    
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
        if (ot == null) return; // Cancelled
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

  /// Accept a pending incoming file offer, prepares file path/sink and signals sender to start
  Future<void> acceptFileOffer(String transferId, {String? saveDir}) async {
    final offer = _pendingOffers.remove(transferId);
    if (offer == null) {
      print('[ConnectionService] No pending offer for $transferId');
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

  /// Handle connection error
  void _handleConnectionError(String error) {
    if (_currentConnection != null) {
      _updateStatus(_currentConnection!.copyWith(
        status: ConnectionStatus.failed,
        error: error,
      ));
    }
  }

  /// Update connection status
  void _updateStatus(ConnectionInfo info) {
    _currentConnection = info;
    _notifyStatusListeners(info);
  }

  /// Notify message listeners
  void _notifyMessageListeners(DeviceMessage message) {
    for (final listener in _messageListeners) {
      try {
        listener(message);
      } catch (e) {
        print('[ConnectionService] ❌ Error notifying message listener: $e');
      }
    }
  }

  /// Notify status listeners
  void _notifyStatusListeners(ConnectionInfo info) {
    for (final listener in _statusListeners) {
      try {
        listener(info);
      } catch (e) {
        print('[ConnectionService] ❌ Error notifying status listener: $e');
      }
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    print('[ConnectionService] 🔌 Disconnecting...');

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
        print('[ConnectionService] ⚠️  Could not send goodbye message: $e');
      }
    }

    // Cancel socket subscription
    await _socketSubscription?.cancel();
    _socketSubscription = null;

    // Stop keep-alive timer
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;

    // Close socket
    try {
      await _socket?.close();
    } catch (e) {
      print('[ConnectionService] ⚠️  Error closing socket: $e');
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

    print('[ConnectionService] ✅ Disconnected');
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
            print('[ConnectionService] ⚠️  Keep-alive ping failed');
          }
        });
      }
    });
  }

  /// Dispose the service
  Future<void> dispose() async {
    await disconnect();
    _messageListeners.clear();
    _statusListeners.clear();
  }
  
  String _formatFileSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
  }
}

class _IncomingFile {
  final FileOffer offer;
  final String path;
  final RandomAccessFile sink;
  int receivedBytes;
  int nextIndex;

  _IncomingFile({
    required this.offer,
    required this.path,
    required this.sink,
    required this.receivedBytes,
    required this.nextIndex,
  });
}

class _OutgoingTransfer {
  final String fileName;
  int lastAckIndex; // last index confirmed by receiver
  final int totalSize; // total bytes
  final Map<int, int> chunkSizes = {}; // index -> bytes
  int sentBytes = 0; // bytes confirmed by ACKs
  Completer<void>? chunkPermit; // completed when next chunk may be sent
  Completer<void>? completer; // completed when transfer fully done

  _OutgoingTransfer({required this.fileName, required this.lastAckIndex, required this.totalSize});
}
