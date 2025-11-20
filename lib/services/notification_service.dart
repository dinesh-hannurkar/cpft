import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Types of notifications the app can send
enum NotificationType {
  connectionEstablished,
  connectionLost,
  incomingConnectionRequest,
  messageReceived,
  fileTransferStarted,
  fileTransferCompleted,
  fileTransferFailed,
  webShareClientConnected,
  webShareClientDisconnected,
  serviceRestarted,
  error,
}

/// Reusable notification service for the app
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[NotificationService] Notification tapped: ${response.payload}');
    // Handle notification tap actions here if needed
  }

  /// Create notification channels for Android
  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel connectionChannel = AndroidNotificationChannel(
      'connections',
      'Connections',
      description: 'Connection status notifications',
      importance: Importance.defaultImportance,
    );

    const AndroidNotificationChannel transferChannel = AndroidNotificationChannel(
      'transfers',
      'File Transfers',
      description: 'File transfer status notifications',
      importance: Importance.high,
    );

    const AndroidNotificationChannel generalChannel = AndroidNotificationChannel(
      'general',
      'General',
      description: 'General app notifications',
      importance: Importance.defaultImportance,
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(connectionChannel);

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(transferChannel);

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(generalChannel);
  }

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const DarwinInitializationSettings initializationSettingsMacOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      macOS: initializationSettingsMacOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    _isInitialized = true;
    debugPrint('[NotificationService] ✅ Initialized');
  }

  /// Show a notification
  Future<void> showNotification({
    required NotificationType type,
    required String title,
    required String body,
    String? payload,
    bool enableSound = true,
    bool enableVibration = true,
  }) async {
    if (!_isInitialized) {
      debugPrint('[NotificationService] ⚠️  Not initialized, call initialize() first');
      return;
    }

    final int id = DateTime.now().millisecondsSinceEpoch ~/ 1000; // Unique ID

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _getChannelId(type),
      _getChannelName(type),
      channelDescription: _getChannelDescription(type),
      importance: _getImportance(type),
      playSound: enableSound,
      enableVibration: enableVibration,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const DarwinNotificationDetails macOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: macOSDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );

    debugPrint('[NotificationService] 📱 Notification shown: $title - $body');
  }

  /// Get channel ID for notification type
  String _getChannelId(NotificationType type) {
    switch (type) {
      case NotificationType.connectionEstablished:
      case NotificationType.connectionLost:
      case NotificationType.incomingConnectionRequest:
        return 'connections';
      case NotificationType.messageReceived:
        return 'general';
      case NotificationType.fileTransferStarted:
      case NotificationType.fileTransferCompleted:
      case NotificationType.fileTransferFailed:
        return 'transfers';
      default:
        return 'general';
    }
  }

  /// Get channel name for notification type
  String _getChannelName(NotificationType type) {
    switch (type) {
      case NotificationType.connectionEstablished:
      case NotificationType.connectionLost:
      case NotificationType.incomingConnectionRequest:
        return 'Connections';
      case NotificationType.messageReceived:
        return 'Messages';
      case NotificationType.fileTransferStarted:
      case NotificationType.fileTransferCompleted:
      case NotificationType.fileTransferFailed:
        return 'File Transfers';
      default:
        return 'General';
    }
  }

  /// Get channel description for notification type
  String _getChannelDescription(NotificationType type) {
    switch (type) {
      case NotificationType.connectionEstablished:
      case NotificationType.connectionLost:
      case NotificationType.incomingConnectionRequest:
        return 'Connection status notifications';
      case NotificationType.messageReceived:
        return 'Chat message notifications';
      case NotificationType.fileTransferStarted:
      case NotificationType.fileTransferCompleted:
      case NotificationType.fileTransferFailed:
        return 'File transfer status notifications';
      default:
        return 'General app notifications';
    }
  }

  /// Get importance for notification type
  Importance _getImportance(NotificationType type) {
    switch (type) {
      case NotificationType.fileTransferCompleted:
      case NotificationType.fileTransferFailed:
      case NotificationType.incomingConnectionRequest:
      case NotificationType.messageReceived:
        return Importance.high;
      default:
        return Importance.defaultImportance;
    }
  }

  /// Request notification permissions (iOS and macOS)
  Future<bool> requestPermissions() async {
    if (!Platform.isIOS && !Platform.isMacOS) return true;

    final bool? granted = await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );

    return granted ?? false;
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  /// Cancel specific notification by ID
  Future<void> cancel(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }
}