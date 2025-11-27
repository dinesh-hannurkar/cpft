import 'package:cpft/features/webshare/presentation/widgets/qr_image_section.dart';
import 'package:cpft/features/webshare/presentation/widgets/qr_link_chip.dart';
import 'package:cpft/features/webshare/presentation/widgets/received_file_item.dart';
import 'package:cpft/features/webshare/presentation/widgets/upload_progress.dart';
import 'package:cpft/features/webshare/presentation/widgets/uploading_file_item.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_action_button.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../utils/network_utils.dart';
import '../../../features/home/presentation/widgets/network_banner.dart';
import '../services/webshare_service.dart';
import '../services/web_server.dart';

/// Main screen for web share functionality
class WebShareScreen extends StatefulWidget {
  final String deviceName;
  final String? customServiceName;
  final dynamic discoveryService;

  const WebShareScreen({
    super.key,
    required this.deviceName,
    this.customServiceName,
    this.discoveryService,
  });

  @override
  State<WebShareScreen> createState() => _WebShareScreenState();
}

class _WebShareScreenState extends State<WebShareScreen>
    with TickerProviderStateMixin {
  late WebShareService _webShareService;
  String? _serverUrl;
  bool _sendMode = true; // true = Send, false = Receive
  String? _networkName;

  // Track files currently being uploaded
  final Map<String, UploadProgress> _uploadProgress = {};

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
      customServiceName: widget.customServiceName,
      onFileUploadProgress: (filename, received, total) {
        if (!mounted) return;
        debugPrint(
          '[WebShareScreen] Upload progress: $filename - $received/$total bytes',
        );
        setState(() {
          _uploadProgress[filename] = UploadProgress(
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
          SnackBar(
            content: Text(
              'File received: $filename',
              style: const TextStyle(color: Colors.white),
            ),
          ),
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

    // Check if web server is already running and handle accordingly
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final portInUse = await WebServer.isPortInUse();
      if (portInUse) {
        // Port is in use, assume server is running externally
        debugPrint(
          '[WebShareScreen] Port 8080 already in use, assuming server is running',
        );
        // Create a dummy WebServer instance that reports as running
        _webShareService = WebShareService(
          deviceName: widget.deviceName,
          customServiceName: widget.customServiceName,
          onFileUploadProgress: (filename, received, total) {
            if (!mounted) return;
            debugPrint(
              '[WebShareScreen] Upload progress: $filename - $received/$total bytes',
            );
            setState(() {
              _uploadProgress[filename] = UploadProgress(
                filename: filename,
                received: received,
                total: total,
                startedAt:
                    _uploadProgress[filename]?.startedAt ?? DateTime.now(),
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
              SnackBar(
                content: Text(
                  'File received: $filename',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          },
        );
        _webShareService.setExternalServerRunning();
        // Get the URL for the existing server
        _webShareService.getServerUrl().then((url) {
          if (mounted) setState(() => _serverUrl = url);
        });
      } else {
        // Port is free, proceed with normal initialization
        _webShareService = WebShareService(
          deviceName: widget.deviceName,
          customServiceName: widget.customServiceName,
          onFileUploadProgress: (filename, received, total) {
            if (!mounted) return;
            debugPrint(
              '[WebShareScreen] Upload progress: $filename - $received/$total bytes',
            );
            setState(() {
              _uploadProgress[filename] = UploadProgress(
                filename: filename,
                received: received,
                total: total,
                startedAt:
                    _uploadProgress[filename]?.startedAt ?? DateTime.now(),
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
              SnackBar(
                content: Text(
                  'File received: $filename',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          },
        );

        // Auto-start the web server
        _toggleWebServer();
      }
    });

    // Initialize network name
    _initializeNetworkName();
  }

  Future<void> _initializeNetworkName() async {
    try {
      final networkName = await NetworkUtils.getWifiName();
      if (mounted) {
        setState(() {
          _networkName = networkName;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _networkName = 'Not Connected';
        });
      }
    }
  }

  Future<void> _toggleWebServer() async {
    if (_webShareService.isRunning) {
      await _webShareService.stopWebServer();
      setState(() {
        _serverUrl = null;
      });
    } else {
      final success = await _webShareService.startWebServer();

      if (success && mounted) {
        final url = await _webShareService.getServerUrl();
        setState(() {
          _serverUrl = url;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Web Share started. Access: $url',
              style: const TextStyle(color: Colors.white),
            ),
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
          const SnackBar(
            content: Text(
              'Failed to start Web Share',
              style: TextStyle(color: Colors.white),
            ),
          ),
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
        SnackBar(
          content: Text(
            'Shared file: ${result.files.first.name}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  // Test method to discover HTTP services
  Future<void> _testDiscoverServices() async {
    debugPrint('[WebShareScreen] 🔍 Testing service discovery...');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Discovering services... Check debug logs',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );

    final services = await _webShareService.discoverHttpServices();

    debugPrint(
      '[WebShareScreen] 📡 Discovery complete. Found ${services.length} services',
    );
    for (var service in services) {
      debugPrint('[WebShareScreen] Service: ${service['instance']}');
      debugPrint('[WebShareScreen]   - URL: ${service['url']}');
      debugPrint('[WebShareScreen]   - IP URL: ${service['ipUrl']}');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Found ${services.length} services. Check logs for details',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
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
                      color: Colors.black.withValues(alpha: 0.10),
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
                                color: Colors.black.withValues(alpha: 0.05),
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
                      // Debug: Test discovery button
                      IconButton(
                        onPressed: _testDiscoverServices,
                        icon: const Icon(Icons.search, size: 20),
                        tooltip: 'Test Service Discovery',
                        color: AppColors.secondary,
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
                            _serverUrl?.contains('localhost') == true
                                ? 'Web share started (local access only - no network connection)'
                                : 'Open this link on any device to start sharing.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppColors.greyDark,
                                  fontWeight: FontWeight.w500,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSizes.sm),
                          // QR (with loading until hostname)
                          Builder(
                            builder: (context) {
                              final hostname = _webShareService.actualHostname;
                              if (hostname == null || hostname.isEmpty) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 150,
                                      height: 150,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.05,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: Colors.blue.shade50,
                                        ),
                                      ),
                                      child: const SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Preparing QR link...',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.greyDark,
                                            fontWeight: FontWeight.w500,
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                );
                              }
                              return QrImageSection(
                                webShareService: _webShareService,
                              );
                            },
                          ),
                          const SizedBox(height: AppSizes.sm),
                          // Hostname link chip (shows loading until hostname)
                          QrLinkChip(webShareService: _webShareService),
                          // Network connection status
                          NetworkBanner(networkName: _networkName),
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
                        if (ok == true) {
                          await _webShareService.stopWebServer();
                          if (mounted) {
                            Navigator.pop(context);
                          }
                        }
                      },
                      backgroundColor: const Color(0xFFFDF1F1),
                      textColor: AppColors.red,
                      borderColor: AppColors.white,
                      shadowColor: AppColors.red.withValues(alpha: 0.2),
                      icon: Icons.stop_circle,
                    ),
                  ),
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
          : AppColors.greyDark.withValues(alpha: 0),
      shadowColor: active
          ? AppColors.primary.withValues(alpha: 0.1)
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
              'No files shared yet.',
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
              onAction: (context) => _webShareService.removeSharedFile(f.id),
              actionIcon: Icons.delete_forever,
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
          ..._uploadProgress.values.map(
            (progress) => UploadingFileItem(progress),
          ),
          // Then add received files
          ...receivedFiles.map((file) => ReceivedFileItem(file)),
        ];

        if (allItems.isEmpty) {
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
          itemCount: allItems.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final item = allItems[i];
            if (item is UploadingFileItem) {
              return _buildUploadingFileCard(item.progress);
            } else if (item is ReceivedFileItem) {
              final receivedFile = item.file;
              return _buildFileCard(
                receivedFile.filename,
                receivedFile.sizeBytes,
                receivedFile.receivedAt,
                onTap: () async {
                  try {
                    await OpenFilex.open(receivedFile.path);
                  } catch (_) {}
                },
                onAction: (context) async {
                  final box = context.findRenderObject() as RenderBox?;
                  final position =
                      box?.localToGlobal(Offset.zero) ?? Offset.zero;
                  final size = box?.size ?? Size.zero;
                  await Share.shareXFiles(
                    [XFile(receivedFile.path)],
                    sharePositionOrigin: Rect.fromLTWH(
                      position.dx,
                      position.dy,
                      size.width,
                      size.height,
                    ),
                  );
                },
                actionIcon: Icons.download,
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

  Widget _buildUploadingFileCard(UploadProgress progress) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: null, // No action for uploading files
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.blue.withValues(alpha: 0.08),
        highlightColor: Colors.blue.withValues(alpha: 0.04),
        hoverColor: Colors.blue.withValues(alpha: 0.03),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
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
                                    ? _extensionTrim(
                                        progress.filename.split('.').last,
                                      )
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
                              value: progress.isIndeterminate
                                  ? null
                                  : progress.progress,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progress.isIndeterminate
                                    ? Colors.blue.shade400
                                    : AppColors.primary,
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
    Function(BuildContext)? onAction,
    IconData? actionIcon,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.blue.withValues(alpha: 0.08),
        highlightColor: Colors.blue.withValues(alpha: 0.04),
        hoverColor: Colors.blue.withValues(alpha: 0.03),
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
                color: Colors.black.withValues(alpha: 0.05),
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
                  if (onAction != null)
                    Builder(
                      builder: (buttonContext) => IconButton(
                        icon: Icon(
                          actionIcon ?? Icons.delete_forever,
                          color: actionIcon == Icons.download
                              ? AppColors.primary
                              : const Color(0xFFD32F2F),
                          size: 22,
                        ),
                        onPressed: () => onAction.call(buttonContext),
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

  @override
  void dispose() {
    _fileIconPulse?.dispose();
    _fileIconTimer?.cancel();
    _webShareService.dispose();
    super.dispose();
  }
}

abstract class FileListItem {}
