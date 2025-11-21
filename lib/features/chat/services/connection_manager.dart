import 'dart:async';
// Removed unused flutter/foundation import after replacing debugPrint with AppLogger
import 'package:cpft/core/logging/app_logger.dart';
import 'dart:io';

import 'connection_service.dart';
import 'package:cpft/services/background_service.dart';
import 'package:cpft/services/notification_service.dart';
import 'package:cpft/utils/connection_logger.dart';
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
    AppLogger.d('Initialized with device name: $deviceName', tag: 'ConnMgr');
  }

  /// Get or create a connection service for a device
  ConnectionService getOrCreateConnection(String deviceName) {
    if (_activeConnections.containsKey(deviceName)) {
      AppLogger.d('Returning existing connection to $deviceName', tag: 'ConnMgr');
      return _activeConnections[deviceName]!;
    }

  AppLogger.d('Creating new connection service for $deviceName', tag: 'ConnMgr');
  // FIX: Use the remote device's name, not local deviceName, for proper identity in handshake
  final service = ConnectionService(deviceName: deviceName);
    _activeConnections[deviceName] = service;
    AppLogger.d('Active connections: ${_activeConnections.length} -> ${_activeConnections.keys.join(", ")}', tag: 'ConnMgr');
    ConnectionLogger.instance.log('Created connection to $deviceName. Total: ${_activeConnections.length}');
    
    // Notify listeners about the new connection being created
    _notifyConnectionListeners(deviceName, service, isIncoming: false);
    
    // Listen for connection status changes to manage foreground service
    service.addStatusListener((info) {
      if (info.status == ConnectionStatus.connected) {
        AppLogger.i('Connection to ${info.deviceName} is now connected', tag: 'ConnMgr');
        ConnectionLogger.instance.log('✅ CONNECTED to ${info.deviceName}. Active: ${_activeConnections.keys.join(", ")}');
        _startForegroundServiceIfNeeded();
        NotificationService().showNotification(
          type: NotificationType.connectionEstablished,
          title: 'Connected',
          body: 'Successfully connected to ${info.deviceName}',
        );
      } else if (info.status == ConnectionStatus.failed) {
        // ONLY remove failed connections. NEVER remove disconnected connections.
        // Disconnected connections must be retained so the UI can show them and allow reconnection.
        AppLogger.w('Connection to ${info.deviceName} failed – REMOVING', tag: 'ConnMgr');
        _activeConnections.remove(deviceName);
        AppLogger.d('Active after removal: ${_activeConnections.length} -> ${_activeConnections.keys.join(", ")}', tag: 'ConnMgr');
        ConnectionLogger.instance.log('❌ FAILED connection to ${info.deviceName} REMOVED. Remaining: ${_activeConnections.keys.join(", ")}');
        _stopForegroundServiceIfNeeded();
        NotificationService().showNotification(
          type: NotificationType.connectionLost,
          title: 'Connection Failed',
          body: 'Connection to ${info.deviceName} failed',
        );
      } else if (info.status == ConnectionStatus.disconnected) {
        // Remove disconnected connections so user can reconnect fresh from radar
        AppLogger.d('Disconnected from ${info.deviceName} - removing for fresh reconnect', tag: 'ConnMgr');
        _activeConnections.remove(deviceName);
        AppLogger.d('Active after disconnect: ${_activeConnections.length} -> ${_activeConnections.keys.join(", ")}', tag: 'ConnMgr');
        ConnectionLogger.instance.log('⚠️  DISCONNECTED from ${info.deviceName} - REMOVED. Remaining: ${_activeConnections.keys.join(", ")}');
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
    AppLogger.d('dispose() called – PRESERVING ${_activeConnections.length} connections', tag: 'ConnMgr');
    // Instead of clearing, mark all as disconnected but retain for UI/history
    for (final entry in _activeConnections.entries) {
      try {
        await entry.value.disconnect();
        // Do NOT call entry.value.dispose(); we keep listeners/state for potential reuse
      } catch (e) {
        AppLogger.w('dispose() error disconnecting ${entry.key}: $e', tag: 'ConnMgr', error: e);
      }
    }
    // Do not clear maps; only clear listeners to avoid memory leaks
    _connectionListeners.clear();
    // Keep deviceName so reinitialization can reuse it; if we must reset, set via initialize()
    ConnectionLogger.instance.log('ConnectionManager.dispose invoked – connections retained (${_activeConnections.keys.join(", ")})');
  }

  /// Handle incoming connection (socket-only, legacy path)
  Future<void> handleIncomingConnection(Socket socket, String remoteName) async {
    try {
      final ip = socket.remoteAddress.address;
      AppLogger.d('Incoming connection from $remoteName (IP: $ip)', tag: 'ConnMgr');
      AppLogger.v('Socket details: ${socket.remoteAddress.address}:${socket.remotePort}', tag: 'ConnMgr');

      // IMPORTANT: remoteName might be IP address or display name from discovery
      // We need to check all existing connections to see if we're already connected to this IP
      ConnectionService? existingServiceByIp;
      String? existingKeyByIp;
      
      for (final entry in _activeConnections.entries) {
        final connInfo = entry.value.currentConnection;
        if (connInfo != null && connInfo.ipAddress == ip) {
          existingServiceByIp = entry.value;
          existingKeyByIp = entry.key;
          AppLogger.d('Found existing connection to IP $ip under key: $existingKeyByIp', tag: 'ConnMgr');
          break;
        }
      }

      // Check if we already have a connection to this device (by name OR IP)
      final foundService = _activeConnections[remoteName] ?? existingServiceByIp;
      final foundKey = foundService != null ? (existingKeyByIp ?? remoteName) : null;
      
      if (foundService != null && foundKey != null) {
        final status = foundService.currentConnection?.status;
        
        AppLogger.d('Connection to $foundKey already exists (status: $status)', tag: 'ConnMgr');
        
        // If already connected or connecting, handle the duplicate
        if (status == ConnectionStatus.connected || status == ConnectionStatus.connecting) {
          
          if (status == ConnectionStatus.connected) {
            // Already fully connected - notify UI to navigate
            AppLogger.d('Notify listeners to navigate to existing chat with $foundKey', tag: 'ConnMgr');
            _notifyConnectionListeners(foundKey, foundService, isIncoming: true);
            // Close the duplicate incoming socket
            try {
              socket.close();
            } catch (_) {}
            return;
          } else if (status == ConnectionStatus.connecting) {
            // Connection in progress - use "alphabetical order" tie-breaker
            // Lower device name accepts incoming, higher device name keeps outgoing
            final shouldAcceptIncoming = foundKey.compareTo(deviceName ?? '') < 0;
            
            if (shouldAcceptIncoming) {
              AppLogger.d('Tie-breaker: accepting incoming (remote: $foundKey < local: $deviceName)', tag: 'ConnMgr');
              AppLogger.v('Reusing existing service; replacing socket', tag: 'ConnMgr');
              
              // Don't dispose the service! Just accept the incoming socket into the existing service
              // This prevents creating a new service and avoids the connection loop
              final success = await foundService.acceptConnection(socket, foundKey);
              if (success) {
                AppLogger.i('Incoming connection accepted into existing service ($foundKey)', tag: 'ConnMgr');
                _notifyConnectionListeners(foundKey, foundService, isIncoming: true);
              } else {
                AppLogger.w('Failed to accept incoming connection into existing service ($foundKey)', tag: 'ConnMgr');
              }
              return;
            } else {
              AppLogger.d('Tie-breaker: keeping outgoing (local: $deviceName < remote: $foundKey)', tag: 'ConnMgr');
              // Keep the outgoing connection, reject this incoming one
              try {
                socket.close();
              } catch (_) {}
              return;
            }
          }
        } else {
          // Existing connection is not active (disconnected or failed)
          // Only remove and replace if it's failed. Keep disconnected for UI.
          if (status == ConnectionStatus.failed) {
            AppLogger.w('Removing stale failed existing connection to $foundKey', tag: 'ConnMgr');
            _activeConnections.remove(foundKey);
            try {
              await foundService.disconnect();
              await foundService.dispose();
              AppLogger.d('Failed connection to $foundKey fully disposed', tag: 'ConnMgr');
            } catch (e) {
              AppLogger.w('Error disposing failed connection to $foundKey: $e', tag: 'ConnMgr', error: e);
            }
            // Continue to create new connection
            remoteName = foundKey;
          } else {
            // Connection is disconnected - keep it and navigate to existing chat
            AppLogger.d('Connection to $foundKey disconnected (retaining)', tag: 'ConnMgr');
            AppLogger.d('Active: ${_activeConnections.length} -> ${_activeConnections.keys.join(", ")}', tag: 'ConnMgr');
            _notifyConnectionListeners(foundKey, foundService, isIncoming: true);
            try {
              socket.close();
            } catch (_) {}
            return;
          }
        }
      }

  // Create new connection service for the REMOTE device.
  // BUG FIX: Previously passed `this.deviceName` (local device name), causing
  // the ConnectionService to think it was connected to itself. This broke
  // handshakes and led to premature socket closes after declines.
  AppLogger.d('Creating new connection service for remote device $remoteName', tag: 'ConnMgr');
  final service = ConnectionService(deviceName: remoteName);
      _activeConnections[remoteName] = service;
      
      // Attach status listener for incoming connections (same as outgoing)
      service.addStatusListener((info) {
        if (info.status == ConnectionStatus.connected) {
          AppLogger.i('Connection to ${info.deviceName} now connected', tag: 'ConnMgr');
          _startForegroundServiceIfNeeded();
          NotificationService().showNotification(
            type: NotificationType.connectionEstablished,
            title: 'Connected',
            body: 'Successfully connected to ${info.deviceName}',
          );
        } else if (info.status == ConnectionStatus.failed) {
          // ONLY remove failed connections. NEVER remove disconnected connections.
          AppLogger.w('Connection to ${info.deviceName} failed – removing', tag: 'ConnMgr');
          _activeConnections.remove(remoteName);
          AppLogger.d('Active after removal: ${_activeConnections.length} -> ${_activeConnections.keys.join(", ")}', tag: 'ConnMgr');
          _stopForegroundServiceIfNeeded();
          NotificationService().showNotification(
            type: NotificationType.connectionLost,
            title: 'Connection Failed',
            body: 'Connection to ${info.deviceName} failed',
          );
        } else if (info.status == ConnectionStatus.disconnected) {
          // Remove disconnected connections for fresh reconnect from radar
          AppLogger.d('Disconnected from ${info.deviceName} - removing', tag: 'ConnMgr');
          _activeConnections.remove(remoteName);
          AppLogger.d('Active after disconnect: ${_activeConnections.length} -> ${_activeConnections.keys.join(", ")}', tag: 'ConnMgr');
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
      
      AppLogger.d('Got ConnectionService for $remoteName', tag: 'ConnMgr');

      // Accept the connection using the provided socket
      AppLogger.v('Calling acceptConnection for $remoteName', tag: 'ConnMgr');
      final success = await service.acceptConnection(socket, remoteName);

      if (success) {
        AppLogger.i('Incoming connection from $remoteName accepted', tag: 'ConnMgr');
        _notifyConnectionListeners(remoteName, service, isIncoming: true);
        
        // Start foreground service on Android when first connection established
        await _startForegroundServiceIfNeeded();
      } else {
        AppLogger.w('Failed to accept incoming connection from $remoteName', tag: 'ConnMgr');
        _activeConnections.remove(remoteName);
      }
    } catch (e, stackTrace) {
      AppLogger.e('Exception handling incoming connection: $e', tag: 'ConnMgr', error: e, stackTrace: stackTrace);
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
      AppLogger.d('Starting foreground service (first connected device)', tag: 'ConnMgr');
      try {
        final started = await BackgroundService.start();
        if (started) {
          AppLogger.i('Foreground service started', tag: 'ConnMgr');
          _updateForegroundServiceNotification();
        }
      } catch (e) {
          AppLogger.w('Failed to start foreground service: $e', tag: 'ConnMgr', error: e);
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
      AppLogger.d('Stopping foreground service (no connected devices)', tag: 'ConnMgr');
      try {
        await BackgroundService.stop();
        AppLogger.i('Foreground service stopped', tag: 'ConnMgr');
      } catch (e) {
        AppLogger.w('Failed to stop foreground service: $e', tag: 'ConnMgr', error: e);
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
    AppLogger.v('Notifying ${_connectionListeners.length} listeners about ${isIncoming ? "incoming" : "outgoing"} connection to $deviceName', tag: 'ConnMgr');
    for (final listener in _connectionListeners) {
      try {
        listener(deviceName, service, isIncoming);
      } catch (e) {
        AppLogger.w('Error notifying listener: $e', tag: 'ConnMgr', error: e);
      }
    }
  }

  /// Get active connection to a device by name or IP
  ConnectionService? getConnection(String deviceName) {
    // First try exact name match
    var connection = _activeConnections[deviceName];
    AppLogger.v('getConnection($deviceName) -> ${connection != null ? "found by name" : "not found by name"}', tag: 'ConnMgr');
    
    // If not found by name, try to find by IP (in case deviceName is an IP or we need to match by IP)
    if (connection == null) {
      // Check if deviceName might be an IP address
      final ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
      final isIp = ipPattern.hasMatch(deviceName);
      
      if (isIp) {
        // deviceName is an IP, search by IP
        for (final entry in _activeConnections.entries) {
          if (entry.value.currentConnection?.ipAddress == deviceName) {
            connection = entry.value;
            AppLogger.v('Found connection by IP match: $deviceName -> ${entry.key}', tag: 'ConnMgr');
            break;
          }
        }
      }
    }
    
    if (connection == null) {
      AppLogger.v('Available keys: ${_activeConnections.keys.join(", ")}', tag: 'ConnMgr');
      AppLogger.v('Connection IPs: ${_activeConnections.entries.map((e) => "${e.key}:${e.value.currentConnection?.ipAddress}").join(", ")}', tag: 'ConnMgr');
    }
    
    return connection;
  }

  /// Remove a connection
  void removeConnection(String deviceName) {
    final service = _activeConnections.remove(deviceName);
    if (service != null) {
      AppLogger.d('Removed connection to $deviceName', tag: 'ConnMgr');
      service.dispose();
      
      // Stop foreground service if no connections remain
      _stopForegroundServiceIfNeeded();
    }
  }

  /// Get all active connections
  Map<String, ConnectionService> get activeConnections => Map.unmodifiable(_activeConnections);

  /// Close all connections
  Future<void> closeAll() async {
    AppLogger.d('closeAll() called – disconnecting all without clearing', tag: 'ConnMgr');
    for (final entry in _activeConnections.entries) {
      try {
        await entry.value.disconnect();
      } catch (e) {
        AppLogger.w('closeAll() error disconnecting ${entry.key}: $e', tag: 'ConnMgr', error: e);
      }
    }
    ConnectionLogger.instance.log('closeAll() executed – active keys retained: ${_activeConnections.keys.join(", ")}');
    await _stopForegroundServiceIfNeeded();
  }
}
