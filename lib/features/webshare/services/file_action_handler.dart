import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cpft/utils/file_saver.dart';
import 'package:cpft/features/webshare/services/web_download.dart';
import 'package:cpft/features/webshare/services/web_received_cache.dart';
import 'package:cpft/utils/mime_utils.dart';
import 'package:cpft/shared/widgets/app_bottom_sheet.dart';

/// Utility class for handling file actions across different screens
class FileActionHandler {
  /// Creates onTap callback for file cards
  static VoidCallback? createOnTap(String filename, String path) {
    return () async {
      await handleFileTap(filename, path);
    };
  }

  /// Creates onAction callback for file cards
  static void Function(BuildContext)? createOnAction(String filename, String path) {
    return (context) async {
      await handleFileAction(context, filename, path);
    };
  }

  /// Handles file tap (open/download)
  static Future<void> handleFileTap(String filename, String path) async {
    if (kIsWeb &&
        (path.startsWith('web-bytes:') || path.startsWith('web-parts:'))) {
      // On web cached items, trigger download
      await _downloadWebFile(filename, path);
      return;
    }

    // Native: open file
    try {
      await OpenFilex.open(path);
    } catch (_) {}
  }

  /// Handles file action (download on web, action sheet on native)
  static Future<void> handleFileAction(BuildContext context, String filename, String path) async {
    if (kIsWeb && path.startsWith('web-bytes:')) {
      await _downloadWebFileFromCache(filename, path, 'web-bytes:');
      return;
    }

    if (kIsWeb && path.startsWith('web-parts:')) {
      await _downloadWebFileFromCache(filename, path, 'web-parts:');
      return;
    }

    // Native: show actions - Open, Save to device…, Share
    if (!kIsWeb) {
      await _showNativeFileActions(context, filename, path);
      return;
    }
  }

  /// Downloads file from web cache
  static Future<void> _downloadWebFile(String filename, String path) async {
    if (path.startsWith('web-bytes:')) {
      await _downloadWebFileFromCache(filename, path, 'web-bytes:');
    } else if (path.startsWith('web-parts:')) {
      await _downloadWebFileFromCache(filename, path, 'web-parts:');
    }
  }

  /// Downloads file from specific web cache type
  static Future<void> _downloadWebFileFromCache(String filename, String path, String prefix) async {
    final id = path.substring(prefix.length);

    if (prefix == 'web-bytes:') {
      final data = WebReceivedCache.get(id);
      if (data != null) {
        final ext = filename.contains('.')
            ? filename.split('.').last.toLowerCase()
            : '';
        final mime = MimeUtils.guessMime(ext);
        WebDownload.saveBytes(filename, data, contentType: mime);
      }
    } else if (prefix == 'web-parts:') {
      final parts = WebReceivedCache.getParts(id);
      if (parts != null) {
        final ext = filename.contains('.')
            ? filename.split('.').last.toLowerCase()
            : '';
        final mime = MimeUtils.guessMime(ext);
        WebDownload.saveParts(filename, parts.cast(), contentType: mime);
      }
    }
  }

  /// Shows native file action bottom sheet
  static Future<void> _showNativeFileActions(BuildContext context, String filename, String path) async {
    showAppBottomSheet(
      context: context,
      title: 'File Options',
      subtitle: filename,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open'),
            onTap: () async {
              Navigator.of(context).pop();
              try {
                await OpenFilex.open(path);
              } catch (_) {}
            },
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Save to device…'),
            subtitle: const Text('Choose a location to save this file'),
            onTap: () async {
              Navigator.of(context).pop();
              await FileSaver.saveToDevicePicker(
                context: context,
                filename: filename,
                sourcePath: path,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Share / Export'),
            onTap: () async {
              Navigator.of(context).pop();
              final box = context.findRenderObject() as RenderBox?;
              final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
              final size = box?.size ?? Size.zero;
              await Share.shareXFiles(
                [XFile(path)],
                sharePositionOrigin: Rect.fromLTWH(
                  position.dx,
                  position.dy,
                  size.width,
                  size.height,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}