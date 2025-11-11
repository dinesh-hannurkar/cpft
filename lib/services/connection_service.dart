import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/connection_state.dart';

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

      // Set up socket listener
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

  /// Accept an incoming connection using a provided broadcast stream
  Future<bool> acceptConnectionWithStream(
    Socket socket,
    Stream<List<int>> broadcastStream,
    String deviceName,
  ) async {
    print('[ConnectionService] 📞 Accepting incoming connection (with stream) from $deviceName');
    print('[ConnectionService] 🔍 Socket info: ${socket.remoteAddress.address}:${socket.remotePort}');

    // If already connected, disconnect first and wait for stream to be released
    if (_socket != null) {
      print('[ConnectionService] ⚠️  Already have a socket, disconnecting...');
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 100));
      print('[ConnectionService] ✅ Previous connection cleaned up');
    }

    try {
      _socket = socket; // Keep reference for send/close
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

      // Attach to provided broadcast stream instead of re-listening to socket
      print('[ConnectionService] 🎧 Attaching to provided broadcast stream...');
      try {
        _socketSubscription = broadcastStream.listen(
          _handleIncomingData,
          onError: (error) {
            print('[ConnectionService] ❌ Stream error: $error');
            _handleConnectionError(error.toString());
          },
          onDone: () {
            print('[ConnectionService] 🔌 Stream closed by remote');
            disconnect();
          },
          cancelOnError: false,
        );
        print('[ConnectionService] ✅ Broadcast stream listener attached successfully');
      } catch (e) {
        print('[ConnectionService] ❌ Failed to attach to broadcast stream: $e');
        throw Exception('Failed to listen to provided stream: $e');
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

      print('[ConnectionService] ✅ Accepted connection (with stream) from $deviceName');
      return true;
    } catch (e) {
      print('[ConnectionService] ❌ Failed to accept connection (with stream): $e');
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
      _socket!.write(data);
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
}
