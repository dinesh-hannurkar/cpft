import 'dart:convert';
import 'dart:io';

import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';

class UpdateService {
  static final ValueNotifier<Map<String, dynamic>?> updateNotifier =
      ValueNotifier(null);
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
          AppSnackbar.showInfo(context, 'App is up to date');
        }
      }
    } catch (e) {
      debugPrint('Android update error: $e');
      if (!silent && context.mounted) {
        AppSnackbar.showError(context, 'Update check failed: $e');
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
            AppSnackbar.showInfo(context, 'App is up to date');
          }
        }
      }
    } catch (e) {
      debugPrint('iOS update error: $e');
      if (!silent && context.mounted) {
        AppSnackbar.showError(context, 'Update check failed: $e');
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
        Uri.parse('http://192.168.1.181:3000/releases.json'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        final latestRelease = jsonList.firstWhere(
          (item) => item['platform'] == platformKey,
          orElse: () => null,
        );

        if (latestRelease != null) {
          final storeVersion = (latestRelease['version'] as String).replaceAll(
            'v',
            '',
          );

          if (_isNewVersionAvailable(currentVersion, storeVersion)) {
            updateNotifier.value = latestRelease;
            if (!silent) {
              _showUpdateDialog(
                context,
                'https://fylooo.com/downloads.html',
                desktopRelease: latestRelease,
              );
            }
          } else if (!silent && context.mounted) {
            updateNotifier.value = null;
            AppSnackbar.showInfo(context, 'App is up to date');
          } else {
            updateNotifier.value = null;
          }
        }
      }
    } catch (e) {
      debugPrint('Desktop update error: $e');
      if (!silent && context.mounted) {
        AppSnackbar.showError(context, 'Update check failed: $e');
      }
    }
  }

  static Future<void> downloadAndApplyUpdate(
    BuildContext context,
    Map<String, dynamic> release,
  ) async {
    try {
      final updateUrl = release['update_zip'];
      if (updateUrl == null) {
        _launchUrl('https://fylooo.com/downloads.html');
        return;
      }

      final fullUrl = updateUrl.startsWith('http')
          ? updateUrl
          : 'https://fylooo.com$updateUrl';

      // 1. Download ZIP
      final response = await http.get(Uri.parse(fullUrl));
      if (response.statusCode != 200) throw Exception('Download failed');

      final tempDir = await getTemporaryDirectory();
      final zipFile = File(p.join(tempDir.path, 'update.zip'));
      await zipFile.writeAsBytes(response.bodyBytes);

      // 2. Extract
      final updateDir = Directory(p.join(tempDir.path, 'fylooo_update'));
      if (await updateDir.exists()) await updateDir.delete(recursive: true);
      await updateDir.create();

      final archive = ZipDecoder().decodeBytes(response.bodyBytes);
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          File(p.join(updateDir.path, filename))
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory(
            p.join(updateDir.path, filename),
          ).createSync(recursive: true);
        }
      }

      // 3. Prepare Patch Script
      final currentExe = Platform.resolvedExecutable;
      final installDir = p.dirname(currentExe);

      if (Platform.isWindows) {
        await _applyWindowsUpdate(updateDir.path, installDir, currentExe);
      } else if (Platform.isLinux) {
        await _applyLinuxUpdate(updateDir.path, installDir, currentExe);
      }

      exit(0); // Exit app to let the script take over
    } catch (e) {
      debugPrint('Update failed: $e');
      if (context.mounted) {
        AppSnackbar.showError(context, 'Update failed: $e');
      }
    }
  }

  static Future<void> _applyWindowsUpdate(
    String sourceDir,
    String destDir,
    String exePath,
  ) async {
    final scriptPath = p.join(p.dirname(sourceDir), 'patch.bat');
    final script =
        '''
@echo off
timeout /t 2 /nobreak > nul
xcopy /s /y /e "$sourceDir\\*" "$destDir\\"
start "" "$exePath"
del "%~f0"
''';
    await File(scriptPath).writeAsString(script);
    await Process.start('cmd', [
      '/c',
      scriptPath,
    ], mode: ProcessStartMode.detached);
  }

  static Future<void> _applyLinuxUpdate(
    String sourceDir,
    String destDir,
    String exePath,
  ) async {
    final scriptPath = p.join(p.dirname(sourceDir), 'patch.sh');
    final script =
        '''
#!/bin/bash
sleep 2
cp -r $sourceDir/* $destDir/
"$exePath" &
rm "\$0"
''';
    await File(scriptPath).writeAsString(script);
    await Process.start('bash', [scriptPath], mode: ProcessStartMode.detached);
  }

  static Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  static void _showUpdateDialog(
    BuildContext context,
    String appStoreUrl, {
    Map<String, dynamic>? desktopRelease,
  }) {
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
                  desktopRelease != null
                      ? 'A new version (${desktopRelease['version']}) is available. It will be downloaded and installed automatically.'
                      : 'A new version of the app is available. Please update to get the latest features and improvements.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                ),
                const SizedBox(height: AppSizes.lg),
                Row(
                  children: [
                    if (desktopRelease != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            "Later",
                            style: TextStyle(color: AppColors.primary),
                          ),
                        ),
                      ),
                    if (desktopRelease != null) const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          if (desktopRelease != null) {
                            Navigator.of(context).pop();
                            AppSnackbar.showInfo(
                              context,
                              'Downloading update...',
                            );
                            UpdateService.downloadAndApplyUpdate(
                              context,
                              desktopRelease,
                            );
                          } else {
                            final url = Uri.parse(appStoreUrl);
                            if (await canLaunchUrl(url)) {
                              await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                            Navigator.of(context).pop();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Update Now",
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
