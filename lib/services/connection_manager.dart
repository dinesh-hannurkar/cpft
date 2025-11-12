import 'dart:async';
import 'dart:io';

import 'connection_service.dart';
import 'background_service.dart';
import '../models/connection_state.dart';

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
    
    // Listen for connection status changes to manage foreground service
    service.addStatusListener((info) {
      if (info.status == ConnectionStatus.connected) {
        print('[ConnectionManager] Connection to ${info.deviceName} is now connected');
        _startForegroundServiceIfNeeded();
      } else if (info.status == ConnectionStatus.disconnected || info.status == ConnectionStatus.failed) {
        print('[ConnectionManager] Connection to ${info.deviceName} disconnected/failed');
        // Remove from active connections and stop service if needed
        _activeConnections.remove(deviceName);
        _stopForegroundServiceIfNeeded();
      }
      // Update notification whenever status changes
      if (info.status == ConnectionStatus.connected) {
        _updateForegroundServiceNotification();
      }
    });
    
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
        
        // Start foreground service on Android when first connection established
        await _startForegroundServiceIfNeeded();
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

  /// Start foreground service if this is the first connection
  Future<void> _startForegroundServiceIfNeeded() async {
    if (!Platform.isAndroid) return;
    
    if (_activeConnections.length == 1 && !BackgroundService.isRunning) {
      print('[ConnectionManager] Starting foreground service (first connection)');
      try {
        final started = await BackgroundService.start();
        if (started) {
          print('[ConnectionManager] ✅ Foreground service started');
          _updateForegroundServiceNotification();
        }
      } catch (e) {
        print('[ConnectionManager] ❌ Failed to start foreground service: $e');
      }
    } else if (_activeConnections.isNotEmpty) {
      // Update notification with current connections
      _updateForegroundServiceNotification();
    }
  }

  /// Stop foreground service if no connections remain
  Future<void> _stopForegroundServiceIfNeeded() async {
    if (!Platform.isAndroid) return;
    
    if (_activeConnections.isEmpty && BackgroundService.isRunning) {
      print('[ConnectionManager] Stopping foreground service (no connections)');
      try {
        await BackgroundService.stop();
        print('[ConnectionManager] ✅ Foreground service stopped');
      } catch (e) {
        print('[ConnectionManager] ❌ Failed to stop foreground service: $e');
      }
    }
  }

  /// Update foreground service notification with connection info
  void _updateForegroundServiceNotification() {
    if (!Platform.isAndroid || !BackgroundService.isRunning) return;
    
    final count = _activeConnections.length;
    final deviceNames = _activeConnections.keys.take(3).join(', ');
    
    String notificationText;
    if (count == 1) {
      notificationText = 'Connected to $deviceNames';
    } else if (count <= 3) {
      notificationText = 'Connected to $deviceNames';
    } else {
      notificationText = 'Connected to $count devices';
    }
    
    BackgroundService.updateNotification(
      title: 'CPFT Active',
      text: notificationText,
    );
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
      
      // Stop foreground service if no connections remain
      _stopForegroundServiceIfNeeded();
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
    
    // Stop foreground service when all connections closed
    await _stopForegroundServiceIfNeeded();
  }
}
