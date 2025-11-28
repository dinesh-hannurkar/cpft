import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class FileOperations {
  /// Prompts user to select a destination and saves file
  static Future<void> saveFileAs({
    required BuildContext context,
    required String sourcePath,
    required String originalName,
  }) async {
    try {
      String? destPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File',
        fileName: originalName,
      );

      if (destPath == null) {
        debugPrint('[FileOperations] User cancelled save-as');
        return;
      }

      final sourceFile = io.File(sourcePath);
      if (!await sourceFile.exists()) {
        throw Exception('Source file does not exist');
      }

      await sourceFile.copy(destPath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File saved to: $destPath')),
        );
      }
    } catch (e) {
      debugPrint('[FileOperations] Error saving file: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save file: $e')),
        );
      }
    }
  }

  /// Tries to share a file using the system share dialog
  static Future<void> shareFile({
    required BuildContext context,
    required String sourcePath,
    required String originalName,
  }) async {
    try {
      final result = await Share.shareXFiles(
        [XFile(sourcePath)],
        text: 'Sharing $originalName',
      );

      debugPrint('[FileOperations] Share result: ${result.status}');
    } catch (e) {
      debugPrint('[FileOperations] Error sharing file: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share file: $e')),
        );
      }
    }
  }

  /// Picks a file from the device
  static Future<PlatformFile?> pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        return result.files.first;
      }
      return null;
    } catch (e) {
      debugPrint('[FileOperations] Error picking file: $e');
      return null;
    }
  }

  /// Gets file extension from filename
  static String getFileExtension(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot == -1 || lastDot == filename.length - 1) {
      return '';
    }
    return filename.substring(lastDot + 1);
  }

  /// Formats file extension for display (max 6 chars, uppercase)
  static String formatExtension(String ext) {
    ext = ext.trim();
    if (ext.length > 6) ext = ext.substring(0, 6);
    return ext.toUpperCase();
  }

  /// Formats file size in human-readable format
  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
