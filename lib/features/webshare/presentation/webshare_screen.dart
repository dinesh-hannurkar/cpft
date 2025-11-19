import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
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

class _WebShareScreenState extends State<WebShareScreen>
    with TickerProviderStateMixin {
  late WebShareService _webShareService;
  bool _isStarting = false;
  String? _serverUrl;
  bool _sendMode = true; // true = Send, false = Receive

  // Track files currently being uploaded
  final Map<String, _UploadProgress> _uploadProgress = {};

  // Floating button icon cycle
  final List<IconData> _fileIcons = const [
    Icons.text_snippet,
    Icons.broken_image,
    Icons.gif,
    Icons.audiotrack,
    Icons.video_file,
    Icons.image,
    Icons.picture_as_pdf,
    Icons.archive,
    Icons.attach_file,
  ];
  int _fileIconIndex = 0;
  bool _slideFromLeft = true;
  AnimationController? _fileIconPulse;
  Timer? _fileIconTimer;

  @override
  void initState() {
    super.initState();
    _webShareService = WebShareService(
      deviceName: widget.deviceName,
      onFileUploadProgress: (filename, received, total) {
        if (!mounted) return;
        debugPrint('[WebShareScreen] Upload progress: $filename - $received/$total bytes');
        setState(() {
          _uploadProgress[filename] = _UploadProgress(
            filename: filename,
            received: received,
            total: total,
            startedAt: _uploadProgress[filename]?.startedAt ?? DateTime.now(),
          );
        });
      },
      onFileUploadComplete: (filename, savedPath) {
        if (!mounted) return;
        debugPrint('[WebShareScreen] Upload complete: $filename');

        // Delay progress removal to ensure user sees completion
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() {
              _uploadProgress.remove(filename);
            });
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File received: $filename', style: const TextStyle(color: Colors.white))),
        );
      },
    );

    // Setup pulse animation for the floating file icon and cycle icons
    _fileIconPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _fileIconTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _fileIconIndex = (_fileIconIndex + 1) % _fileIcons.length;
          _slideFromLeft = !_slideFromLeft; // alternate direction each swap
        });
      });
    });
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
            content: Text('Web Share started. Access: $url', style: const TextStyle(color: Colors.white)),
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
          const SnackBar(content: Text('Failed to start Web Share', style: TextStyle(color: Colors.white))),
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
        SnackBar(content: Text('Shared file: ${result.files.first.name}', style: const TextStyle(color: Colors.white))),
      );
    }
  }

  Widget _buildFileTaglineBar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: _pickAndShareFile,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFEFF7FF), Color(0xFFDFF0FF)],
              ),
              border: const Border(top: BorderSide(color: Color(0xFFCCE4F6))),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [AppColors.primary, AppColors.skyBlue],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(Rect.fromLTWH(0, 0, constraints.maxWidth, 20)),
                  blendMode: BlendMode.srcIn,
                  child: Text(
                    'Share files via web—pick and upload instantly.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 16,
          top: -24,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _pickAndShareFile,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB3E5FC), Color(0xFF81D4FA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _fileIconPulse!,
                      builder: (context, child) {
                        final scale = Tween<double>(begin: 0.96, end: 1.06)
                            .animate(
                              CurvedAnimation(
                                parent: _fileIconPulse!,
                                curve: Curves.easeInOut,
                              ),
                            )
                            .value;
                        return Transform.scale(
                          scale: scale,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 380),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, anim) {
                              final isOutgoing =
                                  anim.status == AnimationStatus.reverse;
                              final offsetTween = isOutgoing
                                  ? Tween<Offset>(
                                      begin: Offset.zero,
                                      end: Offset(
                                        _slideFromLeft ? 0.35 : -0.35,
                                        0.0,
                                      ),
                                    )
                                  : Tween<Offset>(
                                      begin: Offset(
                                        _slideFromLeft ? -0.35 : 0.35,
                                        0.0,
                                      ),
                                      end: Offset.zero,
                                    );
                              final curved = CurvedAnimation(
                                parent: anim,
                                curve: Curves.easeOutCubic,
                                reverseCurve: Curves.easeInCubic,
                              );
                              return FadeTransition(
                                opacity: curved,
                                child: SlideTransition(
                                  position: curved.drive(offsetTween),
                                  child: child,
                                ),
                              );
                            },
                            child: ShaderMask(
                              key: ValueKey<int>(_fileIconIndex),
                              shaderCallback: (rect) => const LinearGradient(
                                colors: [Color(0xFF2F80ED), Color(0xFF56CCF2)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(rect),
                              child: Icon(
                                _fileIcons[_fileIconIndex],
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg * 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                  child: Row(
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
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
                ),
                const SizedBox(height: AppSizes.md),
                if (_webShareService.isRunning) ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
                  if (_webShareService.isRunning && _sendMode) ...[
                    const SizedBox(height: AppSizes.md),
                    _buildFileTaglineBar(),
                  ],
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
                  // const SizedBox(height: AppSizes.md),
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
      floatingActionButton: null,
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
            return _buildFileCard(
              f.filename,
              f.sizeBytes,
              f.sharedAt,
              onDelete: () => _webShareService.removeSharedFile(f.id),
            );
          },
        );
      },
    );
  }

  Widget _buildReceiveMode() {
    return ValueListenableBuilder<List<ReceivedFile>>(
      valueListenable: _webShareService.receivedFiles,
      builder: (_, receivedFiles, __) {
        final allItems = [
          // Add uploading files first
          ..._uploadProgress.values.map((progress) => _UploadingFileItem(progress)),
          // Then add received files
          ...receivedFiles.map((file) => _ReceivedFileItem(file)),
        ];

        if (allItems.isEmpty) {
          return Center(
            child: Text(
              'No files received yet. Upload from browser.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.greyLight),
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.separated(
          itemCount: allItems.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final item = allItems[i];
            if (item is _UploadingFileItem) {
              return _buildUploadingFileCard(item.progress);
            } else if (item is _ReceivedFileItem) {
              final receivedFile = item.file;
              final index = receivedFiles.indexOf(receivedFile);
              return _buildFileCard(
                receivedFile.filename,
                receivedFile.sizeBytes,
                receivedFile.receivedAt,
                onTap: () async {
                  try {
                    await OpenFilex.open(receivedFile.path);
                  } catch (_) {}
                },
                onDelete: () async {
                  try {
                    await File(receivedFile.path).delete();
                  } catch (_) {}
                  final list = [..._webShareService.receivedFiles.value];
                  list.removeAt(index);
                  _webShareService.receivedFiles.value = list;
                },
              );
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  String _extensionTrim(String ext) {
    ext = ext.trim();
    if (ext.length > 6) ext = ext.substring(0, 6);
    return ext.toUpperCase();
  }

  String _fmtBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
  }

  Widget _buildFileIcon(String name) {
    final lower = name.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    IconData icon;
    Color fg;
    Color bg;

    const imageExt = {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
      'svg',
      'heic',
      'heif',
    };
    const videoExt = {'mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'};
    const audioExt = {'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'opus'};
    const pdfExt = {'pdf'};
    const archiveExt = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2'};
    const docExt = {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'csv', 'txt'};

    if (imageExt.contains(ext)) {
      icon = Icons.image;
      fg = const Color(0xFF1E88E5);
      bg = const Color(0xFFE3F2FD);
    } else if (videoExt.contains(ext)) {
      icon = Icons.videocam;
      fg = const Color(0xFF6A1B9A);
      bg = const Color(0xFFF3E5F5);
    } else if (audioExt.contains(ext)) {
      icon = Icons.audiotrack;
      fg = const Color(0xFF00897B);
      bg = const Color(0xFFE0F2F1);
    } else if (pdfExt.contains(ext)) {
      icon = Icons.picture_as_pdf;
      fg = const Color(0xFFD32F2F);
      bg = const Color(0xFFFDECEA);
    } else if (archiveExt.contains(ext)) {
      icon = Icons.archive;
      fg = const Color(0xFF5D4037);
      bg = const Color(0xFFEFEBE9);
    } else if (docExt.contains(ext)) {
      icon = Icons.description;
      fg = const Color(0xFF1565C0);
      bg = const Color(0xFFE3F2FD);
    } else if (ext == 'apk') {
      icon = Icons.android;
      fg = const Color(0xFF2E7D32);
      bg = const Color(0xFFE8F5E9);
    } else {
      icon = Icons.insert_drive_file;
      fg = const Color(0xFF455A64);
      bg = const Color(0xFFECEFF1);
    }

    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: fg),
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

  Widget _buildUploadingFileCard(_UploadProgress progress) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: null, // No action for uploading files
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.blue.withOpacity(0.08),
        highlightColor: Colors.blue.withOpacity(0.04),
        hoverColor: Colors.blue.withOpacity(0.03),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.blue.shade50),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildFileIcon(progress.filename),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFBBDEFB),
                                ),
                              ),
                              child: Text(
                                progress.filename.contains('.')
                                    ? _extensionTrim(progress.filename.split('.').last)
                                    : 'FILE',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1565C0),
                                  letterSpacing: .5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                progress.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  progress.isIndeterminate
                                      ? '${_fmtBytes(progress.received)} uploaded'
                                      : '${_fmtBytes(progress.received)} / ${_fmtBytes(progress.total)}',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                if (!progress.isIndeterminate)
                                  Text(
                                    '${(progress.progress! * 100).toInt()}%',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: progress.isIndeterminate ? null : progress.progress,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progress.isIndeterminate ? Colors.blue.shade400 : AppColors.primary,
                              ),
                              minHeight: progress.isIndeterminate ? 6 : 4,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileCard(
    String filename,
    int sizeBytes,
    DateTime timestamp, {
    VoidCallback? onTap,
    VoidCallback? onDelete,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.blue.withOpacity(0.08),
        highlightColor: Colors.blue.withOpacity(0.04),
        hoverColor: Colors.blue.withOpacity(0.03),
        mouseCursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSizes.md),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.blue.shade50),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildFileIcon(filename),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFBBDEFB),
                                ),
                              ),
                              child: Text(
                                filename.contains('.')
                                    ? _extensionTrim(filename.split('.').last)
                                    : 'FILE',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1565C0),
                                  letterSpacing: .5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              _fmtBytes(sizeBytes),
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(timestamp),
                              style: const TextStyle(
                                color: Colors.black38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_forever,
                        color: Color(0xFFD32F2F),
                        size: 22,
                      ),
                      onPressed: onDelete,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fileIconPulse?.dispose();
    _fileIconTimer?.cancel();
    super.dispose();
  }
}

class _UploadProgress {
  final String filename;
  final int received;
  final int total;
  final DateTime startedAt;

  _UploadProgress({
    required this.filename,
    required this.received,
    required this.total,
    required this.startedAt,
  });

  double? get progress => total > 0 ? received / total : null;
  bool get isIndeterminate => total <= 0;
  bool get isComplete => received >= total && total > 0;
}

abstract class _FileListItem {}

class _UploadingFileItem extends _FileListItem {
  final _UploadProgress progress;
  _UploadingFileItem(this.progress);
}

class _ReceivedFileItem extends _FileListItem {
  final ReceivedFile file;
  _ReceivedFileItem(this.file);
}
