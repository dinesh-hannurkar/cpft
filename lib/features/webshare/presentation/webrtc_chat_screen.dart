import 'dart:async';
import 'dart:io' as io;
import 'package:cpft/utils/file_saver.dart';
import 'package:cpft/utils/mime_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/webshare/services/webrtc_file_transfer_service.dart';
import 'package:cpft/features/webshare/services/webshare_service.dart';
import 'package:cpft/features/webshare/services/web_download.dart';
import 'package:cpft/features/webshare/services/web_received_cache.dart';
import 'package:cpft/shared/widgets/primary_app_bar.dart';
import 'package:cpft/shared/widgets/back_button_chip.dart';
import 'package:cpft/features/home/presentation/widgets/settings_button.dart';
import 'package:cpft/features/chat/models/transfer_progress.dart';
import 'package:cpft/features/chat/presentation/widgets/transfer_progress_tile.dart';
import 'package:cpft/features/chat/presentation/widgets/message_input_bar.dart';
import 'package:cpft/features/chat/presentation/widgets/file_tagline_bar.dart';
import 'package:cpft/features/webshare/presentation/widgets/file_card.dart';
import 'package:cpft/features/webshare/services/file_action_handler.dart';

/// Chat-like screen for WebRTC file sharing
class WebRTCChatScreen extends StatefulWidget {
  final WebRTCFileTransferService webrtcService;
  final WebShareService? webShareService;
  final String roomId;
  final VoidCallback onDisconnect;

  const WebRTCChatScreen({
    super.key,
    required this.webrtcService,
    this.webShareService,
    required this.roomId,
    required this.onDisconnect,
  });

  @override
  State<WebRTCChatScreen> createState() => _WebRTCChatScreenState();
}

