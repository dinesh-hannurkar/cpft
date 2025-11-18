import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';

import 'connection_service.dart';
import 'package:cpft/services/background_service.dart';
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
    debugPrint('[ConnectionManager] Initialized with device name: $deviceName');
  }

  /// Get or create a connection service for a device
  ConnectionService getOrCreateConnection(String deviceName) {
    if (_activeConnections.containsKey(deviceName)) {
      debugPrint('[ConnectionManager] Returning existing connection to $deviceName');
      return _activeConnections[deviceName]!;
    }

  debugPrint('[ConnectionManager] Creating new connection service for $deviceName');
  // FIX: Use the remote device's name, not local deviceName, for proper identity in handshake
  final service = ConnectionService(deviceName: deviceName);
    _activeConnections[deviceName] = service;
    
    // Listen for connection status changes to manage foreground service
    service.addStatusListener((info) {
      if (info.status == ConnectionStatus.connected) {
        debugPrint('[ConnectionManager] Connection to ${info.deviceName} is now connected');
        _startForegroundServiceIfNeeded();
      } else if (info.status == ConnectionStatus.disconnected || info.status == ConnectionStatus.failed) {
        debugPrint('[ConnectionManager] Connection to ${info.deviceName} disconnected/failed');
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

  /// Dispose all active connections (called when tearing down discovery)
  Future<void> dispose() async {
    for (final entry in _activeConnections.entries) {
      try {
        await entry.value.disconnect();
        await entry.value.dispose();
      } catch (_) {}
    }
    _activeConnections.clear();
    _connectionListeners.clear();
  }

  /// Handle incoming connection (socket-only, legacy path)
  Future<void> handleIncomingConnection(Socket socket, String remoteName) async {
    try {
      debugPrint('[ConnectionManager] 📞 Handling incoming connection from $remoteName');
      debugPrint('[ConnectionManager] 🔍 Socket details - Address: ${socket.remoteAddress.address}, Port: ${socket.remotePort}');

      // Check if we already have a connection to this device
      final existingService = _activeConnections[remoteName];
      if (existingService != null) {
        // Check if existing connection is active/connected
        if (existingService.isConnected) {
          debugPrint('[ConnectionManager] ⚠️  Already connected to $remoteName, rejecting duplicate incoming connection');
          // Close the duplicate incoming socket
          try {
            socket.close();
          } catch (_) {}
          return;
        } else {
          // Existing connection is not active, remove it
          debugPrint('[ConnectionManager] 🗑️  Removing stale (not connected) existing connection to $remoteName');
          _activeConnections.remove(remoteName);
          try {
            // Ensure we fully clean up the old service to release any socket/subscriptions
            await existingService.disconnect();
            await existingService.dispose();
            debugPrint('[ConnectionManager] ✅ Stale connection to $remoteName fully disposed');
          } catch (e) {
            debugPrint('[ConnectionManager] ⚠️  Error disposing stale connection to $remoteName: $e');
          }
        }
      }

  // Create new connection service for the REMOTE device.
  // BUG FIX: Previously passed `this.deviceName` (local device name), causing
  // the ConnectionService to think it was connected to itself. This broke
  // handshakes and led to premature socket closes after declines.
  debugPrint('[ConnectionManager] Creating new connection service for remote device $remoteName');
  final service = ConnectionService(deviceName: remoteName);
      _activeConnections[remoteName] = service;
      debugPrint('[ConnectionManager] 🔍 Got ConnectionService for $remoteName');

      // Accept the connection using the provided socket
      debugPrint('[ConnectionManager] 🔄 Calling acceptConnection...');
      final success = await service.acceptConnection(socket, remoteName);

      if (success) {
        debugPrint('[ConnectionManager] ✅ Incoming connection from $remoteName accepted');
        _notifyConnectionListeners(remoteName, service, isIncoming: true);
        
        // Start foreground service on Android when first connection established
        await _startForegroundServiceIfNeeded();
      } else {
        debugPrint('[ConnectionManager] ❌ Failed to accept connection from $remoteName');
        _activeConnections.remove(remoteName);
      }
    } catch (e, stackTrace) {
      debugPrint('[ConnectionManager] ❌ Exception handling incoming connection: $e');
      debugPrint('[ConnectionManager] Stack trace: $stackTrace');
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
      debugPrint('[ConnectionManager] Starting foreground service (first connection)');
      try {
        final started = await BackgroundService.start();
        if (started) {
          debugPrint('[ConnectionManager] ✅ Foreground service started');
          _updateForegroundServiceNotification();
        }
      } catch (e) {
        debugPrint('[ConnectionManager] ❌ Failed to start foreground service: $e');
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
      debugPrint('[ConnectionManager] Stopping foreground service (no connections)');
      try {
        await BackgroundService.stop();
        debugPrint('[ConnectionManager] ✅ Foreground service stopped');
      } catch (e) {
        debugPrint('[ConnectionManager] ❌ Failed to stop foreground service: $e');
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
        debugPrint('[ConnectionManager] Error notifying listener: $e');
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
      debugPrint('[ConnectionManager] Removed connection to $deviceName');
      service.dispose();
      
      // Stop foreground service if no connections remain
      _stopForegroundServiceIfNeeded();
    }
  }

  /// Get all active connections
  Map<String, ConnectionService> get activeConnections => Map.unmodifiable(_activeConnections);

  /// Close all connections
  Future<void> closeAll() async {
    debugPrint('[ConnectionManager] Closing all connections');
    for (final service in _activeConnections.values) {
      await service.disconnect();
      service.dispose();
    }
    _activeConnections.clear();
    
    // Stop foreground service when all connections closed
    await _stopForegroundServiceIfNeeded();
  }
}
