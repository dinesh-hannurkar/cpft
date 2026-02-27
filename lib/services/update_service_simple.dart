import 'dart:convert';
import 'dart:io';

import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool silent = true,
  }) async {
    if (Platform.isAndroid) {
      await _checkAndroidUpdate(context, silent);
    } else if (Platform.isIOS) {
      await _checkiOSUpdate(context, silent);
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await _checkDesktopUpdate(context, silent);
    }
  }

  static Future<void> _checkAndroidUpdate(
    BuildContext context,
    bool silent,
  ) async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
      } else if (!silent) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('App is up to date')));
        }
      }
    } catch (e) {
      debugPrint('Android update error: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update check failed: $e')));
      }
    }
  }

  static Future<void> _checkiOSUpdate(BuildContext context, bool silent) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // ===== CONFIGURATION - CHANGE THIS TO YOUR iOS BUNDLE ID =====
      const String iosBundleId = 'com.omnity.fylooo'; // Your iOS bundle ID
      // ===== END CONFIGURATION =====

      final response = await http.get(
        Uri.parse('https://itunes.apple.com/lookup?bundleId=$iosBundleId'),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final results = json['results'];
        if (results != null && results.isNotEmpty) {
          final storeVersion = results[0]['version'];
          if (_isNewVersionAvailable(currentVersion, storeVersion)) {
            _showUpdateDialog(context, results[0]['trackViewUrl']);
          } else if (!silent && context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('App is up to date')));
          }
        }
      }
    } catch (e) {
      debugPrint('iOS update error: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update check failed: $e')));
      }
    }
  }

  static Future<void> _checkDesktopUpdate(
    BuildContext context,
    bool silent,
  ) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Determine platform key for releases.json
      String platformKey = '';
      if (Platform.isWindows)
        platformKey = 'windows';
      else if (Platform.isLinux)
        platformKey = 'linux';
      else if (Platform.isMacOS)
        platformKey = 'macos';

      final response = await http.get(
        Uri.parse('https://fylooo.com/releases.json'),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final platforms = json['platforms'];
        if (platforms != null && platforms[platformKey] != null) {
          final latestRelease = platforms[platformKey][0];
          final storeVersion = latestRelease['version'];

          if (_isNewVersionAvailable(currentVersion, storeVersion)) {
            _showUpdateDialog(context, 'https://fylooo.com/downloads.html');
          } else if (!silent && context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('App is up to date')));
          }
        }
      }
    } catch (e) {
      debugPrint('Desktop update error: $e');
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update check failed: $e')));
      }
    }
  }

  static bool _isNewVersionAvailable(String current, String latest) {
    List<int> currentParts = current
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    List<int> latestParts = latest
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    for (int i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length || latestParts[i] > currentParts[i]) {
        return true;
      } else if (latestParts[i] < currentParts[i]) {
        return false;
      }
    }
    return false;
  }

  static void _showUpdateDialog(BuildContext context, String appStoreUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          elevation: 10,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.system_update_rounded,
                  size: 60,
                  color: AppColors.primary,
                ),
                const SizedBox(height: AppSizes.md),
                Text(
                  'Update Available',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: AppSizes.sm * 1.5),
                Text(
                  'A new version of the app is available. Please update to get the latest features and improvements.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                ),
                const SizedBox(height: AppSizes.lg),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final url = Uri.parse(appStoreUrl);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Update",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
