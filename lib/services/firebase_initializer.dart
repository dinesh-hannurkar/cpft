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
  static int get appCount {
    try {
      return Firebase.apps.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> ensure() async {
    if (_initialized) return;
    if (_inFlight != null) {
      return _inFlight!;
    }
    _inFlight = _initOnce();
    try {
      await _inFlight;
      _initialized = true;
      int count = _safeAppsLength();
      AppLogger.i('Firebase initialized (apps=$count)', tag: 'Startup');
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
    final opts = DefaultFirebaseOptions.currentPlatform;
    var count = _safeAppsLength();
    if (count == 0) {
      try {
        await Firebase.initializeApp(options: opts);
      } catch (e) {
        AppLogger.w('Firebase.initializeApp warning: $e', tag: 'Startup');
      }
    }

    const attempts = 12; // ~1.8s total
    for (int i = 0; i < attempts; i++) {
      count = _safeAppsLength();
      if (count > 0) break;
      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (count == 0) {
      try {
        await Firebase.initializeApp(options: opts);
        count = _safeAppsLength();
      } catch (e) {
        AppLogger.e('Firebase second init attempt failed: $e', tag: 'Startup');
      }
    }

    if (count == 0) {
      throw Exception('Firebase not available after initialization (apps=0)');
    }

    try {
      _projectId = Firebase.apps.first.options.projectId;
    } catch (_) {
      _projectId = opts.projectId;
    }
  }

  static int _safeAppsLength() {
    try {
      return Firebase.apps.length;
    } catch (_) {
      return 0;
    }
  }
}
