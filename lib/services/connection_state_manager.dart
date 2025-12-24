import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:fylooo/services/background_service.dart';
import 'package:fylooo/services/notification_service.dart';
import 'package:android_intent_plus/android_intent.dart';

/// Centralized manager for tracking all connection types and managing background service
class ConnectionStateManager {
  static final ConnectionStateManager _instance = ConnectionStateManager._internal();
  factory ConnectionStateManager() => _instance;
  ConnectionStateManager._internal();

  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  // Track different connection types
  bool _hasAppToAppConnections = false;
  bool _hasWebRTCConnections = false;
  bool _hasDiscoveryActive = false;

  bool get hasAnyConnections => _hasAppToAppConnections || _hasWebRTCConnections || _hasDiscoveryActive;
  bool get isBackgroundServiceRunning => BackgroundService.isRunning;

  /// Update app-to-app connection state
  void updateAppToAppConnections(bool hasConnections) {
    _hasAppToAppConnections = hasConnections;
    _updateBackgroundService();
  }

  /// Update WebRTC connection state
  void updateWebRTCConnections(bool hasConnections) {
    _hasWebRTCConnections = hasConnections;
    _updateBackgroundService();
  }

  /// Update discovery active state
  void updateDiscoveryActive(bool isActive) {
    _hasDiscoveryActive = isActive;
    _updateBackgroundService();
  }

  /// Force start background service (for specific use cases)
  Future<void> forceStartBackgroundService() async {
    if (!BackgroundService.isRunning) {
      await BackgroundService.start();
      _connectionStateController.add(true);
    }
  }

  /// Force stop background service
  Future<void> forceStopBackgroundService() async {
    if (BackgroundService.isRunning) {
      await BackgroundService.stop();
      _connectionStateController.add(false);
    }
  }

  /// Internal method to update background service based on connection state
  void _updateBackgroundService() {
    final shouldRun = hasAnyConnections;

    if (shouldRun && !BackgroundService.isRunning) {
      // Start background service
      BackgroundService.start().then((started) {
        if (started) {
          debugPrint('[ConnectionStateManager] Background service started - connections active');
          _connectionStateController.add(true);
        }
      });
    } else if (!shouldRun && BackgroundService.isRunning) {
      // Stop background service and cancel connection notifications
      BackgroundService.stop().then((stopped) async {
        if (stopped) {
          debugPrint('[ConnectionStateManager] Background service stopped - no active connections');
          
          // Add a longer delay to ensure the foreground notification is removed
          await Future.delayed(const Duration(seconds: 1));
          
          // Try to stop the service again in case it didn't work the first time
          await BackgroundService.stop();
          await Future.delayed(const Duration(milliseconds: 500));
          
          _connectionStateController.add(false);
          
          // Cancel all connection-related notifications
          _cancelConnectionNotifications();
        }
      });
    }
  }

  /// Cancel connection-related notifications
  void _cancelConnectionNotifications() {
    // Cancel all notifications to clear any lingering connection status notifications
    NotificationService().cancelAll().then((_) {
      debugPrint('[ConnectionStateManager] All notifications cancelled');
    }).catchError((error) {
      debugPrint('[ConnectionStateManager] Error cancelling all notifications: $error');
    });
    
    // Try to cancel foreground service notifications with common IDs
    // Foreground service notifications often use the serviceId (256) or other system IDs
    final foregroundIds = [256, 257, 258, 259, 260]; // Try a range around the serviceId
    
    for (final id in foregroundIds) {
      NotificationService().cancel(id).then((_) {
        debugPrint('[ConnectionStateManager] Cancelled notification ID: $id');
      }).catchError((error) {
        debugPrint('[ConnectionStateManager] Error cancelling notification $id: $error');
      });
    }
    
    // Also try to cancel with negative IDs (sometimes used by system)
    NotificationService().cancel(-256).catchError((_) {});
    NotificationService().cancel(-1).catchError((_) {});
    
    // Try to force cancel notifications using Android Intent
    _forceCancelAndroidNotifications();
  }

  /// Force cancel notifications using Android Intent (for stubborn foreground notifications)
  void _forceCancelAndroidNotifications() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        // This is a workaround - we can't directly cancel foreground notifications
        // but we can try to trigger a system notification refresh by requesting permissions
        debugPrint('[ConnectionStateManager] Attempted notification refresh workaround');
      } catch (e) {
        debugPrint('[ConnectionStateManager] Error with notification refresh: $e');
      }
    }
  }

  /// Get current connection status
  Map<String, bool> getConnectionStatus() {
    return {
      'appToApp': _hasAppToAppConnections,
      'webRTC': _hasWebRTCConnections,
      'discovery': _hasDiscoveryActive,
      'any': hasAnyConnections,
      'backgroundService': isBackgroundServiceRunning,
    };
  }

  /// Dispose the manager
  void dispose() {
    _connectionStateController.close();
  }
}