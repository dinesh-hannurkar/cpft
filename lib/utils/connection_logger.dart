import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class ConnectionLogger {
  static ConnectionLogger? _instance;
  static ConnectionLogger get instance {
    _instance ??= ConnectionLogger._();
    return _instance!;
  }

  ConnectionLogger._();

  File? _logFile;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final logDir = Directory('${directory.path}/cpft_logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      _logFile = File('${logDir.path}/connection_log_$timestamp.txt');

      await _logFile!.writeAsString('=== CPFT Connection Log ===\n');
      await _logFile!.writeAsString(
        'Started: ${DateTime.now()}\n\n',
        mode: FileMode.append,
      );

      _initialized = true;
      debugPrint('[ConnectionLogger] ✅ Log file created: ${_logFile!.path}');
    } catch (e) {
      debugPrint('[ConnectionLogger] ❌ Failed to initialize: $e');
    }
  }

  Future<void> log(String message) async {
    if (!_initialized) await initialize();
    try {
      final timestamp = DateTime.now().toIso8601String();
      final logMessage = '[$timestamp] $message\n';
      await _logFile?.writeAsString(logMessage, mode: FileMode.append);
    } catch (e) {
      debugPrint('[ConnectionLogger] ❌ Failed to write log: $e');
    }
  }

  Future<String?> getLogPath() async {
    if (!_initialized) await initialize();
    return _logFile?.path;
  }

  Future<String> readLogs() async {
    if (!_initialized || _logFile == null) {
      return 'Log file not initialized';
    }

    try {
      if (await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
      return 'Log file does not exist';
    } catch (e) {
      return 'Error reading logs: $e';
    }
  }

  Future<void> clearLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('=== CPFT Connection Log ===\n');
      await _logFile!.writeAsString(
        'Cleared: ${DateTime.now()}\n\n',
        mode: FileMode.append,
      );
    }
  }
}
