import 'dart:async';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/logging/app_logger.dart';
import 'dart:io';
import 'package:fylooo/features/webshare/presentation/web_file_manager_screen.dart';
import 'package:fylooo/widgets/device_count.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';
import '../shared/widgets/dialog_helpers.dart' as app_dialog;
import '../shared/widgets/app_confirm_dialog.dart';
import '../services/discovery_service.dart';
import '../features/chat/presentation/chat_screen.dart';
import 'package:file_picker/file_picker.dart';

class DeviceDiscoveryScreen extends StatefulWidget {
  final String deviceName;

  const DeviceDiscoveryScreen({super.key, required this.deviceName});

  @override
  State<DeviceDiscoveryScreen> createState() => _DeviceDiscoveryScreenState();
}

class _DeviceDiscoveryScreenState extends State<DeviceDiscoveryScreen> {
  late DiscoveryService _discoveryService;
  final bool _isInitialized = false;
  bool _isRefreshing = false;
  final Map<String, String> _discoveredDevices = {};
  // Track pending incoming prompts to avoid duplicates
  final Set<String> _pendingIncoming = {};
  // Track web uploads in progress
  final Map<String, _WebUpload> _activeWebUploads = {};

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _discoveryService = DiscoveryService(
      alias: widget.deviceName,
      deviceModel: Platform.operatingSystem,
      port: 53317,
    );
  }

  void _onWebUploadProgress(String filename, int received, int total) {
    AppLogger.v(
      '[DeviceDiscovery] Upload progress: $filename - $received/$total bytes (${(received / total * 100).toStringAsFixed(1)}%)',
      tag: 'DiscoveryUI',
    );
    if (!mounted) return;

    setState(() {
      _activeWebUploads[filename] = _WebUpload(
        filename: filename,
        bytesReceived: received,
        totalBytes: total,
        startTime: _activeWebUploads[filename]?.startTime ?? DateTime.now(),
      );
    });
  }

  void _onIncomingRequest(
    String deviceName,
    String ipAddress,
    int port,
    Future<void> Function() accept,
    Future<void> Function() decline,
  ) async {
    if (_pendingIncoming.contains(deviceName)) return;
    _pendingIncoming.add(deviceName);
    await _handleIncomingConnectionUI(
      deviceName,
      ipAddress,
      port,
      accept,
      decline,
    );
  }

  Future<void> _handleIncomingConnectionUI(
    String deviceName,
    String ipAddress,
    int port,
    Future<void> Function() accept,
    Future<void> Function() decline,
  ) async {
    if (!mounted) return;

    // If you prefer auto-open, you can short-circuit here by pushing without dialog.
    // For now, show a prompt so user can accept/decline.
    final result = await app_dialog.showAppDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: 'Incoming chat request',
        content: Text('$deviceName wants to chat.'),
        cancelLabel: 'Decline',
        confirmLabel: 'Accept',
      ),
    );

    _pendingIncoming.remove(deviceName);

    if (result == true && mounted) {
      // Accept the socket and then open chat
      await accept();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            deviceName: deviceName,
            ipAddress: ipAddress,
            port: port,
            myDeviceName: widget.deviceName,
            connectionManager: _discoveryService.connectionManager!,
          ),
        ),
      );
    } else if (result == false) {
      // Declined: close the socket
      await decline();
    }
  }

  Future<void> _refreshDiscovery() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _discoveredDevices.clear();
    });

    try {
      AppLogger.d(
        'Refresh triggered - clearing devices and scanning',
        tag: 'DiscoveryUI',
      );

      // Clear the discovery service's device list
      _discoveryService.clearDevices();

      // Wait a bit for the clear to propagate
      await Future.delayed(const Duration(milliseconds: 300));

      // Force a re-announcement (this will work on Android/macOS, not iOS)
      await _discoveryService.announce();

      // On iOS, Bonjour is continuously running, so we just need to wait
      // for devices to be re-discovered from the ongoing Bonjour discovery
      // and incoming multicast messages
      if (Platform.isIOS) {
        AppLogger.d(
          'iOS: Waiting for Bonjour re-discovery...',
          tag: 'DiscoveryUI',
        );
        // Give Bonjour time to trigger discovery events
        await Future.delayed(const Duration(milliseconds: 1500));
      } else {
        // On other platforms, multicast announcements will trigger discoveries
        await Future.delayed(const Duration(milliseconds: 800));
      }

      AppLogger.i(
        'Refresh complete - found ${_discoveredDevices.length} devices',
        tag: 'DiscoveryUI',
      );
    } catch (e) {
      AppLogger.w('Refresh error: $e', tag: 'DiscoveryUI', error: e);
      if (mounted) {
        AppSnackbar.showError(context, 'Refresh failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _openWebFileManager() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            WebFileManagerScreen(discoveryService: _discoveryService),
      ),
    );
  }

  Future<void> _showWebLinkDialog() async {
    try {
      // Start web server if not running
      if (!_discoveryService.isWebServerRunning) {
        final success = await _discoveryService.startWebServer(port: 80);
        if (!success) {
          if (!mounted) return;
          AppSnackbar.showError(context, 'Failed to start web server');
          return;
        }
      }

      // Get web link
      final webLink = await _discoveryService.getWebLink();
      if (webLink == null) {
        if (!mounted) return;
        AppSnackbar.showWarning(
          context,
          'Unable to generate web link. Check network connection.',
        );
        return;
      }

      if (!mounted) return;

      // Show dialog with web link (consistent styling)
      await app_dialog.showAppDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.web, color: Colors.blue),
                    SizedBox(width: 12),
                    Text(
                      'Web Browser Access',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Anyone on the same network can access this device via web browser:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          webLink,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'Copy link',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: webLink));
                          AppSnackbar.showSuccess(
                            context,
                            'Link copied to clipboard!',
                            duration: const Duration(seconds: 2),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '📱 Share this link via email, chat, or QR code to let others send you files from their browser.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await _discoveryService.stopWebServer();
                          if (context.mounted) Navigator.of(ctx).pop();
                        },
                        child: const Text('Stop & Close'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _shareFileToWeb();
                        },
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Share File'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      // TODO: Add QR code generation
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'QR code feature coming soon!',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Show QR'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      AppLogger.w('Error showing web link: $e', tag: 'DiscoveryUI', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareFileToWeb() async {
    try {
      // Ensure web server is running
      if (!_discoveryService.isWebServerRunning) {
        final success = await _discoveryService.startWebServer();
        if (!success) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please start web server first',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }

      // Pick file
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not access file',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
        return;
      }

      // Add file to web server
      final fileId = _discoveryService.shareFileViaWeb(file.path!, file.name);

      if (fileId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to share file. Is web server running?',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ ${file.name} is now available for download via web!',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'View Link',
            textColor: Colors.white,
            onPressed: _showWebLinkDialog,
          ),
        ),
      );
    } catch (e) {
      AppLogger.w(
        'Error sharing file to web: $e',
        tag: 'DiscoveryUI',
        error: e,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    // Disable wakelock when leaving the screen
    WakelockPlus.disable();

    _discoveryService.removeIncomingRequestListener(_onIncomingRequest);
    _discoveryService.removeWebProgressListener(_onWebUploadProgress);
    _discoveryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openWebFileManager,
            tooltip: 'Web File Manager',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshDiscovery,
            tooltip: 'Refresh device search',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // VPN Warning Banner (iOS only)
              if (_isInitialized &&
                  _discoveryService.isVpnDetected &&
                  Platform.isIOS)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.orange.shade100,
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange.shade900,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'VPN Detected',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'iOS blocks multicast when VPN is active. Please disconnect VPN in Settings.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Status badges
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // This Device Info Card
                    Card(
                      elevation: 1,
                      color: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.smartphone,
                              color: Colors.blue.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'This Device',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.deviceName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Status badges row - scrollable to prevent overflow
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildStatusBadge(
                            icon: _isInitialized ? Icons.wifi : Icons.wifi_off,
                            label: _isInitialized
                                ? 'Discovering'
                                : 'Initializing',
                            color: _isInitialized
                                ? AppColors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(
                            icon: Icons.link,
                            label: 'Ready to connect',
                            color: _isInitialized
                                ? AppColors.green
                                : AppColors.greyLight,
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(
                            icon: Icons.screen_lock_portrait,
                            label: 'Screen on',
                            color: AppColors.skyBlue,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Device count
              DeviceCount(
                discoveredDevices: _discoveredDevices,
                isRefreshing: _isRefreshing,
              ),

              const SizedBox(height: 16),

              // Device list
              Expanded(
                child: _discoveredDevices.isEmpty
                    ? _buildEmptyState()
                    : _buildDeviceList(),
              ),
            ],
          ),

          // Web upload progress overlay
          if (_activeWebUploads.isNotEmpty)
            Positioned(
              bottom: 80,
              left: 16,
              right: 16,
              child: _buildUploadProgressCard(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showWebLinkDialog,
        icon: const Icon(Icons.web),
        label: const Text('Web Link'),
        tooltip: 'Share web link for browser access',
      ),
    );
  }

  Widget _buildUploadProgressCard() {
    return Card(
      elevation: 8,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_upload, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Receiving from Web',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '${_activeWebUploads.length} file(s)',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._activeWebUploads.values.map((upload) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            upload.filename,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(upload.progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: upload.progress,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      upload.formattedProgress,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices_other, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _isInitialized ? 'No devices found' : 'Initializing discovery...',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          if (_isInitialized)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48.0),
              child: Text(
                'Make sure other devices are running this app on the same WiFi network',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _discoveredDevices.length,
      itemBuilder: (context, index) {
        final deviceName = _discoveredDevices.keys.elementAt(index);
        final ipAddress = _discoveredDevices[deviceName]!;
        return _buildDeviceCard(deviceName, ipAddress);
      },
    );
  }

  Widget _buildDeviceCard(String deviceName, String ipAddress) {
    // Extract device type from name (e.g., "iPhone-xxx", "Mac-xxx", "Android-xxx")
    final deviceInfo = _parseDeviceName(deviceName);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      child: InkWell(
        onTap: () => _onDeviceSelected(deviceName, ipAddress),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: deviceInfo['color'].withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: deviceInfo['color'].withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  deviceInfo['icon'],
                  color: deviceInfo['color'],
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            deviceInfo['displayName'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Platform badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: deviceInfo['color'].withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: deviceInfo['color'].withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            deviceInfo['platform'],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: deviceInfo['color'],
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        // Device ID badge (if available)
                        if (deviceInfo['deviceId'] != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fingerprint,
                                  size: 10,
                                  color: Colors.grey[700],
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  deviceInfo['deviceId'],
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.wifi, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          ipAddress,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  /// Parse device name to extract platform and display information
  Map<String, dynamic> _parseDeviceName(String deviceName) {
    AppLogger.v('Parsing device name: "$deviceName"', tag: 'DiscoveryUI');

    IconData icon = Icons.devices;
    Color color = Colors.blue;
    String platform = 'Unknown';
    String displayName = deviceName;
    String? deviceId;

    // Extract device ID if present (last 4 digits after last hyphen)
    final parts = deviceName.split('-');
    AppLogger.v('Split into ${parts.length} parts: $parts', tag: 'DiscoveryUI');

    if (parts.length > 1 &&
        parts.last.length == 4 &&
        int.tryParse(parts.last) != null) {
      deviceId = parts.last;
      AppLogger.d('Extracted device ID: $deviceId', tag: 'DiscoveryUI');
      // Rebuild device name without the ID for display
      final nameWithoutId = parts.sublist(0, parts.length - 1).join('-');
      deviceName = nameWithoutId;
      AppLogger.v('Device name without ID: "$deviceName"', tag: 'DiscoveryUI');
    } else {
      AppLogger.w(
        'No valid device ID found (last: "${parts.last}" len=${parts.last.length})',
        tag: 'DiscoveryUI',
      );
    }

    if (deviceName.startsWith('iPhone-')) {
      icon = Icons.phone_iphone;
      color = const Color(0xFF000000); // Apple Black
      platform = 'iOS';
      displayName = deviceName.substring(7); // Remove "iPhone-" prefix
    } else if (deviceName.startsWith('Android-')) {
      icon = Icons.phone_android;
      color = const Color(0xFF3DDC84); // Android Green
      platform = 'Android';
      displayName = deviceName.substring(8); // Remove "Android-" prefix
    } else if (deviceName.startsWith('Mac-')) {
      icon = Icons.laptop_mac;
      color = const Color(0xFF0071E3); // Apple Blue
      platform = 'macOS';
      displayName = deviceName.substring(4); // Remove "Mac-" prefix
    } else if (deviceName.startsWith('Windows-')) {
      icon = Icons.desktop_windows;
      color = const Color(0xFF0078D4); // Windows Blue
      platform = 'Windows';
      displayName = deviceName.substring(8); // Remove "Windows-" prefix
    } else if (deviceName.startsWith('Linux-')) {
      icon = Icons.computer;
      color = const Color(0xFFFF6600); // Linux Orange
      platform = 'Linux';
      displayName = deviceName.substring(6); // Remove "Linux-" prefix
    } else if (deviceName.startsWith('cpft-')) {
      // Legacy format - try to determine from hostname
      displayName = deviceName.substring(5); // Remove "cpft-" prefix
      platform = 'Legacy';
      color = Colors.grey;
    }

    // Clean up display name
    displayName = displayName.replaceAll('-', ' ').replaceAll('_', ' ').trim();

    // Capitalize each word
    if (displayName.isNotEmpty) {
      displayName = displayName
          .split(' ')
          .map((word) {
            if (word.isEmpty) return word;
            return word[0].toUpperCase() + word.substring(1).toLowerCase();
          })
          .join(' ');
    }

    return {
      'icon': icon,
      'color': color,
      'platform': platform,
      'displayName': displayName,
      'deviceId': deviceId,
    };
  }

  void _onDeviceSelected(String deviceName, String ipAddress) {
    AppLogger.d(
      'Device selected: $deviceName at $ipAddress',
      tag: 'DiscoveryUI',
    );

    // Get connection manager from discovery service
    final connectionManager = _discoveryService.connectionManager;
    if (connectionManager == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connection service not ready. Please wait...',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if already connected to this device
    final existingConnection = connectionManager.getConnection(deviceName);
    if (existingConnection != null && existingConnection.isConnected) {
      AppLogger.d(
        'Already connected to $deviceName, navigating to existing chat',
        tag: 'DiscoveryUI',
      );
      // Navigate to existing connection without creating new one
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            deviceName: deviceName,
            ipAddress: ipAddress,
            port: 53318,
            myDeviceName: widget.deviceName,
            connectionManager: connectionManager,
            initialDeviceId: deviceName,
          ),
        ),
      );
      return;
    }

    // Navigate to connection screen (will create new connection)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          deviceName: deviceName,
          ipAddress: ipAddress,
          port: 53318, // Use P2P port
          myDeviceName: widget.deviceName,
          connectionManager: connectionManager,
        ),
      ),
    );
  }
}

/// Model class for tracking active web uploads
class _WebUpload {
  final String filename;
  final int bytesReceived;
  final int totalBytes;
  final DateTime startTime;

  _WebUpload({
    required this.filename,
    required this.bytesReceived,
    required this.totalBytes,
    required this.startTime,
  });

  double get progress => totalBytes > 0 ? bytesReceived / totalBytes : 0.0;

  String get formattedProgress {
    final mb = (bytesReceived / 1024 / 1024).toStringAsFixed(1);
    final totalMb = (totalBytes / 1024 / 1024).toStringAsFixed(1);
    return '$mb MB / $totalMb MB';
  }
}
