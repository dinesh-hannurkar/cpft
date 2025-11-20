import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';

import 'notification_service.dart';

/// Service for accepting incoming connections from other devices
class IncomingConnectionService {
  final int port;
  final String deviceName;
  ServerSocket? _serverSocket;
  // Listeners receive the accepted Socket and the remote device name
  final List<Function(Socket, String)> _connectionListeners = [];
  bool _isListening = false;

  IncomingConnectionService({
    required this.port,
    required this.deviceName,
  });

  /// Check if service is listening
  bool get isListening => _isListening;

  /// Add connection listener
  void addConnectionListener(Function(Socket, String) listener) {
    _connectionListeners.add(listener);
  }

  /// Remove connection listener
  void removeConnectionListener(Function(Socket, String) listener) {
    _connectionListeners.remove(listener);
  }

  /// Start listening for incoming connections
  Future<void> startListening() async {
    if (_isListening) {
      debugPrint('[IncomingConnection] Already listening on port $port');
      return;
    }

    debugPrint('[IncomingConnection] Attempting to bind to port $port...');
    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );

      _isListening = true;
      debugPrint('[IncomingConnection] ✅ Successfully bound to port $port');

      _serverSocket!.listen(
        _handleIncomingConnection,
        onError: (error) {
          debugPrint('[IncomingConnection] ❌ Server error: $error');
        },
        onDone: () {
          debugPrint('[IncomingConnection] Server socket closed');
          _isListening = false;
        },
      );
    } catch (e) {
      debugPrint('[IncomingConnection] ❌ Failed to start listening: $e');
      rethrow;
    }
  }

  /// Handle incoming connection (no initial data required)
  void _handleIncomingConnection(Socket socket) {
    final remoteAddress = socket.remoteAddress.address;
    debugPrint('[IncomingConnection] 📞 Incoming connection from $remoteAddress');

    // Don't convert to broadcast - just pass the socket directly
    // The ConnectionService will attach its own listener
    debugPrint('[IncomingConnection] 🎯 Notifying listeners with socket (no broadcast needed)');
    _notifyListeners(socket, remoteAddress);

    // Show notification for incoming connection
    NotificationService().showNotification(
      type: NotificationType.incomingConnectionRequest,
      title: 'Incoming Connection',
      body: 'Connection request from $remoteAddress',
    );
  }

  /// Notify listeners about new connection
  void _notifyListeners(Socket socket, String remoteName) {
    for (final listener in _connectionListeners) {
      try {
        listener(socket, remoteName);
      } catch (e) {
        debugPrint('[IncomingConnection] ❌ Error notifying listener: $e');
      }
    }
  }

  /// Stop listening for incoming connections
  Future<void> stopListening() async {
    if (!_isListening) {
      debugPrint('[IncomingConnection] Not listening');
      return;
    }

    debugPrint('[IncomingConnection] Stopping listening on port $port...');
    try {
      await _serverSocket?.close();
      _serverSocket = null;
      _isListening = false;
      debugPrint('[IncomingConnection] ✅ Successfully closed socket on port $port');
    } catch (e) {
      debugPrint('[IncomingConnection] ⚠️  Error stopping: $e');
    }
  }

  /// Dispose the service
  Future<void> dispose() async {
    await stopListening();
    _connectionListeners.clear();
  }
}
