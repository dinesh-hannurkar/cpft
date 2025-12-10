import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Handler for foreground service callbacks
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

/// Background task handler to keep app alive
class BackgroundTaskHandler extends TaskHandler {
  SendPort? _sendPort;
  int _eventCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BackgroundService] Foreground service started at $timestamp');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This is called every interval (e.g., every 5 seconds)
    _eventCount++;
    
    // Send data to main isolate if port is available
    final data = {
      'timestamp': timestamp.toIso8601String(),
      'eventCount': _eventCount,
    };
    
    _sendPort?.send(data);
    
    // Update notification with current status
    FlutterForegroundTask.updateService(
      notificationText: 'Keeping connection alive... ($_eventCount)',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[BackgroundService] Foreground service destroyed at $timestamp');
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('[BackgroundService] Notification button pressed: $id');
  }

  @override
  void onNotificationPressed() {
    debugPrint('[BackgroundService] Notification pressed - bringing app to foreground');
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {
    debugPrint('[BackgroundService] Notification dismissed');
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('[BackgroundService] Received data: $data');
    if (data is SendPort) {
      _sendPort = data;
    }
  }
}

/// Service for managing Android foreground service
class BackgroundService {
  static bool _isInitialized = false;
  static bool _isRunning = false;

  /// Initialize foreground service configuration
  static Future<void> initialize() async {
    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'cpft_foreground_service',
        channelName: 'CPFT Background Service',
        channelDescription: 'Keeps the app running to maintain connections and transfers',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // Repeat every 5 seconds
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
    debugPrint('[BackgroundService] Initialized');
  }

  /// Start the foreground service
  static Future<bool> start() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isRunning) {
      debugPrint('[BackgroundService] Service already running');
      return true;
    }

    final serviceStatus = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'CPFT Running',
      notificationText: 'Maintaining connection and file transfers',
      callback: startCallback,
    );

    _isRunning = true;
    debugPrint('[BackgroundService] Start result: $_isRunning (status: $serviceStatus)');
    return _isRunning;
  }

  /// Stop the foreground service
  static Future<bool> stop() async {
    if (!_isRunning) {
      debugPrint('[BackgroundService] Service not running');
      return true;
    }

    final result = await FlutterForegroundTask.stopService();
    _isRunning = false;
    debugPrint('[BackgroundService] Stopped (result: $result)');
    return true;
  }

  /// Check if service is running
  static bool get isRunning => _isRunning;

  /// Update notification text
  static Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!_isRunning) return;

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }
}
