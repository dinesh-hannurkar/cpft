import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;

class FileSaver {
  const FileSaver._(); // private constructor to prevent instantiation

  /// Opens a "save to device" picker and shows a SnackBar on success/failure.
  static Future<void> saveToDevicePicker({
    required BuildContext context,
    required String filename,
    required String sourcePath,
  }) async {
    try {
      final params = SaveFileDialogParams(
        sourceFilePath: sourcePath,
        fileName: filename,
      );

      final savedPath = await FlutterFileDialog.saveFile(params: params);

      if (savedPath != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: ${p.basename(savedPath)}')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }
}
