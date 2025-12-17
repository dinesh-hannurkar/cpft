import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io' show Platform;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

enum FeedbackType {
  bug,
  feature,
  general,
  other,
}

class FeedbackData {
  final String id;
  final FeedbackType type;
  final String description;
  final String? stepsToReproduce;
  final String? expectedBehavior;
  final String deviceInfo;
  final String appVersion;
  final String platform;
  final DateTime timestamp;
  final String? userId; // Optional for future user tracking

  FeedbackData({
    required this.id,
    required this.type,
    required this.description,
    this.stepsToReproduce,
    this.expectedBehavior,
    required this.deviceInfo,
    required this.appVersion,
    required this.platform,
    required this.timestamp,
    this.userId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString().split('.').last,
      'description': description,
      'stepsToReproduce': stepsToReproduce,
      'expectedBehavior': expectedBehavior,
      'deviceInfo': deviceInfo,
      'appVersion': appVersion,
      'platform': platform,
      'timestamp': Timestamp.fromDate(timestamp),
      'userId': userId,
    };
  }

  factory FeedbackData.fromJson(Map<String, dynamic> json) {
    return FeedbackData(
      id: json['id'],
      type: FeedbackType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => FeedbackType.other,
      ),
      description: json['description'],
      stepsToReproduce: json['stepsToReproduce'],
      expectedBehavior: json['expectedBehavior'],
      deviceInfo: json['deviceInfo'],
      appVersion: json['appVersion'],
      platform: json['platform'],
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      userId: json['userId'],
    );
  }
}

class FeedbackService {
  static final FeedbackService _instance = FeedbackService._internal();
  factory FeedbackService() => _instance;
  FeedbackService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Submit feedback to Firestore with email fallback
  Future<bool> submitFeedback({
    required FeedbackType type,
    required String description,
    String? stepsToReproduce,
    String? expectedBehavior,
    required bool includeDeviceInfo,
  }) async {
    try {
      // Get app and device info
      final packageInfo = await PackageInfo.fromPlatform();
      final deviceInfo = await _getDeviceInfo(includeDeviceInfo);

      // Create feedback data
      final feedbackId = _generateFeedbackId();
      final feedbackData = FeedbackData(
        id: feedbackId,
        type: type,
        description: description,
        stepsToReproduce: stepsToReproduce,
        expectedBehavior: expectedBehavior,
        deviceInfo: deviceInfo,
        appVersion: packageInfo.version,
        platform: kIsWeb ? 'web' : Platform.operatingSystem,
        timestamp: DateTime.now(),
      );

      // Try to save to Firestore first
      await _saveToFirestore(feedbackData);
      return true;
    } catch (e) {
      // If Firestore fails, try email fallback
      debugPrint('Failed to save feedback to Firestore: $e');
      try {
        await _sendViaEmailFallback(
          type: type,
          description: description,
          stepsToReproduce: stepsToReproduce,
          expectedBehavior: expectedBehavior,
          includeDeviceInfo: includeDeviceInfo,
        );
        return true;
      } catch (emailError) {
        debugPrint('Email fallback also failed: $emailError');
        return false;
      }
    }
  }

  /// Save feedback to Firestore
  Future<void> _saveToFirestore(FeedbackData feedback) async {
    await _firestore
        .collection('feedback')
        .doc(feedback.id)
        .set(feedback.toJson());
  }

  /// Get all feedback (for admin purposes)
  Future<List<FeedbackData>> getAllFeedback() async {
    try {
      final snapshot = await _firestore
          .collection('feedback')
          .orderBy('timestamp', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => FeedbackData.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Failed to get feedback: $e');
      return [];
    }
  }

  /// Get feedback by type
  Future<List<FeedbackData>> getFeedbackByType(FeedbackType type) async {
    try {
      final snapshot = await _firestore
          .collection('feedback')
          .where('type', isEqualTo: type.toString().split('.').last)
          .orderBy('timestamp', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => FeedbackData.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Failed to get feedback by type: $e');
      return [];
    }
  }

  /// Email fallback when Firestore is unavailable
  Future<void> _sendViaEmailFallback({
    required FeedbackType type,
    required String description,
    String? stepsToReproduce,
    String? expectedBehavior,
    required bool includeDeviceInfo,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final deviceInfo = await _getDeviceInfo(includeDeviceInfo);
    final content = _buildEmailContent(
      type: type,
      description: description,
      stepsToReproduce: stepsToReproduce,
      expectedBehavior: expectedBehavior,
      deviceInfo: includeDeviceInfo ? deviceInfo : null,
      appVersion: packageInfo.version,
    );

    final subject = 'CPFT ${_getFeedbackTypeTitle(type)} - ${packageInfo.version} (Offline)';

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'feedback@cpft.app',
      queryParameters: {
        'subject': subject,
        'body': content,
      },
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      throw 'Could not launch email client';
    }
  }

  /// Generate unique feedback ID
  String _generateFeedbackId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 1000;
    return 'fb_${timestamp}_$random';
  }

  /// Get device information
  Future<String> _getDeviceInfo(bool includeDeviceInfo) async {
    if (!includeDeviceInfo) return 'Device info not included';

    final buffer = StringBuffer();
    final packageInfo = await PackageInfo.fromPlatform();

    if (kIsWeb) {
      buffer.writeln('Platform: Web');
      buffer.writeln('User Agent: ${Uri.base.host}');
      buffer.writeln('App Version: ${packageInfo.version}');
      buffer.writeln('App Build: ${packageInfo.buildNumber}');
    } else {
      buffer.writeln('Platform: ${Platform.operatingSystem}');
      buffer.writeln('OS Version: ${Platform.operatingSystemVersion}');
      buffer.writeln('App Version: ${packageInfo.version}');
      buffer.writeln('App Build: ${packageInfo.buildNumber}');

      try {
        buffer.writeln('Locale: ${Platform.localeName}');
      } catch (e) {
        // Ignore locale errors
      }
    }

    return buffer.toString();
  }

  /// Build email content for fallback
  String _buildEmailContent({
    required FeedbackType type,
    required String description,
    String? stepsToReproduce,
    String? expectedBehavior,
    String? deviceInfo,
    required String appVersion,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('=== CPFT Feedback (Offline Mode) ===');
    buffer.writeln('Type: ${_getFeedbackTypeTitle(type)}');
    buffer.writeln('Date: ${DateTime.now().toIso8601String()}');
    buffer.writeln('App Version: $appVersion');

    buffer.writeln('\n--- Description ---');
    buffer.writeln(description);

    if (type == FeedbackType.bug) {
      if (stepsToReproduce?.isNotEmpty ?? false) {
        buffer.writeln('\n--- Steps to Reproduce ---');
        buffer.writeln(stepsToReproduce);
      }

      if (expectedBehavior?.isNotEmpty ?? false) {
        buffer.writeln('\n--- Expected Behavior ---');
        buffer.writeln(expectedBehavior);
      }
    }

    if (deviceInfo != null) {
      buffer.writeln('\n--- Device Information ---');
      buffer.writeln(deviceInfo);
    }

    buffer.writeln('\n--- Note ---');
    buffer.writeln('This feedback was sent via email because Firestore was unavailable.');

    buffer.writeln('\n--- End of Feedback ---');

    return buffer.toString();
  }

  /// Get feedback type title
  String _getFeedbackTypeTitle(FeedbackType type) {
    switch (type) {
      case FeedbackType.bug:
        return 'Bug Report';
      case FeedbackType.feature:
        return 'Feature Request';
      case FeedbackType.general:
        return 'General Feedback';
      case FeedbackType.other:
        return 'Other';
    }
  }
}