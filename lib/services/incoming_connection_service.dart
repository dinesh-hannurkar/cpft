import 'dart:async';
import 'dart:io';

/// Service for accepting incoming connections from other devices
class IncomingConnectionService {
  final int port;
  final String deviceName;
  ServerSocket? _serverSocket;
  // Listeners now receive the accepted Socket plus a broadcast stream of its data and the remote device name
  final List<Function(Socket, Stream<List<int>>, String)> _connectionListeners = [];
  bool _isListening = false;

  IncomingConnectionService({
    required this.port,
    required this.deviceName,
  });

  /// Check if service is listening
  bool get isListening => _isListening;

  /// Add connection listener
  void addConnectionListener(Function(Socket, Stream<List<int>>, String) listener) {
    _connectionListeners.add(listener);
  }

  /// Remove connection listener
  void removeConnectionListener(Function(Socket, Stream<List<int>>, String) listener) {
    _connectionListeners.remove(listener);
  }

  /// Start listening for incoming connections
  Future<void> startListening() async {
    if (_isListening) {
      print('[IncomingConnection] Already listening');
      return;
    }

    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );

      _isListening = true;
      print('[IncomingConnection] ✅ Listening for incoming connections on port $port');

      _serverSocket!.listen(
        _handleIncomingConnection,
        onError: (error) {
          print('[IncomingConnection] ❌ Server error: $error');
        },
        onDone: () {
          print('[IncomingConnection] Server socket closed');
          _isListening = false;
        },
      );
    } catch (e) {
      print('[IncomingConnection] ❌ Failed to start listening: $e');
      rethrow;
    }
  }

  /// Handle incoming connection (no initial data required)
  void _handleIncomingConnection(Socket socket) {
    final remoteAddress = socket.remoteAddress.address;
    print('[IncomingConnection] 📞 Incoming connection from $remoteAddress');

    // Immediately convert to broadcast and notify listeners (UI will accept/decline)
    final broadcast = socket.asBroadcastStream();
    print('[IncomingConnection] 🎯 Notifying listeners with socket & broadcast (no handshake expected)');
    _notifyListeners(socket, broadcast, remoteAddress);
  }

  /// Notify listeners about new connection
  void _notifyListeners(Socket socket, Stream<List<int>> broadcastStream, String remoteName) {
    for (final listener in _connectionListeners) {
      try {
        listener(socket, broadcastStream, remoteName);
      } catch (e) {
        print('[IncomingConnection] ❌ Error notifying listener: $e');
      }
    }
  }

  /// Stop listening for connections
  Future<void> stopListening() async {
    if (!_isListening) {
      print('[IncomingConnection] Not listening');
      return;
    }

    try {
      await _serverSocket?.close();
      _serverSocket = null;
      _isListening = false;
      print('[IncomingConnection] ✅ Stopped listening');
    } catch (e) {
      print('[IncomingConnection] ⚠️  Error stopping: $e');
    }
  }

  /// Dispose the service
  Future<void> dispose() async {
    await stopListening();
    _connectionListeners.clear();
  }
}
