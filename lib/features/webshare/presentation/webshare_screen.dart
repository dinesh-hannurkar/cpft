import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_action_button.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../services/webshare_service.dart';

/// Main screen for web share functionality
class WebShareScreen extends StatefulWidget {
  final String deviceName;
  final dynamic discoveryService; // TODO: Import proper type

  const WebShareScreen({
    super.key,
    required this.deviceName,
    this.discoveryService,
  });

  @override
  State<WebShareScreen> createState() => _WebShareScreenState();
}

class _WebShareScreenState extends State<WebShareScreen> {
  late WebShareService _webShareService;
  bool _isStarting = false;
  String? _serverUrl;
  bool _sendMode = true; // true = Send, false = Receive

  @override
  void initState() {
    super.initState();
    _webShareService = WebShareService(
      deviceName: widget.deviceName,
      onFileUploadProgress: (filename, received, total) {
        // Handle upload progress if needed
      },
      onFileUploadComplete: (filename, savedPath) {
        // Handle upload complete if needed
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('File received: $filename')));
      },
    );
  }

  @override
  void dispose() {
    _webShareService.dispose();
    super.dispose();
  }

  Future<void> _toggleWebServer() async {
    if (_webShareService.isRunning) {
      await _webShareService.stopWebServer();
      setState(() => _serverUrl = null);
    } else {
      setState(() => _isStarting = true);
      final success = await _webShareService.startWebServer();
      setState(() => _isStarting = false);

      if (success && mounted) {
        final url = await _webShareService.getServerUrl();
        setState(() => _serverUrl = url);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Web Share started. Access: $url'),
            action: SnackBarAction(
              label: 'Copy',
              onPressed: () {
                // TODO: Implement copy to clipboard
              },
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start Web Share')),
        );
      }
    }
  }

  Future<void> _pickAndShareFile() async {
    if (!_webShareService.isRunning) return;
    final result = await FilePicker.platform.pickFiles(withReadStream: false);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    final id = await _webShareService.shareFile(File(path));
    if (!mounted) return;
    if (id != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shared file: ${result.files.first.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE9F5FA), Color.fromARGB(255, 255, 255, 255)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          size: 20,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.md),
                    Text(
                      'Link Share',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (!_webShareService.isRunning)
                      TextButton(
                        onPressed: _isStarting ? null : _toggleWebServer,
                        child: _isStarting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Start'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                if (_webShareService.isRunning) ...[
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'Open this link on any device to start sharing.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppColors.greyDark,
                                fontWeight: FontWeight.w500,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSizes.sm),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {},
                              child: Text(
                                _serverUrl ?? 'Loading...',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                    ),
                              ),
                            ),
                            // const SizedBox(width: AppSizes.sm),
                            // AppActionButton(
                            //   text: 'Copy',
                            //   onPressed: () {
                            //     if (_serverUrl != null) {
                            //       Clipboard.setData(ClipboardData(text: _serverUrl!));
                            //       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied URL to clipboard')));
                            //     }
                            //   },
                            //   backgroundColor: AppColors.primary,
                            //   textColor: AppColors.white,
                            //   borderColor: AppColors.primary,
                            //   shadowColor: AppColors.primary.withOpacity(0.12),
                            //   width: 100,
                            //   height: 38,
                            // ),
                          ],
                        ),
                        const SizedBox(height: AppSizes.sm),
                        ValueListenableBuilder<int>(
                          valueListenable: _webShareService.connectedClients,
                          builder: (_, count, __) => Text(
                            '$count users connected',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.greyLight),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  // Mode toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildModeButton(true, 'Send'),
                      const SizedBox(width: AppSizes.md),
                      _buildModeButton(false, 'Receive'),
                    ],
                  ),
                  const SizedBox(height: AppSizes.md),
                  Expanded(
                    child: _sendMode ? _buildSendMode() : _buildReceiveMode(),
                  ),
                  const SizedBox(height: AppSizes.md),
                  Center(
                    child: AppActionButton(
                      text: 'Stop Sharing',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => const AppConfirmDialog(
                            title: 'Stop sharing?',
                            content: Text(
                              'Stop the web server and close connections?',
                            ),
                            confirmLabel: 'Stop',
                            cancelLabel: 'Cancel',
                            destructive: true,
                          ),
                        );
                        if (ok == true) _toggleWebServer();
                      },
                      backgroundColor: const Color(0xFFFDF1F1),
                      textColor: AppColors.red,
                      borderColor: AppColors.white,
                      shadowColor: AppColors.red.withValues(alpha: 0.2),
                      icon: Icons.stop_circle,
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                ] else ...[
                  Expanded(
                    child: Center(
                      child: Text(
                        'Start web share to allow browser-based transfers',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.greyLight,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _webShareService.isRunning && _sendMode
          ? FloatingActionButton(
              onPressed: _pickAndShareFile,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: AppColors.white),
            )
          : null,
    );
  }

  Widget _buildModeButton(bool mode, String label) {
    final active = _sendMode == mode;
    return AppActionButton(
      text: label,
      onPressed: () => setState(() => _sendMode = mode),
      backgroundColor: active ? AppColors.secondary : Colors.transparent,
      textColor: AppColors.primary,
      borderColor: active
          ? AppColors.white
          : AppColors.greyDark.withOpacity(0.25),
      shadowColor: active
          ? AppColors.primary.withOpacity(0.1)
          : Colors.transparent,
      icon: mode ? Icons.north_east : Icons.south_east,
      width: 145,
      // height: 40,
    );
  }

  Widget _buildSendMode() {
    return ValueListenableBuilder<List<SharedFile>>(
      valueListenable: _webShareService.sharedFiles,
      builder: (_, files, __) {
        if (files.isEmpty) {
          return Center(
            child: Text(
              'No files shared yet. Tap + to add.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.greyLight),
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.separated(
          itemCount: files.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final f = files[i];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${f.humanSize}',
                          style: TextStyle(
                            color: AppColors.greyLight,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_forever,
                      color: AppColors.red,
                      size: 22,
                    ),
                    onPressed: () => _webShareService.removeSharedFile(f.id),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReceiveMode() {
    return ValueListenableBuilder<List<ReceivedFile>>(
      valueListenable: _webShareService.receivedFiles,
      builder: (_, files, __) {
        if (files.isEmpty) {
          return Center(
            child: Text(
              'No files received yet. Upload from browser.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.greyLight),
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.separated(
          itemCount: files.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final f = files[i];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.download_done, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${f.humanSize} • ${_formatTime(f.receivedAt)}',
                          style: TextStyle(
                            color: AppColors.greyLight,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete,
                      color: AppColors.red,
                      size: 20,
                    ),
                    onPressed: () async {
                      try {
                        await File(f.path).delete();
                      } catch (_) {}
                      final list = [..._webShareService.receivedFiles.value];
                      list.removeAt(i);
                      _webShareService.receivedFiles.value = list;
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.open_in_new,
                      color: AppColors.primary,
                    ),
                    onPressed: () async {
                      try {
                        await OpenFilex.open(f.path);
                      } catch (_) {}
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