class _WebRTCChatScreenState extends State<WebRTCChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  final List<ChatMessage> _messages = [];
  bool _isConnected = true;
  int _lastKnownFileCount = 0;
  late VoidCallback _connectionListener;

  // Progress tracking for UI progress bars
  final Map<String, TransferProgress> _outgoingProgress = {};
  final Map<String, TransferProgress> _incomingProgress = {};

  // Floating button animation state
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

    // Clear received files for this WebRTC session to start fresh
    if (widget.webShareService != null) {
      widget.webShareService!.receivedFiles.value = [];
    }

    // Initialize the last known file count
    _lastKnownFileCount =
        widget.webShareService?.receivedFiles.value.length ?? 0;
    _setupListeners();
    // Removed: _addSystemMessage('Connected to room ${widget.roomId}');

    // Animation for file icon pulse + cycling
    _fileIconPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _fileIconTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _slideFromLeft = !_slideFromLeft;
        _fileIconIndex = (_fileIconIndex + 1) % _fileIcons.length;
      });
    });

    // Check focus
    _inputFocus.addListener(() => setState(() {}));
  }

  void _setupWebRTCCallbacks() {
    // Set up main WebRTC callbacks for connection management
    widget.webrtcService.onConnectionEstablished = () {
      if (!mounted) return;
      debugPrint('[WebRTCChatScreen] 🎉 WebRTC Connection Established!');
      setState(() {
        _isConnected = true;
      });
      // Removed: _addSystemMessage('Connected successfully');
    };

    widget.webrtcService.onConnectionLost = () {
      if (!mounted) return;
      debugPrint('[WebRTCChatScreen] ❌ WebRTC Connection Lost!');
      setState(() {
        _isConnected = false;
      });
      // Removed: _addSystemMessage('Connection lost');
    };

    // Set up file transfer callbacks
    widget.webrtcService.onFileReceiveProgress = (filename, received, total) {
      if (!mounted) return;
      // Update progress for incoming transfers
      setState(() {
        _incomingProgress.putIfAbsent('incoming_$filename', () => TransferProgress(name: filename, total: total));
        _incomingProgress['incoming_$filename']!.updateProgress(received.toDouble());
      });
    };

    widget.webrtcService.onFileSendProgress = (filename, sent, total) {
      if (!mounted) return;
      // Update progress for outgoing transfers
      setState(() {
        _outgoingProgress.putIfAbsent('outgoing_$filename', () => TransferProgress(name: filename, total: total));
        _outgoingProgress['outgoing_$filename']!.updateProgress(sent.toDouble());
      });
    };

    widget.webrtcService.onFileSendComplete = (filename, filePath, fileSize) {
      if (!mounted) return;
      debugPrint('[WebRTCChatScreen] WebRTC send complete: $filename');
      setState(() {
        _outgoingProgress.remove('outgoing_$filename');
      });
      // Removed: _addSystemMessage('Sent: $filename');
    };

    widget.webrtcService.onFileReceiveComplete = (filename, savedPath) {
      if (!mounted) return;
      debugPrint('[WebRTCChatScreen] WebRTC receive complete: $filename at $savedPath');
      setState(() {
        _incomingProgress.remove('incoming_$filename');
      });
      // Removed: _addSystemMessage('Received: $filename');
      _onWebRTCFileReceiveComplete(filename, savedPath);
    };

    widget.webrtcService.onFileTransferError = (filename, reason, duringSend) {
      if (!mounted) return;
      debugPrint('[WebRTCChatScreen] ❌ WebRTC transfer error: $filename | $reason');

      // Clean up progress on error
      setState(() {
        if (duringSend) {
          _outgoingProgress.remove('outgoing_$filename');
        } else {
          _incomingProgress.remove('incoming_$filename');
        }
      });
    };

    // Set up additional callbacks for chat updates
    widget.webrtcService.addFileReceiveCompleteListener(_onWebRTCFileReceiveComplete);

    // Listen for connection changes
    widget.webrtcService.connectionEstablished.addListener(_onConnectionChanged);
  }

  void _onConnectionChanged() {
    final isConnected = widget.webrtcService.connectionEstablished.value;
    if (!mounted) return;

    debugPrint('[WebRTCChatScreen] Connection state changed: $isConnected');
    setState(() {
      _isConnected = isConnected;
    });

    // Removed system messages
    // if (isConnected) {
    //   _addSystemMessage('Connected successfully');
    // } else {
    //   _addSystemMessage('Connection lost');
    // }
  }

  void _onWebRTCFileReceiveComplete(String filename, String savedPath) {
    if (!mounted) return;
    debugPrint('[WebRTCChatScreen] WebRTC receive complete: $filename at $savedPath');

    // Add file to WebShareService
    if (widget.webShareService != null) {
      if (kIsWeb) {
        // Web: handle cache-backed paths
        if (savedPath.startsWith('web-parts:')) {
          final id = savedPath.substring('web-parts:'.length);
          final total = WebReceivedCache.length(id);
          widget.webShareService!.addWebRTCReceivedFile(filename, savedPath, total);
        } else if (savedPath.startsWith('web-bytes:')) {
          final id = savedPath.substring('web-bytes:'.length);
          final data = WebReceivedCache.get(id);
          final len = data?.length ?? 0;
          widget.webShareService!.addWebRTCReceivedFile(filename, savedPath, len);
        } else {
          // Fallback: use service's received file data
          final bytes = widget.webrtcService.receivedFileBytes;
          final name = widget.webrtcService.receivedFileName ?? filename;
          final cacheId = WebReceivedCache.put(name, bytes);
          widget.webShareService!.addWebRTCReceivedFile(
            name,
            'web-bytes:$cacheId',
            bytes.length,
          );
        }
      } else {
        // Native: get file size from saved path
        try {
          final file = io.File(savedPath);
          final fileSize = file.lengthSync();
          widget.webShareService!.addWebRTCReceivedFile(filename, savedPath, fileSize);
        } catch (e) {
          debugPrint('[WebRTCChatScreen] Error getting file size: $e');
          // Fallback to expected size
          final fileSize = widget.webrtcService.lastExpectedFileSize;
          widget.webShareService!.addWebRTCReceivedFile(filename, savedPath, fileSize);
        }
      }
    }
  }

  void _setupListeners() {
    // Set up main WebRTC callbacks if not already set
    _setupWebRTCCallbacks();

    // Register additional progress callbacks for chat updates
    widget.webrtcService.addFileSendProgressListener(_onFileSendProgress);
    widget.webrtcService.addFileReceiveProgressListener(_onFileReceiveProgress);
    widget.webrtcService.addFileSendCompleteListener(_onFileSendComplete);
    widget.webrtcService.addFileReceiveCompleteListener(_onFileReceiveComplete);
    widget.webrtcService.addFileTransferErrorListener(_onFileTransferError);

    // Listen for received files
    if (widget.webShareService != null) {
      debugPrint('[WebRTCChatScreen] Setting up receivedFiles listener');
      debugPrint(
        '[WebRTCChatScreen] Current receivedFiles count: ${widget.webShareService!.receivedFiles.value.length}',
      );
      widget.webShareService!.receivedFiles.addListener(
        _onReceivedFilesChanged,
      );
      debugPrint('[WebRTCChatScreen] Listener added successfully');
    } else {
      debugPrint(
        '[WebRTCChatScreen] WARNING: webShareService is null, cannot add listener',
      );
    }

    // Listen for connection lost
    _connectionListener = () {
      if (widget.webrtcService.connectionEstablished.value == false &&
          mounted) {
        setState(() {
          _isConnected = false;
        });
        // Removed: _addSystemMessage('Connection lost');
      }
    };
    widget.webrtcService.connectionEstablished.addListener(_connectionListener);
  }

  void _onReceivedFilesChanged() {
    debugPrint('[WebRTCChatScreen] _onReceivedFilesChanged triggered');
    if (widget.webShareService == null) {
      debugPrint('[WebRTCChatScreen] webShareService is null, skipping');
      return;
    }
    final files = widget.webShareService!.receivedFiles.value;
    debugPrint(
      '[WebRTCChatScreen] Current files count: ${files.length}, last known: $_lastKnownFileCount',
    );

    if (files.length > _lastKnownFileCount &&
        mounted &&
        _lastKnownFileCount >= 0) {
      // New files have been received (files are prepended to the list)
      final newFileCount = files.length - _lastKnownFileCount;

      debugPrint(
        '[WebRTCChatScreen] Adding $newFileCount new files from the beginning of the list',
      );

      // Since files are prepended, new files are at the beginning (indices 0 to newFileCount-1)
      final newFiles = files.sublist(0, newFileCount);
      for (final file in newFiles) {
        debugPrint(
          '[WebRTCChatScreen] Adding file card: ${file.filename}, size: ${file.sizeBytes}',
        );
        _addFileMessage(file.filename, file.sizeBytes, false);
      }

      _lastKnownFileCount = files.length;
    } else if (files.length < _lastKnownFileCount) {
      // Files were removed, reset counter
      debugPrint('[WebRTCChatScreen] Files removed, resetting counter');
      _lastKnownFileCount = files.length;
    }
  }

  void _onFileSendProgress(String filename, int sent, int total) {
    // Update current transfer state for progress tracking
    _addTransferProgressMessage(filename, sent, total);

    // Update progress map for UI progress bar
    setState(() {
      final transferId = 'outgoing_$filename';
      _outgoingProgress.putIfAbsent(
        transferId,
        () => TransferProgress(
          name: filename,
          total: total,
          mime: MimeUtils.guessMime(filename.split('.').last),
        ),
      );
      _outgoingProgress[transferId]!.updateProgress(sent.toDouble());
    });
  }

  void _onFileReceiveProgress(String filename, int received, int total) {
    debugPrint(
      '[WebRTCChatScreen] Receive progress: $filename - $received/$total bytes',
    );

    // For receiving, we can show progress too
    _addTransferProgressMessage('Receiving $filename', received, total);

    // Update incoming progress map for UI progress bar
    setState(() {
      final transferId = 'incoming_$filename';
      _incomingProgress.putIfAbsent(
        transferId,
        () => TransferProgress(
          name: filename,
          total: total,
          mime: MimeUtils.guessMime(filename.split('.').last),
        ),
      );
      _incomingProgress[transferId]!.updateProgress(received.toDouble());
    });
  }

  void _onFileSendComplete(String filename, String filePath, int fileSize) {
    // Clear transfer state

    // Clear progress map
    setState(() {
      _outgoingProgress.remove('outgoing_$filename');
    });

    // Mirror WebShareScreen behavior: record sent file in shared list if available
    final svc = widget.webShareService;
    if (svc != null) {
      final fileId = 'webrtc_${DateTime.now().millisecondsSinceEpoch}';
      svc.addWebRTCSharedFile(fileId, filename, fileSize);
    }
    // File card already shows sent status, no need for system message
  }

  void _onFileReceiveComplete(String filename, String savedPath) {
    // Note: WebShareService file addition is handled by the main callback
    // This listener callback only handles any additional chat UI updates

    // Clear incoming progress entry
    setState(() {
      _incomingProgress.remove('incoming_$filename');
    });
  }

  void _onFileTransferError(String filename, String reason, bool duringSend) {
    debugPrint(
      '[WebRTCChatScreen] Transfer error: $filename - $reason (during ${duringSend ? 'send' : 'receive'})',
    );

    // Clear transfer state
    // Removed: final action = duringSend ? 'sending' : 'receiving';
    // Removed: _addSystemMessage('Error $action $filename: $reason');
  }

  void _addTransferProgressMessage(String filename, int sent, int total) {
    // Progress shown in file cards, no system messages needed
  }

  void _addFileMessage(String filename, int fileSize, bool isSending) {
    debugPrint(
      '[WebRTCChatScreen] _addFileMessage called: filename=$filename, size=$fileSize, isSending=$isSending',
    );
    setState(() {
      _messages.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: filename,
          type: isSending ? MessageType.fileSent : MessageType.fileReceived,
          timestamp: DateTime.now(),
          fileSize: fileSize,
        ),
      );
    });
    debugPrint(
      '[WebRTCChatScreen] Message added. Total messages: ${_messages.length}',
    );
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb, // For web, we need the data
      );

      if (result != null && result.files.isNotEmpty) {
        for (final file in result.files) {
          // On web, path is unavailable. Check platform before accessing path.
          final hasData = kIsWeb
              ? file.bytes != null
              : (file.path != null || file.bytes != null);

          if (hasData) {
            // Add sending message to chat immediately
            _addFileMessage(file.name, file.size, true);

            try {
              // Match WebShareScreen behavior: use bytes on web, path on native
              if (kIsWeb) {
                final bytes = file.bytes;
                if (bytes == null) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not read file bytes in browser',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  }
                  continue;
                }
                await widget.webrtcService.sendFileBytes(file.name, bytes);
              } else {
                if (file.path != null) {
                  await widget.webrtcService.sendFile(file.path!);
                } else if (file.bytes != null) {
                  // Fallback if provider returns bytes on native
                  await widget.webrtcService.sendFileBytes(
                    file.name,
                    file.bytes!,
                  );
                } else {
                  throw Exception('No file path or bytes available');
                }
              }
            } catch (sendError) {
              if (mounted) {
                // Add error message for failed send
                // Removed: _addSystemMessage('Failed to send ${file.name}: $sendError');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WebRTCChatScreen] Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error selecting file: $e',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  void _showReceivedFiles() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Received Files',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: widget.webShareService != null
                    ? ListView.separated(
                        controller: scrollController,
                        itemCount:
                            widget.webShareService!.receivedFiles.value.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemBuilder: (context, index) {
                          final file = widget
                              .webShareService!
                              .receivedFiles
                              .value[index];
                          return FileCard(
                            filename: file.filename,
                            sizeBytes: file.sizeBytes,
                            timestamp: file.receivedAt,
                            onTap: () async {
                              if (kIsWeb &&
                                  (file.path.startsWith('web-bytes:') ||
                                      file.path.startsWith('web-parts:'))) {
                                // On web cached items, trigger the same action as the download button
                                try {
                                  // Reuse the action handler
                                  // ignore: use_build_context_synchronously
                                  await Future.microtask(() => {});
                                  // Call the same logic as onAction
                                  // Note: onAction is non-null in this callsite
                                  // ignore: unnecessary_lambdas
                                  // ignore: inference_failure_on_untyped_parameter
                                  // ignore: avoid_dynamic_calls
                                  // We directly duplicate the download logic below to avoid context quirks
                                  final path = file.path;
                                  if (path.startsWith('web-bytes:')) {
                                    final id = path.substring(
                                      'web-bytes:'.length,
                                    );
                                    final data = WebReceivedCache.get(id);
                                    if (data != null) {
                                      final ext = (file.filename.contains('.')
                                          ? file.filename
                                                .split('.')
                                                .last
                                                .toLowerCase()
                                          : '');
                                      final mime = MimeUtils.guessMime(ext);
                                      WebDownload.saveBytes(
                                        file.filename,
                                        data,
                                        contentType: mime,
                                      );
                                      return;
                                    }
                                  } else if (path.startsWith('web-parts:')) {
                                    final id = path.substring(
                                      'web-parts:'.length,
                                    );
                                    final parts = WebReceivedCache.getParts(id);
                                    if (parts != null) {
                                      final ext = (file.filename.contains('.')
                                          ? file.filename
                                                .split('.')
                                                .last
                                                .toLowerCase()
                                          : '');
                                      final mime = MimeUtils.guessMime(ext);
                                      WebDownload.saveParts(
                                        file.filename,
                                        parts,
                                        contentType: mime,
                                      );
                                      return;
                                    }
                                  }
                                } catch (_) {}
                                return;
                              }
                              try {
                                await OpenFilex.open(file.path);
                              } catch (_) {}
                            },
                            onAction: (context) async {
                              if (kIsWeb &&
                                  file.path.startsWith('web-bytes:')) {
                                final id = file.path.substring(
                                  'web-bytes:'.length,
                                );
                                final data = WebReceivedCache.get(id);
                                if (data != null) {
                                  final ext = (file.filename.contains('.')
                                      ? file.filename
                                            .split('.')
                                            .last
                                            .toLowerCase()
                                      : '');
                                  final mime = MimeUtils.guessMime(ext);
                                  WebDownload.saveBytes(
                                    file.filename,
                                    data,
                                    contentType: mime,
                                  );
                                  return;
                                }
                              }
                              if (kIsWeb &&
                                  file.path.startsWith('web-parts:')) {
                                final id = file.path.substring(
                                  'web-parts:'.length,
                                );
                                final parts = WebReceivedCache.getParts(id);
                                if (parts != null) {
                                  final ext = (file.filename.contains('.')
                                      ? file.filename
                                            .split('.')
                                            .last
                                            .toLowerCase()
                                      : '');
                                  final mime = MimeUtils.guessMime(ext);
                                  WebDownload.saveParts(
                                    file.filename,
                                    parts.cast(),
                                    contentType: mime,
                                  );
                                  return;
                                }
                              }
                              // Native: show actions - Open, Save to device…, Share
                              if (!kIsWeb) {
                                // ignore: use_build_context_synchronously
                                await showModalBottomSheet(
                                  context: context,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(16),
                                    ),
                                  ),
                                  builder: (_) => SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(
                                            Icons.open_in_new,
                                          ),
                                          title: const Text('Open'),
                                          onTap: () async {
                                            Navigator.of(context).pop();
                                            try {
                                              await OpenFilex.open(file.path);
                                            } catch (_) {}
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.save_alt),
                                          title: const Text('Save to device…'),
                                          subtitle: const Text(
                                            'Choose a location to save this file',
                                          ),
                                          onTap: () async {
                                            Navigator.of(context).pop();
                                            await FileSaver.saveToDevicePicker(
                                              context: context,
                                              filename: file.filename,
                                              sourcePath: file.path,
                                            );
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.ios_share),
                                          title: const Text('Share / Export'),
                                          onTap: () async {
                                            Navigator.of(context).pop();
                                            final box =
                                                context.findRenderObject()
                                                    as RenderBox?;
                                            final position =
                                                box?.localToGlobal(
                                                  Offset.zero,
                                                ) ??
                                                Offset.zero;
                                            final size = box?.size ?? Size.zero;
                                            await Share.shareXFiles(
                                              [XFile(file.path)],
                                              sharePositionOrigin:
                                                  Rect.fromLTWH(
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
                                  ),
                                );
                                return;
                              }
                            },
                          );
                        },
                      )
                    : const Center(child: Text('Received files not available')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _fileIconTimer?.cancel();
    _fileIconPulse?.dispose();
    if (widget.webShareService != null) {
      widget.webShareService!.receivedFiles.removeListener(
        _onReceivedFilesChanged,
      );
    }
    widget.webrtcService.connectionEstablished.removeListener(
      _connectionListener,
    );
    // Clear extra callbacks registered on the shared service to avoid leaks
    widget.webrtcService.onFileSendProgressExtra = null;
    widget.webrtcService.onFileReceiveProgressExtra = null;
    widget.webrtcService.onFileSendCompleteExtra = null;
    widget.webrtcService.onFileReceiveCompleteExtra = null;
    widget.webrtcService.onFileTransferErrorExtra = null;

    // Disconnect from WebRTC when leaving chat
    widget.webrtcService.disconnect();

    // Dispose the WebRTC service when leaving chat screen completely
    // Note: dispose() is async but we can't await in widget dispose
    widget.webrtcService.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PrimaryAppBar(
        leading: BackButtonChip(onPressed: () => Navigator.pop(context)),
        titleWidget: Padding(
          padding: const EdgeInsets.only(left: AppSizes.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WebRTC Chat',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              Text(
                _isConnected
                    ? 'Room: ${widget.roomId} • Connected'
                    : 'Room: ${widget.roomId} • Disconnected',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
        centerTitle: false,
        trailing: [
          if (widget.webShareService != null)
            AppIconButton(
              onPressed: _showReceivedFiles,
              icon: Icons.folder_open,
            ),
          AppIconButton(
            onPressed: widget.onDisconnect,
            icon: _isConnected ? Icons.wifi : Icons.wifi_off,
          ),
        ],
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE2F6FB), Color(0xFFFFFFFF)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: (() {
                  final totalItems =
                      _messages.length +
                      _incomingProgress.length +
                      _outgoingProgress.length;
                  if (totalItems == 0) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Send files to start sharing',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                    itemCount: totalItems,
                    itemBuilder: (context, index) {
                      if (index < _messages.length) {
                        final msg = _messages[index];
                        return _buildMessageBubble(msg);
                      }
                      final extra = index - _messages.length;
                      // First render incoming progress tiles
                      final incomingKeys = _incomingProgress.keys.toList();
                      if (extra < incomingKeys.length) {
                        final tId = incomingKeys[extra];
                        return TransferProgressTile(
                          progress: _incomingProgress[tId]!,
                          onCancel: () {
                            setState(() {
                              _incomingProgress.remove(tId);
                            });
                          },
                        );
                      }
                      // Then render outgoing tiles
                      final outExtra = extra - incomingKeys.length;
                      final outKeys = _outgoingProgress.keys.toList();
                      if (outExtra < outKeys.length) {
                        final tId = outKeys[outExtra];
                        return TransferProgressTile(
                          progress: _outgoingProgress[tId]!,
                          onCancel: () {
                            // Remove from local progress list
                            setState(() {
                              _outgoingProgress.remove(tId);
                            });
                          },
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  );
                })(),
              ),
              if (_isConnected)
                FileTaglineBar(
                  onTapMain: _pickAndSendFile,
                  onTapFab: _pickAndSendFile,
                  pulseController: _fileIconPulse!,
                  fileIcons: _fileIcons,
                  fileIconIndex: _fileIconIndex,
                  slideFromLeft: _slideFromLeft,
                ),
              MessageInputBar(
                controller: _messageController,
                focusNode: _inputFocus,
                onSend: () {
                  // For now, just clear
                  _messageController.clear();
                },
                enabled: _isConnected,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    debugPrint(
      '[WebRTCChatScreen] Building message bubble for type: ${message.type}, content: ${message.content}',
    );
    switch (message.type) {
      case MessageType.fileSent:
        debugPrint('[WebRTCChatScreen] Rendering file SENT card');
        return _buildFileCard(message: message, isMine: true);

      case MessageType.fileReceived:
        debugPrint('[WebRTCChatScreen] Rendering file RECEIVED card');
        return _buildFileCard(message: message, isMine: false);
    }
  }

  Widget _buildFileCard({required ChatMessage message, required bool isMine}) {
    final isReceived = message.type == MessageType.fileReceived;

    // Find the file path for received files
    String? filePath;
    if (isReceived && widget.webShareService != null) {
      final files = widget.webShareService!.receivedFiles.value;
      final file = files.cast<dynamic>().firstWhere(
        (f) => f?.filename == message.content,
        orElse: () => null,
      );
      filePath = file?.path;
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isMine ? 64 : 16,
          right: isMine ? 16 : 64,
          bottom: 8,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: FileCard(
          filename: message.content,
          sizeBytes: message.fileSize ?? 0,
          timestamp: message.timestamp,
          onTap: FileActionHandler.createOnTap(message.content, filePath ?? ''),
          onAction: isReceived
              ? FileActionHandler.createOnAction(
                  message.content,
                  filePath ?? '',
                )
              : null,
          actionIcon: isReceived ? Icons.download : null,
        ),
      ),
    );
  }
}

enum MessageType { fileSent, fileReceived }

class ChatMessage {
  final String id;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final int? fileSize;

  ChatMessage({
    required this.id,
    required this.content,
    required this.type,
    required this.timestamp,
    this.fileSize,
  });
}
