import 'package:cpft/features/webshare/presentation/widgets/qr_image_section.dart';
import 'package:cpft/features/webshare/presentation/widgets/qr_link_chip.dart';
import 'package:cpft/features/webshare/presentation/widgets/received_file_item.dart';
import 'package:cpft/features/webshare/presentation/widgets/upload_progress.dart';
import 'package:cpft/features/webshare/presentation/widgets/uploading_file_item.dart';
import 'package:cpft/features/webshare/services/webrtc_file_transfer_service.dart';
import 'package:flutter/material.dart';
import 'package:cpft/features/webshare/services/web_download.dart';
import 'package:cpft/features/webshare/services/web_received_cache.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'dart:io' if (dart.library.html) 'package:cpft/features/webshare/services/io_stub.dart';
import 'dart:async';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../shared/widgets/app_action_button.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';
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
  late WebRTCFileTransferService _webrtcService;
  String? _serverUrl;
  bool _sendMode = true; // true = Send, false = Receive
  bool _transferMode = true; // true = HTTP, false = WebRTC
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

    // On web, default to WebRTC mode (HTTP server not available)
    if (kIsWeb) {
      _transferMode = false; // false = WebRTC
    }

    // Initialize WebRTC service
    _webrtcService = WebRTCFileTransferService(
      onConnectionEstablished: () {
        if (!mounted) return;
        debugPrint('[WebShareScreen] 🎉 WebRTC Connection Established!');
        setState(() {}); // Update UI
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'WebRTC Connected!',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'You are now connected on the local network and ready to transfer files.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
                if (_webrtcService.roomId != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Room: ${_webrtcService.roomId}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
      onConnectionLost: () {
        if (!mounted) return;
        debugPrint('[WebShareScreen] ❌ WebRTC Connection Lost!');
        setState(() {}); // Update UI
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'WebRTC connection lost',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      },
      onFileReceiveProgress: (filename, received, total) {
        if (!mounted) return;
        // debugPrint(
        //   '[WebShareScreen] WebRTC receive progress: $filename - $received/$total bytes',
        // );
        setState(() {
          _uploadProgress[filename] = UploadProgress(
            filename: filename,
            received: received,
            total: total,
            startedAt: _uploadProgress[filename]?.startedAt ?? DateTime.now(),
          );
        });
      },
      onFileReceiveComplete: (filename, savedPath) {
        if (!mounted) return;
        debugPrint(
          '[WebShareScreen] WebRTC receive complete: $filename at $savedPath',
        );

        if (kIsWeb) {
          // Service now provides a cache-backed path for web (web-parts:* or fallback)
          if (savedPath.startsWith('web-parts:')) {
            final id = savedPath.substring('web-parts:'.length);
            final total = WebReceivedCache.length(id);
            _webShareService.addWebRTCReceivedFile(filename, savedPath, total);
          } else if (savedPath.startsWith('web-bytes:')) {
            final id = savedPath.substring('web-bytes:'.length);
            final data = WebReceivedCache.get(id);
            final len = data?.length ?? 0;
            _webShareService.addWebRTCReceivedFile(filename, savedPath, len);
          } else {
            final bytes = _webrtcService.receivedFileBytes;
            final name = _webrtcService.receivedFileName ?? filename;
            final cacheId = WebReceivedCache.put(name, bytes);
            _webShareService.addWebRTCReceivedFile(name, 'web-bytes:$cacheId', bytes.length);
          }
          // Do not auto-download on web; user will tap Download
        } else {
          // Get file size from saved path (native platforms)
          final file = File(savedPath);
          final fileSize = file.lengthSync();
          _webShareService.addWebRTCReceivedFile(filename, savedPath, fileSize);
        }

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
              'File received via WebRTC: $filename',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      },
      onFileSendProgress: (filename, sent, total) {
        if (!mounted) return;
        // debugPrint(
        //   '[WebShareScreen] WebRTC send progress: $filename - $sent/$total bytes',
        // );
        setState(() {
          _uploadProgress[filename] = UploadProgress(
            filename: filename,
            received: sent,
            total: total,
            startedAt: _uploadProgress[filename]?.startedAt ?? DateTime.now(),
          );
        });
      },
      onFileSendComplete: (filename, filePath, fileSize) {
        if (!mounted) return;
        debugPrint('[WebShareScreen] WebRTC send complete: $filename');

        // Add to shared files list with a unique ID
        final fileId = 'webrtc_${DateTime.now().millisecondsSinceEpoch}';
        _webShareService.addWebRTCSharedFile(fileId, filename, fileSize);

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
              'File sent via WebRTC: $filename',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      },
      onFileTransferError: (filename, reason, duringSend) {
        if (!mounted) return;
        debugPrint('[WebShareScreen] ❌ WebRTC transfer error: $filename | $reason');
        setState(() {
          _uploadProgress.remove(filename);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Transfer ${duringSend ? 'send' : 'receive'} failed for $filename: $reason',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red.shade700,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                if (duringSend) {
                  // For web, user can re-pick file; on native, open picker too
                  _pickAndShareFile();
                }
              },
            ),
          ),
        );
      },
    );

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

  String _guessMime(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'zip':
        return 'application/zip';
      case 'gz':
      case 'tgz':
        return 'application/gzip';
      case 'apk':
        return 'application/vnd.android.package-archive';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _saveToDevicePicker(String filename, String sourcePath) async {
    try {
      final params = SaveFileDialogParams(sourceFilePath: sourcePath, fileName: filename);
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
    // Check if we can share files
    if (_transferMode) {
      // HTTP mode
      if (!_webShareService.isRunning) return;
    } else {
      // WebRTC mode
      if (!_webrtcService.connectionEstablished.value) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please connect to a peer first',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
        return;
      }
    }

    final result = await FilePicker.platform.pickFiles(
      withReadStream: false,
      withData: kIsWeb, // ensure bytes are available on web
    );
    if (result == null || result.files.isEmpty) return;
    final selected = result.files.first;
    String? path;
    if (!kIsWeb) {
      // On web, accessing PlatformFile.path throws. Never touch it there.
      path = selected.path;
    }

    try {
      if (_transferMode) {
        // HTTP mode - share via web server
        // Avoid static type mismatch on web by passing dynamic
        final id = await _webShareService.shareFile((File(path!)) as dynamic);
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
      } else {
        // WebRTC mode - send directly to peer
        if (kIsWeb) {
          final bytes = selected.bytes;
          final name = selected.name;
          if (bytes == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not read file bytes in browser',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            );
            return;
          }
          await _webrtcService.sendFileBytes(name, bytes);
        } else {
          if (path == null) return; // safety on native
          await _webrtcService.sendFile(path);
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sending ${selected.name} via WebRTC...',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to send file: ${e.toString().replaceFirst('Exception: ', '')}',
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
                    _transferMode
                        ? 'Share files via web—pick and upload instantly.'
                        : _webrtcService.connectionEstablished.value
                        ? 'Tap to send files directly to your peer via WebRTC.'
                        : 'Connect to a peer to start sending files via WebRTC.',
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
                if ((_transferMode && _webShareService.isRunning) ||
                    (!_transferMode &&
                        _webrtcService.connectionEstablished.value)) ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Column(
                        children: [
                          Text(
                            _transferMode
                                ? (_serverUrl?.contains('localhost') == true
                                      ? 'Web share started (local access only - no network connection)'
                                      : 'Open this link on any device to start sharing.')
                                : 'WebRTC peer-to-peer connection established.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppColors.greyDark,
                                  fontWeight: FontWeight.w500,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSizes.sm),
                          // QR (with loading until hostname) - only for HTTP mode
                          if (_transferMode) ...[
                            Builder(
                              builder: (context) {
                                final hostname =
                                    _webShareService.actualHostname;
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                          ],
                          // Network connection status
                          NetworkBanner(networkName: _networkName),
                          const SizedBox(height: AppSizes.sm),
                          // Local network readiness indicator for WebRTC
                          if (!_transferMode) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (_networkName != null &&
                                        _networkName != 'Not Connected')
                                    ? Colors.blue.shade50
                                    : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      (_networkName != null &&
                                          _networkName != 'Not Connected')
                                      ? Colors.blue.shade200
                                      : Colors.orange.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    (_networkName != null &&
                                            _networkName != 'Not Connected')
                                        ? Icons.wifi
                                        : Icons.wifi_off,
                                    color:
                                        (_networkName != null &&
                                            _networkName != 'Not Connected')
                                        ? Colors.blue.shade700
                                        : Colors.orange.shade700,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    (_networkName != null &&
                                            _networkName != 'Not Connected')
                                        ? 'Connected to local network'
                                        : 'No network connection',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color:
                                              (_networkName != null &&
                                                  _networkName !=
                                                      'Not Connected')
                                              ? Colors.blue.shade700
                                              : Colors.orange.shade700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSizes.sm),
                          ],
                          if (_transferMode) ...[
                            ValueListenableBuilder<int>(
                              valueListenable:
                                  _webShareService.connectedClients,
                              builder: (_, count, __) => Text(
                                '$count users connected',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: AppColors.greyLight),
                              ),
                            ),
                          ] else ...[
                            ValueListenableBuilder<bool>(
                              valueListenable:
                                  _webrtcService.connectionEstablished,
                              builder: (_, isConnected, __) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isConnected
                                      ? Colors.green.shade50
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isConnected
                                        ? Colors.green.shade200
                                        : Colors.grey.shade300,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isConnected
                                          ? Icons.check_circle
                                          : Icons.wifi_off,
                                      color: isConnected
                                          ? Colors.green
                                          : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            isConnected
                                                ? 'Connected & Ready'
                                                : 'Waiting for Connection',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: isConnected
                                                      ? Colors.green.shade800
                                                      : Colors.grey.shade700,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          if (isConnected) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'You can now send files to your peer',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        Colors.green.shade600,
                                                    fontSize: 11,
                                                  ),
                                            ),
                                            if (_webrtcService.roomId !=
                                                null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Room: ${_webrtcService.roomId}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          Colors.green.shade500,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                              ),
                                            ],
                                          ] else ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Join the same room on another device',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 11,
                                                  ),
                                            ),
                                            if (_webrtcService.roomId !=
                                                null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Current room: ${_webrtcService.roomId}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          Colors.grey.shade500,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  // Transfer mode toggle (HTTP vs WebRTC)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!kIsWeb) ...[
                        _buildTransferModeButton(true, 'HTTP'),
                        const SizedBox(width: AppSizes.sm),
                      ],
                      _buildTransferModeButton(false, 'WebRTC'),
                    ],
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
                  if (_sendMode &&
                      ((_transferMode && _webShareService.isRunning) ||
                          (!_transferMode &&
                              _webrtcService.connectionEstablished.value))) ...[
                    const SizedBox(height: AppSizes.md),
                    _buildFileTaglineBar(),
                  ],
                  const SizedBox(height: AppSizes.md),
                  Center(
                    child: AppActionButton(
                      text: _transferMode ? 'Stop Sharing' : 'Disconnect',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AppConfirmDialog(
                            title: _transferMode
                                ? 'Stop sharing?'
                                : 'Disconnect?',
                            content: Text(
                              _transferMode
                                  ? 'Stop the web server and close connections?'
                                  : 'Disconnect from WebRTC peer?',
                            ),
                            confirmLabel: _transferMode ? 'Stop' : 'Disconnect',
                            cancelLabel: 'Cancel',
                            destructive: true,
                          ),
                        );
                        if (ok == true) {
                          if (_transferMode) {
                            await _webShareService.stopWebServer();
                          } else {
                            await _webrtcService.disconnect();
                            setState(() {});
                          }
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
                        _transferMode
                            ? 'Start web share to allow browser-based transfers'
                            : 'Connect via WebRTC for peer-to-peer file transfers',
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
      floatingActionButton:
          ((_transferMode && !_webShareService.isRunning) ||
              (!_transferMode && !_webrtcService.connectionEstablished.value))
          ? FloatingActionButton.extended(
              onPressed: _transferMode
                  ? _toggleWebServer
                  : _startWebRTCConnection,
              label: Text(
                _transferMode ? 'Start HTTP Server' : 'Connect WebRTC',
              ),
              icon: Icon(_transferMode ? Icons.http : Icons.wifi_tethering),
              backgroundColor: AppColors.primary,
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
          : AppColors.greyDark.withValues(alpha: 0),
      shadowColor: active
          ? AppColors.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      icon: mode ? Icons.north_east : Icons.south_east,
      width: 145,
      // height: 40,
    );
  }

  Widget _buildTransferModeButton(bool mode, String label) {
    final active = _transferMode == mode;
    return AppActionButton(
      text: label,
      onPressed: () => setState(() => _transferMode = mode),
      backgroundColor: active ? AppColors.primary : Colors.transparent,
      textColor: active ? Colors.white : AppColors.primary,
      borderColor: active
          ? AppColors.white
          : AppColors.greyDark.withValues(alpha: 0.3),
      shadowColor: active
          ? AppColors.primary.withValues(alpha: 0.2)
          : Colors.transparent,
      icon: mode ? Icons.http : Icons.wifi_tethering,
      width: 130,
    );
  }

  Widget _buildSendMode() {
    return ValueListenableBuilder<List<SharedFile>>(
      valueListenable: _webShareService.sharedFiles,
      builder: (_, files, __) {
        // Combine uploading (progress) items with already shared files
        final allItems = [
          ..._uploadProgress.values.map((p) => UploadingFileItem(p)),
          ...files,
        ];

        if (allItems.isEmpty) {
          return Center(
            child: Text(
              'No files shared yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.greyLight,
              ),
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
            }

            final f = item as SharedFile;
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
                  if (kIsWeb && (receivedFile.path.startsWith('web-bytes:') || receivedFile.path.startsWith('web-parts:'))) {
                    // On web cached items, trigger the same action as the download button
                    try {
                      // Reuse the action handler
                      // ignore: use_build_context_synchronously
                      await Future.microtask(() => {});
                      // Call the same logic as onAction
                      // Note: onAction is non-null in this callsite
                      // ignore: unnecessary_lambdas
                      (context as BuildContext);
                      // Invoke the action using this context
                      // ignore: inference_failure_on_untyped_parameter
                      // ignore: avoid_dynamic_calls
                      // We directly duplicate the download logic below to avoid context quirks
                      final path = receivedFile.path;
                      if (path.startsWith('web-bytes:')) {
                        final id = path.substring('web-bytes:'.length);
                        final data = WebReceivedCache.get(id);
                        if (data != null) {
                          final ext = (receivedFile.filename.contains('.')
                              ? receivedFile.filename.split('.').last.toLowerCase()
                              : '');
                          final mime = _guessMime(ext);
                          WebDownload.saveBytes(receivedFile.filename, data, contentType: mime);
                          return;
                        }
                      } else if (path.startsWith('web-parts:')) {
                        final id = path.substring('web-parts:'.length);
                        final parts = WebReceivedCache.getParts(id);
                        if (parts != null) {
                          final ext = (receivedFile.filename.contains('.')
                              ? receivedFile.filename.split('.').last.toLowerCase()
                              : '');
                          final mime = _guessMime(ext);
                          WebDownload.saveParts(receivedFile.filename, parts, contentType: mime);
                          return;
                        }
                      }
                    } catch (_) {}
                    return;
                  }
                  try {
                    await OpenFilex.open(receivedFile.path);
                  } catch (_) {}
                },
                onAction: (context) async {
                  if (kIsWeb && receivedFile.path.startsWith('web-bytes:')) {
                    final id = receivedFile.path.substring('web-bytes:'.length);
                    final data = WebReceivedCache.get(id);
                    if (data != null) {
                      final ext = (receivedFile.filename.contains('.')
                          ? receivedFile.filename.split('.').last.toLowerCase()
                          : '');
                      final mime = _guessMime(ext);
                      WebDownload.saveBytes(receivedFile.filename, data, contentType: mime);
                      return;
                    }
                  }
                  if (kIsWeb && receivedFile.path.startsWith('web-parts:')) {
                    final id = receivedFile.path.substring('web-parts:'.length);
                    final parts = WebReceivedCache.getParts(id);
                    if (parts != null) {
                      final ext = (receivedFile.filename.contains('.')
                          ? receivedFile.filename.split('.').last.toLowerCase()
                          : '');
                      final mime = _guessMime(ext);
                      WebDownload.saveParts(receivedFile.filename, parts.cast(), contentType: mime);
                      return;
                    }
                  }
                  // Native: show actions - Open, Save to device…, Share
                  if (!kIsWeb) {
                    // ignore: use_build_context_synchronously
                    await showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (_) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.open_in_new),
                              title: const Text('Open'),
                              onTap: () async {
                                Navigator.of(context).pop();
                                try { await OpenFilex.open(receivedFile.path); } catch (_) {}
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.save_alt),
                              title: const Text('Save to device…'),
                              subtitle: const Text('Choose a location to save this file'),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _saveToDevicePicker(receivedFile.filename, receivedFile.path);
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
                                  [XFile(receivedFile.path)],
                                  sharePositionOrigin: Rect.fromLTWH(position.dx, position.dy, size.width, size.height),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                    return;
                  }
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
    // Use SI (decimal) units for display to match user expectations (KB=1000, MB=1000^2)
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1000 && unit < units.length - 1) {
      size /= 1000;
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
                            // Show transfer speed
                            ValueListenableBuilder<double>(
                              valueListenable: _webrtcService.transferSpeed,
                              builder: (context, speed, _) {
                                if (speed > 0) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${_fmtBytes(speed.toInt())}/s',
                                      style: TextStyle(
                                        color: Colors.blue.shade700,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
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
    _webrtcService.dispose();
    super.dispose();
  }

  Future<void> _startWebRTCConnection() async {
    if (mounted) {
      showAppBottomSheet(
        context: context,
        title: 'WebRTC Connection',
        subtitle: 'Connect with another device',
        maxHeightFactor: 0.85,
        showCloseButton: true,
        child: WebRTCConnectionBottomSheet(
          webrtcService: _webrtcService,
          onConnected: () {
            Navigator.pop(context);
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'WebRTC connected successfully!',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            );
          },
          onError: (error) {
            Navigator.pop(context);
            final errorMessage = error.replaceFirst('Exception: ', '');
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Connection Failed'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(errorMessage),
                    const SizedBox(height: 16),
                    const Text(
                      'Please ensure:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Signaling server is running at http://192.168.1.179:3000',
                    ),
                    const Text('• Both devices are on the same network'),
                    const Text('• Port 3000 is not blocked by firewall'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
  }
}

/// WebRTC Connection Bottom Sheet
class WebRTCConnectionBottomSheet extends StatefulWidget {
  final WebRTCFileTransferService webrtcService;
  final VoidCallback onConnected;
  final Function(String) onError;

  const WebRTCConnectionBottomSheet({
    super.key,
    required this.webrtcService,
    required this.onConnected,
    required this.onError,
  });

  @override
  State<WebRTCConnectionBottomSheet> createState() => _WebRTCConnectionBottomSheetState();
}

class _WebRTCConnectionBottomSheetState extends State<WebRTCConnectionBottomSheet> {
  final TextEditingController _peerIdController = TextEditingController();
  bool _isConnecting = false;
  bool _hasJoinedRoom = false;
  bool _isDiscovering = false;
  String? _currentRoomId;
  String? _networkName;
  String? _detectedHostIp;

  @override
  void initState() {
    super.initState();
    _checkNetworkStatus();
  }

  Future<void> _checkNetworkStatus() async {
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

  @override
  void dispose() {
    _peerIdController.dispose();
    super.dispose();
  }

  Future<void> _connectToPeer() async {
    // Check if local mode and if host
    final isLocal = widget.webrtcService.isLocalMode.value;
    final isHost = widget.webrtcService.isHostMode.value;
    
    // For host mode, room ID is auto-generated. For join mode, need manual entry.
    String roomId;
    if (isHost && isLocal) {
      // Host: room ID will be generated automatically with port
      roomId = ''; // Will be generated by startLocalHostAndConnect
    } else {
      // Join or remote mode: need room ID from user
      roomId = _peerIdController.text.trim();
      if (roomId.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please enter a room ID')));
        return;
      }

      // On web: auto-switch to local signaling if room ID encodes port (e.g., 1234-192-p8081)
      if (kIsWeb && !isLocal && RegExp(r"-p\d+").hasMatch(roomId)) {
        widget.webrtcService.setSignalingMode(useLocal: true);
        widget.webrtcService.setHostMode(false); // web cannot host local WS
      }
    }

    setState(() {
      _isConnecting = true;
      _currentRoomId = roomId;
    });

    try {
      setState(() {
        _isDiscovering = !isHost && isLocal; // Show discovery for join mode
      });
      
      if (isLocal) {
        if (isHost) {
          // Start as host and get generated room ID with port
          final generatedRoomId = await widget.webrtcService.startLocalHostAndConnect();
          if (mounted && generatedRoomId != null) {
            setState(() {
              _detectedHostIp = generatedRoomId; // Store the room ID
              _currentRoomId = generatedRoomId;
              _peerIdController.text = generatedRoomId; // Show in UI
              _isDiscovering = false;
            });
          }
        } else {
          // Join as client - automatic discovery with port extraction!
          await widget.webrtcService.connectToSignalingServer(roomId);
          if (mounted) {
            setState(() {
              _isDiscovering = false;
            });
          }
        }
      } else {
        // Use remote Socket.IO signaling
        await widget.webrtcService.connectToSignalingServer(roomId);
      }
      
      if (mounted) {
        setState(() {
          _hasJoinedRoom = true;
          _isConnecting = false;
          _isDiscovering = false;
        });
      }
      // Don't close dialog yet - wait for actual peer connection
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _hasJoinedRoom = false;
          _isDiscovering = false;
        });
      }
      widget.onError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Signaling Mode Toggle (hide on web - local mode not supported)
            if (!_hasJoinedRoom && !kIsWeb) ...[
              ValueListenableBuilder<bool>(
                valueListenable: widget.webrtcService.isLocalMode,
                builder: (context, isLocal, _) {
                  return Card(
                    color: isLocal ? Colors.blue.shade50 : Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isLocal ? Icons.wifi : Icons.cloud,
                                color: isLocal ? Colors.blue : Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Signaling Mode',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isLocal ? Colors.blue.shade900 : Colors.green.shade900,
                                ),
                              ),
                              const Spacer(),
                              Switch(
                                value: isLocal,
                                onChanged: (value) {
                                  widget.webrtcService.setSignalingMode(useLocal: value);
                                },
                                activeColor: Colors.blue,
                                inactiveThumbColor: Colors.green,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isLocal 
                              ? 'Local (WiFi/Hotspot) - No internet needed'
                              : 'Remote (Internet) - Works anywhere',
                            style: TextStyle(
                              fontSize: 12,
                              color: isLocal ? Colors.blue.shade700 : Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // Host/Join Mode Toggle (only for local mode)
              ValueListenableBuilder<bool>(
                valueListenable: widget.webrtcService.isLocalMode,
                builder: (context, isLocal, _) {
                  if (!isLocal) return const SizedBox.shrink();
                  return ValueListenableBuilder<bool>(
                    valueListenable: widget.webrtcService.isHostMode,
                    builder: (context, isHost, _) {
                      return Card(
                        color: isHost ? Colors.purple.shade50 : Colors.orange.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isHost ? Icons.router : Icons.link,
                                    color: isHost ? Colors.purple : Colors.orange,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Connection Role',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isHost ? Colors.purple.shade900 : Colors.orange.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(
                                      value: true,
                                      label: Text('Host', style: TextStyle(fontSize: 13)),
                                      icon: Icon(Icons.router, size: 18),
                                    ),
                                    ButtonSegment(
                                      value: false,
                                      label: Text('Join', style: TextStyle(fontSize: 13)),
                                      icon: Icon(Icons.link, size: 18),
                                    ),
                                  ],
                                  selected: {isHost},
                                  onSelectionChanged: (Set<bool> selected) {
                                    widget.webrtcService.setHostMode(selected.first);
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isHost 
                                  ? 'Create the room and share your IP with peers'
                                  : 'Join an existing room - host IP auto-detected',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isHost ? Colors.purple.shade700 : Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            // Step 1: Network Check
            _buildStatusIndicator(
              icon: (_networkName != null && _networkName != 'Not Connected')
                  ? Icons.wifi
                  : Icons.wifi_off,
              text: 'Network Check',
              status: (_networkName != null && _networkName != 'Not Connected')
                  ? 'Connected to local network'
                  : 'No network connection',
              isComplete:
                  _networkName != null && _networkName != 'Not Connected',
              color: (_networkName != null && _networkName != 'Not Connected')
                  ? Colors.green
                  : Colors.orange,
            ),
            const SizedBox(height: 12),
            // Signaling Backend Indicator
            _buildStatusIndicator(
              icon: Icons.cloud,
              text: 'Signaling Backend',
              status: widget.webrtcService.useFirestoreSignaling
                ? 'Firestore (Firebase)'
                : (widget.webrtcService.isLocalMode.value
                  ? 'Local WebSocket'
                  : 'Socket.IO Remote'),
              isComplete: true,
              color: Colors.indigo,
            ),
            const SizedBox(height: 12),
            // Discovery status (for join mode)
            if (_isDiscovering) ...[
              _buildStatusIndicator(
                icon: Icons.search,
                text: 'Finding Host',
                status: 'Scanning local network for WebRTC host...',
                isComplete: false,
                color: Colors.blue,
                isLoading: true,
              ),
              const SizedBox(height: 12),
            ],
            // Step 2: Room Input/Joined
            if (!_hasJoinedRoom) ...[
              const Text(
                'Enter a room ID that both devices will join:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _peerIdController,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: kIsWeb ? 'Enter room ID (e.g., "1234")' : 'Enter room ID (e.g., "1234-192-p8081")',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  prefixIcon: const Icon(Icons.meeting_room, color: AppColors.primary),
                  helperText: 'Both devices must use the same room ID',
                  helperStyle: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                enabled: !_isConnecting,
                onSubmitted: (_) => _connectToPeer(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isConnecting
                          ? null
                          : () async {
                              setState(() => _isConnecting = true);
                              try {
                                // Ensure Firestore (remote) signaling for web sharing
                                widget.webrtcService.setSignalingMode(useLocal: false);
                                widget.webrtcService.setHostMode(false);
                                final id = await widget.webrtcService.createAutoRoomAndConnect(length: 4, alphanumeric: false);
                                if (!mounted) return;
                                setState(() {
                                  _peerIdController.text = id;
                                  _currentRoomId = id;
                                  _hasJoinedRoom = true;
                                  _isConnecting = false;
                                });
                              } catch (e) {
                                if (!mounted) return;
                                setState(() => _isConnecting = false);
                                widget.onError(e.toString());
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to start web sharing: $e'),
                                    backgroundColor: Colors.red.shade700,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.wifi_tethering, size: 20),
                      label: const Text('Start Web Sharing (auto room)'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<bool>(
                valueListenable: widget.webrtcService.isHostMode,
                builder: (context, isHost, _) {
                  return SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isConnecting ? null : _connectToPeer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(isHost ? Icons.router : Icons.link, size: 24),
                      label: Text(
                        _isConnecting 
                            ? (isHost ? 'Starting Server...' : 'Joining Room...') 
                            : (isHost ? 'Start Hosting' : 'Join Room'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ] else ...[
              _buildStatusIndicator(
                icon: Icons.meeting_room,
                text: 'Room Joined',
                status: 'Room: $_currentRoomId',
                isComplete: true,
                color: Colors.green,
              ),
              const SizedBox(height: 12),
              // Show generated room ID if in local host mode
              if (_detectedHostIp != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    border: Border.all(color: Colors.purple.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.share, color: Colors.purple.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Share This Room ID',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Other devices on the same WiFi can join using this Room ID:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.purple.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.purple.shade200),
                              ),
                              child: SelectableText(
                                _detectedHostIp!,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              // Copy to clipboard
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('IP copied to clipboard')),
                              );
                            },
                            tooltip: 'Copy IP',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Step 3: Waiting for peer / Connected
              ValueListenableBuilder<bool>(
                valueListenable: widget.webrtcService.connectionEstablished,
                builder: (context, isConnected, _) {
                  if (isConnected) {
                    // Auto-close dialog after showing success
                    Future.delayed(const Duration(milliseconds: 1500), () {
                      if (mounted) {
                        widget.onConnected();
                      }
                    });
                  }
                  return _buildStatusIndicator(
                    icon: isConnected
                        ? Icons.check_circle
                        : Icons.hourglass_empty,
                    text: isConnected
                        ? 'Connected & Ready'
                        : 'Waiting for Connection',
                    status: isConnected
                        ? 'You can now send files to your peer'
                        : 'Join the same room on another device',
                    isComplete: isConnected,
                    color: isConnected ? Colors.green : Colors.blue,
                    isLoading: !isConnected,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator({
    required IconData icon,
    required String text,
    required String status,
    required bool isComplete,
    required Color color,
    bool isLoading = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          if (isComplete) Icon(Icons.check, color: color, size: 20),
        ],
      ),
    );
  }
}

abstract class FileListItem {}
