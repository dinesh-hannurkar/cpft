import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';

import 'connection_service.dart';
import 'package:cpft/services/background_service.dart';
import 'package:cpft/services/notification_service.dart';
import '../models/connection_state.dart';

/// Manages all active P2P connections (both incoming and outgoing)
class ConnectionManager {
  String? deviceName;
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
    debugPrint('[ConnectionManager] 📊 Active connections count: ${_activeConnections.length}, devices: ${_activeConnections.keys.join(", ")}');
    
    // Notify listeners about the new connection being created
    _notifyConnectionListeners(deviceName, service, isIncoming: false);
    
    // Listen for connection status changes to manage foreground service
    service.addStatusListener((info) {
      if (info.status == ConnectionStatus.connected) {
        debugPrint('[ConnectionManager] Connection to ${info.deviceName} is now connected');
        _startForegroundServiceIfNeeded();
        NotificationService().showNotification(
          type: NotificationType.connectionEstablished,
          title: 'Connected',
          body: 'Successfully connected to ${info.deviceName}',
        );
      } else if (info.status == ConnectionStatus.failed) {
        // Only remove failed connections immediately. Disconnected connections are retained
        // so the UI (bottom sheet) can still show them and allow manual reconnection attempts.
        debugPrint('[ConnectionManager] Connection to ${info.deviceName} failed – removing');
        _activeConnections.remove(deviceName);
        _stopForegroundServiceIfNeeded();
        NotificationService().showNotification(
          type: NotificationType.connectionLost,
          title: 'Connection Failed',
          body: 'Connection to ${info.deviceName} failed',
        );
      } else if (info.status == ConnectionStatus.disconnected) {
        // Keep the service so UI can show a "Disconnected" state.
        debugPrint('[ConnectionManager] Connection to ${info.deviceName} disconnected (retaining for UI)');
        _stopForegroundServiceIfNeeded();
        NotificationService().showNotification(
          type: NotificationType.connectionLost,
          title: 'Disconnected',
          body: 'Connection to ${info.deviceName} disconnected',
        );
      }

      // Update notification whenever status changes and we have at least one connected device
      if (info.status == ConnectionStatus.connected) {
        _updateForegroundServiceNotification();
      } else {
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
    deviceName = null; // Clear for restart capability
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
      
      // Attach status listener for incoming connections (same as outgoing)
      service.addStatusListener((info) {
        if (info.status == ConnectionStatus.connected) {
          debugPrint('[ConnectionManager] Connection to ${info.deviceName} is now connected');
          _startForegroundServiceIfNeeded();
          NotificationService().showNotification(
            type: NotificationType.connectionEstablished,
            title: 'Connected',
            body: 'Successfully connected to ${info.deviceName}',
          );
        } else if (info.status == ConnectionStatus.failed) {
          debugPrint('[ConnectionManager] Connection to ${info.deviceName} failed – removing');
          _activeConnections.remove(remoteName);
          _stopForegroundServiceIfNeeded();
          NotificationService().showNotification(
            type: NotificationType.connectionLost,
            title: 'Connection Failed',
            body: 'Connection to ${info.deviceName} failed',
          );
        } else if (info.status == ConnectionStatus.disconnected) {
          debugPrint('[ConnectionManager] Connection to ${info.deviceName} disconnected (retaining for UI)');
          _stopForegroundServiceIfNeeded();
          NotificationService().showNotification(
            type: NotificationType.connectionLost,
            title: 'Disconnected',
            body: 'Connection to ${info.deviceName} disconnected',
          );
        }

        // Update notification whenever status changes
        if (info.status == ConnectionStatus.connected) {
          _updateForegroundServiceNotification();
        } else {
          _updateForegroundServiceNotification();
        }
      });
      
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
    final connectedCount = _activeConnections.values.where((s) => s.isConnected).length;
    if (connectedCount == 1 && !BackgroundService.isRunning) {
      debugPrint('[ConnectionManager] Starting foreground service (first connected device)');
      try {
        final started = await BackgroundService.start();
        if (started) {
          debugPrint('[ConnectionManager] ✅ Foreground service started');
          _updateForegroundServiceNotification();
        }
      } catch (e) {
        debugPrint('[ConnectionManager] ❌ Failed to start foreground service: $e');
      }
    } else if (connectedCount > 0) {
      _updateForegroundServiceNotification();
    }
  }

  /// Stop foreground service if no connections remain
  Future<void> _stopForegroundServiceIfNeeded() async {
    if (!Platform.isAndroid) return;
    final connectedCount = _activeConnections.values.where((s) => s.isConnected).length;
    if (connectedCount == 0 && BackgroundService.isRunning) {
      debugPrint('[ConnectionManager] Stopping foreground service (no connected devices)');
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
    
    final connectedEntries = _activeConnections.entries.where((e) => e.value.isConnected).toList();
    final count = connectedEntries.length;
    final deviceNames = connectedEntries.map((e) => e.key).take(3).join(', ');
    
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
    debugPrint('[ConnectionManager] 🔔 Notifying ${_connectionListeners.length} listeners about ${isIncoming ? "incoming" : "outgoing"} connection to $deviceName');
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
