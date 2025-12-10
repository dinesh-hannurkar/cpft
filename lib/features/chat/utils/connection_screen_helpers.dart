import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/received_file.dart';

class ConnectionScreenHelpers {
  /// Prompts user to save a file with a new name/location
  static Future<void> saveFileAs({
    required BuildContext context,
    required String sourcePath,
    required String originalName,
  }) async {
    try {
      String? destPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File As',
        fileName: originalName,
      );

      if (destPath == null) {
        debugPrint('[ConnectionScreen] User cancelled save-as');
        return;
      }

      final sourceFile = io.File(sourcePath);
      if (!await sourceFile.exists()) {
        throw Exception('Source file no longer exists');
      }

      await sourceFile.copy(destPath);

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to: $destPath')));
      }
    } catch (e) {
      debugPrint('[ConnectionScreen] Save-as error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  /// Formats bytes into human-readable size string
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Formats speed into human-readable string
  static String formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  /// Gets status text based on connection info
  static String getConnectionStatusText({
    required bool isConnected,
    required bool isConnecting,
    String? ipAddress,
  }) {
    if (isConnecting) {
      return 'Connecting...';
    }
    if (isConnected && ipAddress != null) {
      return 'Connected • $ipAddress';
    }
    if (isConnected) {
      return 'Connected';
    }
    return 'Disconnected';
  }

  /// Converts ReceivedFile to ReceivedFileItem for widget use
  static List<ReceivedFileItem> convertToFileItems(List<ReceivedFile> files) {
    return files
        .map(
          (f) => ReceivedFileItem(
            name: f.name,
            path: f.path,
            timestamp: f.timestamp,
          ),
        )
        .toList();
  }
}

class ReceivedFileItem {
  final String name;
  final String path;
  final DateTime timestamp;

  ReceivedFileItem({
    required this.name,
    required this.path,
    required this.timestamp,
  });
}
