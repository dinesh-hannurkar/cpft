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
import 'package:fylooo/shared/widgets/dialog_helpers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class UpdateService {
  static final ValueNotifier<Map<String, dynamic>?> updateNotifier =
      ValueNotifier(null);
  static final ValueNotifier<double?> downloadProgress = ValueNotifier(null);
  static final ValueNotifier<String> updateStatus = ValueNotifier(
    'Downloading Update',
  );
  static String _baseUrl = 'http://192.168.1.179:3000';
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

      final releasesUri = Uri.parse('http://192.168.1.179:3000/releases.json');
      _baseUrl =
          '${releasesUri.scheme}://${releasesUri.host}${releasesUri.hasPort ? ':${releasesUri.port}' : ''}';

      final response = await http.get(releasesUri);

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
          : '$_baseUrl$updateUrl';

      // Show Progress Dialog
      if (context.mounted) {
        debugPrint('Showing progress dialog...');
        _showProgressDialog(context);
      }

      // 1. Download ZIP with progress tracking
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(fullUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) throw Exception('Download failed');

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final List<int> bytes = [];

      await for (var chunk in response.stream) {
        bytes.addAll(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          downloadProgress.value = receivedBytes / totalBytes;
        }
      }

      client.close();

      final tempDir = await getTemporaryDirectory();
      final zipFile = File(p.join(tempDir.path, 'update.zip'));
      await zipFile.writeAsBytes(bytes);

      // 2. Extract in Background Isolate
      updateStatus.value = 'Extracting Update...';
      debugPrint('Starting extraction in isolate...');
      final updateDir = Directory(p.join(tempDir.path, 'fylooo_update'));
      if (await updateDir.exists()) await updateDir.delete(recursive: true);
      await updateDir.create(recursive: true);

      await compute(_extractZipInIsolate, {
        'bytes': bytes,
        'path': updateDir.path,
      });
      debugPrint('Extraction complete.');

      // 3. Prepare Patch Script
      final currentExe = Platform.resolvedExecutable;
      final installDir = p.dirname(currentExe);

      if (Platform.isWindows) {
        await _applyWindowsUpdate(updateDir.path, installDir, currentExe);
      } else if (Platform.isLinux) {
        await _applyLinuxUpdate(updateDir.path, installDir, currentExe);
      }

      updateStatus.value = 'Restarting App...';
      debugPrint('Update process complete. Finalizing shutdown...');

      // Delay so user can see "Restarting App"
      await Future.delayed(const Duration(milliseconds: 2000));

      debugPrint('Calling hard exit(0).');
      exit(0);
    } catch (e) {
      debugPrint('Update failed: $e');
      downloadProgress.value = null;
      if (context.mounted) {
        Navigator.of(context).pop(); // Ensure progress dialog is closed
        AppSnackbar.showError(context, 'Update failed: $e');
      }
    }
  }

  static Future<void> _extractZipInIsolate(Map<String, dynamic> args) async {
    final bytes = args['bytes'] as List<int>;
    final path = args['path'] as String;

    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final filename = file.name;
      final fullPath = p.join(path, filename);

      if (file.isFile) {
        final data = file.content as List<int>;
        File(fullPath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory(fullPath).createSync(recursive: true);
      }
    }
  }

  static Future<void> _applyWindowsUpdate(
    String sourceDir,
    String destDir,
    String exePath,
  ) async {
    final parentDir = p.dirname(sourceDir);
    final scriptPath = p.join(parentDir, 'patch.bat');
    final logPath = p.join(parentDir, 'patch.log');
    final exeName = p.basename(exePath);

    // Robust Windows Script using tasklist wait loop and robocopy
    final script =
        '''
@echo off
setlocal enabledelayedexpansion
echo Starting update for $exeName... > "$logPath"

:: Wait for app to exit by checking tasklist
set WAIT_COUNT=0
:WAIT_LOOP
set /a WAIT_COUNT+=1
echo Checking if $exeName is still running (Attempt %WAIT_COUNT%)... >> "$logPath"
tasklist /fi "IMAGENAME eq $exeName" | find /i "$exeName" > nul
if %ERRORLEVEL% equ 0 (
    if %WAIT_COUNT% leq 20 (
        timeout /t 1 /nobreak > nul
        goto WAIT_LOOP
    )
    echo Timeout waiting for $exeName to exit. >> "$logPath"
    exit /b 1
)
echo $exeName has exited. >> "$logPath"

set RETRY=0
:RETRY_LOOP
set /a RETRY+=1
echo Attempt !RETRY! to copy files... >> "$logPath"

:: Use robocopy for robust copying
robocopy "$sourceDir" "$destDir" /e /is /it /move /ndl /nfl /np /r:3 /w:2 >> "$logPath" 2>&1

if %ERRORLEVEL% LEQ 7 (
    echo Copy successful. >> "$logPath"
    start "" "$exePath"
    del "%~f0"
    exit
)

if !RETRY! LEQ 5 (
    echo Copy failed (Error %ERRORLEVEL%), retrying in 2s... >> "$logPath"
    timeout /t 2 /nobreak > nul
    goto RETRY_LOOP
)

echo Failed to update after 5 attempts. >> "$logPath"
pause
''';
    await File(scriptPath).writeAsString(script);

    // IMPORTANT: Use ProcessStartMode.detached NOT detachedWithStdio.
    // detachedWithStdio keeps stdio pipes OPEN, preventing Flutter from exiting.
    try {
      debugPrint('Spawning detached Windows patch script...');
      await Process.start('cmd', [
        '/c',
        scriptPath,
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      debugPrint('Failed to spawn Windows patch script: $e');
    }
  }

  static Future<void> _applyLinuxUpdate(
    String sourceDir,
    String destDir,
    String exePath,
  ) async {
    final parentDir = p.dirname(sourceDir);
    final scriptPath = p.join(parentDir, 'patch.sh');
    final logPath = p.join(parentDir, 'patch.log');
    final exeName = p.basename(exePath);

    // Robust Linux Script with pgrep wait loop
    final script =
        '''
#!/bin/bash
exec > "$logPath" 2>&1
echo "Starting Linux update for $exeName..."

# Wait for process to exit using pgrep
WAIT_COUNT=0
while pgrep -x "$exeName" > /dev/null; do
    WAIT_COUNT=\$((WAIT_COUNT+1))
    echo "Waiting for $exeName to exit (Attempt \$WAIT_COUNT)..."
    if [ \$WAIT_COUNT -gt 20 ]; then
        echo "Timeout waiting for $exeName to exit."
        exit 1
    fi
    sleep 1
done

echo "$exeName has exited."

MAX_RETRIES=5
RETRY=0

while [ \$RETRY -lt \$MAX_RETRIES ]; do
    RETRY=\$((RETRY+1))
    echo "Attempt \$RETRY to copy files..."
    
    # -a for archive, -v for verbose, -f for force
    cp -rvf "$sourceDir"/* "$destDir"/
    
    if [ \$? -eq 0 ]; then
        echo "Copy successful."
        chmod +x "$exePath"
        "$exePath" &
        rm "\$0"
        exit 0
    fi
    
    echo "Copy failed, retrying in 2s..."
    sleep 2
done

echo "Failed to update after \$MAX_RETRIES attempts."
''';
    await File(scriptPath).writeAsString(script);
    await Process.run('chmod', ['+x', scriptPath]);

    // IMPORTANT: Use ProcessStartMode.detached NOT detachedWithStdio.
    // detachedWithStdio keeps stdio pipes OPEN, preventing Flutter from exiting.
    try {
      debugPrint('Spawning detached Linux patch script...');
      await Process.start('bash', [
        scriptPath,
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      debugPrint('Failed to spawn Linux patch script: $e');
    }
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
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppColors.white,
          surfaceTintColor: AppColors.white,
          insetPadding: const EdgeInsets.all(AppSizes.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 10,
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
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
  } // Closing brace for _showUpdateDialog

  static void _showProgressDialog(BuildContext context) {
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppColors.white,
          surfaceTintColor: AppColors.white,
          insetPadding: const EdgeInsets.all(AppSizes.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 10,
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: ValueListenableBuilder<double?>(
              valueListenable: downloadProgress,
              builder: (context, progress, _) {
                final percent = progress != null ? (progress * 100).toInt() : 0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: updateStatus,
                      builder: (context, status, _) {
                        return Text(
                          status,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSizes.lg),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$percent%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.primary,
                          ),
                        ),
                        const Text(
                          'Updating Fylooo',
                          style: TextStyle(
                            color: AppColors.greyDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.md),
                    Text(
                      'Please do not close the application.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.greyDark.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
