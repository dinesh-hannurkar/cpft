import 'dart:async';
import 'dart:io';

import 'connection_service.dart';

/// Manages all active P2P connections (both incoming and outgoing)
class ConnectionManager {
  late final String deviceName;
  final Map<String, ConnectionService> _activeConnections = {};
  final List<Function(String deviceName, ConnectionService service, bool isIncoming)> _connectionListeners = [];

  ConnectionManager();

  /// Initialize with device name
  void initialize(String deviceName) {
    this.deviceName = deviceName;
    print('[ConnectionManager] Initialized with device name: $deviceName');
  }

  /// Get or create a connection service for a device
  ConnectionService getOrCreateConnection(String deviceName) {
    if (_activeConnections.containsKey(deviceName)) {
      print('[ConnectionManager] Returning existing connection to $deviceName');
      return _activeConnections[deviceName]!;
    }

    print('[ConnectionManager] Creating new connection service for $deviceName');
    final service = ConnectionService(deviceName: this.deviceName);
    _activeConnections[deviceName] = service;
    return service;
  }

  /// Handle incoming connection (socket-only, legacy path)
  Future<void> handleIncomingConnection(Socket socket, String remoteName) async {
    try {
      print('[ConnectionManager] 📞 Handling incoming connection from $remoteName');
      print('[ConnectionManager] 🔍 Socket details - Address: ${socket.remoteAddress.address}, Port: ${socket.remotePort}');

      // Check if we already have a connection to this device
      final existingService = _activeConnections[remoteName];
      if (existingService != null) {
        // Check if existing connection is active/connected
        if (existingService.isConnected) {
          print('[ConnectionManager] ⚠️  Already connected to $remoteName, rejecting duplicate incoming connection');
          // Close the duplicate incoming socket
          try {
            socket.close();
          } catch (_) {}
          return;
        } else {
          // Existing connection is not active, remove it
          print('[ConnectionManager] 🗑️  Removing stale (not connected) existing connection to $remoteName');
          _activeConnections.remove(remoteName);
          try {
            // Ensure we fully clean up the old service to release any socket/subscriptions
            await existingService.disconnect();
            await existingService.dispose();
            print('[ConnectionManager] ✅ Stale connection to $remoteName fully disposed');
          } catch (e) {
            print('[ConnectionManager] ⚠️  Error disposing stale connection to $remoteName: $e');
          }
        }
      }

      // Create new connection service for this device
      print('[ConnectionManager] Creating new connection service for $remoteName');
      final service = ConnectionService(deviceName: this.deviceName);
      _activeConnections[remoteName] = service;
      print('[ConnectionManager] 🔍 Got ConnectionService for $remoteName');

      // Accept the connection using the provided socket
      print('[ConnectionManager] 🔄 Calling acceptConnection...');
      final success = await service.acceptConnection(socket, remoteName);

      if (success) {
        print('[ConnectionManager] ✅ Incoming connection from $remoteName accepted');
  _notifyConnectionListeners(remoteName, service, isIncoming: true);
      } else {
        print('[ConnectionManager] ❌ Failed to accept connection from $remoteName');
        _activeConnections.remove(remoteName);
      }
    } catch (e, stackTrace) {
      print('[ConnectionManager] ❌ Exception handling incoming connection: $e');
      print('[ConnectionManager] Stack trace: $stackTrace');
      _activeConnections.remove(remoteName);
      
      // Don't let the exception propagate - just close the socket
      try {
        socket.close();
      } catch (_) {}
    }
  }

  /// Add listener for new connections
  void addConnectionListener(Function(String deviceName, ConnectionService service, bool isIncoming) listener) {
    _connectionListeners.add(listener);
  }

  /// Remove connection listener
  void removeConnectionListener(Function(String, ConnectionService, bool) listener) {
    _connectionListeners.remove(listener);
  }

  /// Notify listeners about new connection
  void _notifyConnectionListeners(String deviceName, ConnectionService service, {required bool isIncoming}) {
    for (final listener in _connectionListeners) {
      try {
        listener(deviceName, service, isIncoming);
      } catch (e) {
        print('[ConnectionManager] Error notifying listener: $e');
      }
    }
  }

  /// Get active connection to a device (if any)
  ConnectionService? getConnection(String deviceName) {
    return _activeConnections[deviceName];
  }

  /// Remove a connection
  void removeConnection(String deviceName) {
    final service = _activeConnections.remove(deviceName);
    if (service != null) {
      print('[ConnectionManager] Removed connection to $deviceName');
      service.dispose();
    }
  }

  /// Get all active connections
  Map<String, ConnectionService> get activeConnections => Map.unmodifiable(_activeConnections);

  /// Close all connections
  Future<void> closeAll() async {
    print('[ConnectionManager] Closing all connections');
    for (final service in _activeConnections.values) {
      await service.disconnect();
      service.dispose();
    }
    _activeConnections.clear();
  }
}
