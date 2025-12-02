import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:cpft/firebase_options.dart';
import 'package:cpft/core/logging/app_logger.dart';

class FirebaseInitializer {
  static Future<void>? _inFlight;
  static bool _initialized = false;
  static Object? lastError;
  static final ValueListenable<bool> isReady = _readyNotifier;
  static final ValueNotifier<bool> _readyNotifier = ValueNotifier<bool>(false);
  static String? _projectId;

  static String? get projectId => _projectId;
  static int get appCount => Firebase.apps.length;

  static Future<void> ensure() async {
    if (_initialized) return;
    if (_inFlight != null) {
      return _inFlight!;
    }
    _inFlight = _initOnce();
    try {
      await _inFlight;
      _initialized = true;
      AppLogger.i('Firebase initialized (apps=${Firebase.apps.length})', tag: 'Startup');
      _readyNotifier.value = true;
    } catch (e) {
      AppLogger.e('Firebase initialization failed: $e', tag: 'Startup');
      lastError = e;
      _readyNotifier.value = false;
      rethrow;
    } finally {
      _inFlight = null;
    }
  }

  static Future<void> _initOnce() async {
    if (Firebase.apps.isEmpty) {
      final opts = DefaultFirebaseOptions.currentPlatform;
      await Firebase.initializeApp(options: opts);
      _projectId = opts.projectId;
    } else {
      // Derive project id from existing app if available
      try {
        _projectId = Firebase.apps.first.options.projectId;
      } catch (_) {}
    }
  }
}
