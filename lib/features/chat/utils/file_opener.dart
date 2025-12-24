import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fylooo/utils/permissions.dart';
import '../../../../core/constants/app_colors.dart';

class FileOpener {
  /// Opens a file with special handling for APK files
  static Future<void> openFile({
    required BuildContext context,
    required String filePath,
    required String fileName,
  }) async {
    try {
      if (filePath.toLowerCase().endsWith('.apk') && io.Platform.isAndroid) {
        await _openApkFile(context, filePath, fileName);
      } else {
        await _openRegularFile(context, filePath, fileName);
      }
    } catch (e) {
      debugPrint('[FileOpener] Error opening file: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening file: $e')));
      }
    }
  }

  static Future<void> _openApkFile(
    BuildContext context,
    String filePath,
    String fileName,
  ) async {
    debugPrint('[FileOpener] Opening APK file: $filePath');

    // Check and request install packages permission
    if (await Permission.requestInstallPackages.isDenied) {
      final status = await AppPermissions.runGuarded(
        () => Permission.requestInstallPackages.request(),
      );
      if (status.isDenied || status.isPermanentlyDenied) {
        if (context.mounted) {
          _showPermissionRequiredSnackBar(context);
        }
        return;
      }
    }

    // Try to open APK with type specification
    var result = await OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );

    debugPrint(
      '[FileOpener] APK open result: ${result.type} - ${result.message}',
    );

    if (result.type != ResultType.done) {
      // Fallback: try without type specification
      result = await OpenFilex.open(filePath);
      debugPrint(
        '[FileOpener] APK open fallback result: ${result.type} - ${result.message}',
      );
    }

    if (result.type != ResultType.done && context.mounted) {
      // Still failed, open file manager
      await _openParentDirectory(filePath);
      _showFileManagerSnackBar(context);
    }
  }

  static Future<void> _openRegularFile(
    BuildContext context,
    String filePath,
    String fileName,
  ) async {
    final result = await OpenFilex.open(filePath);
    debugPrint(
      '[FileOpener] Open file result: ${result.type} - ${result.message}',
    );

    if (result.type != ResultType.done) {
      debugPrint('[FileOpener] Cannot open file directly, opening folder...');
      await _openParentDirectory(filePath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fileName - Opened in file manager'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  static Future<void> _openParentDirectory(String filePath) async {
    final file = io.File(filePath);
    final parentDir = file.parent.path;
    await OpenFilex.open(parentDir);
  }

  static void _showPermissionRequiredSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Permission required to install APK files.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.white),
        ),
        duration: const Duration(seconds: 30),
        action: SnackBarAction(
          label: 'Allow',
          textColor: AppColors.primary,
          onPressed: () async {
            await openAppSettings();
          },
        ),
      ),
    );
  }

  static void _showFileManagerSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open installer. File shown in file manager.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Reveals a file in its parent directory
  static Future<void> revealInFolder({
    required BuildContext context,
    required String filePath,
  }) async {
    try {
      final file = io.File(filePath);
      final parentDir = file.parent.path;
      debugPrint('[FileOpener] Revealing file in: $parentDir');
      await OpenFilex.open(parentDir);
    } catch (e) {
      debugPrint('[FileOpener] Error revealing file: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('File at: $filePath')));
      }
    }
  }
}
