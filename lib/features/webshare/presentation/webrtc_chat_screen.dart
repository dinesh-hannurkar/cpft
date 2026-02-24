import 'dart:async';
import 'dart:io' as io;
import 'package:fylooo/features/chat/models/connection_state.dart';
import 'package:fylooo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:fylooo/features/webshare/models/chat_message_model.dart';
import 'package:fylooo/shared/widgets/app_bottom_sheet.dart';
import 'package:fylooo/shared/widgets/connection_info_dialog.dart';
import 'package:fylooo/utils/file_saver.dart';
import 'package:fylooo/utils/mime_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/core/constants/app_strings.dart';
import 'package:fylooo/features/webshare/services/webrtc_file_transfer_service.dart';
import 'package:fylooo/features/webshare/services/webshare_service.dart';
import 'package:fylooo/features/webshare/services/web_download.dart';
import 'package:fylooo/features/webshare/services/web_received_cache.dart';
import 'package:fylooo/services/connection_state_manager.dart';
import 'package:fylooo/shared/widgets/primary_app_bar.dart';
import 'package:fylooo/shared/widgets/back_button_chip.dart';
import 'package:fylooo/features/home/presentation/widgets/buttons/settings_button.dart';
import 'package:fylooo/shared/widgets/app_action_button.dart';
import 'package:fylooo/shared/widgets/temporary_files_warning_banner.dart';
import 'package:fylooo/features/chat/models/transfer_progress.dart';
import 'package:fylooo/features/chat/presentation/widgets/tiles/transfer_progress_tile.dart';
import 'package:fylooo/features/chat/presentation/widgets/message_input_bar.dart';
import 'package:fylooo/features/chat/presentation/widgets/file_tagline_bar.dart';
import 'package:fylooo/features/webshare/presentation/widgets/file_card.dart';
import 'package:fylooo/features/webshare/services/file_action_handler.dart';
import 'package:fylooo/services/background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:fylooo/shared/showcase/showcase_helper.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:fylooo/services/share_intent_service.dart';
import 'package:fylooo/features/chat/presentation/widgets/shared_files_banner.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:fylooo/shared/widgets/drag_overlay.dart';

class WebRTCChatScreen extends StatefulWidget {
  final WebRTCFileTransferService webrtcService;
  final WebShareService? webShareService;
  final String roomId;
  final VoidCallback onDisconnect;
  final String? deviceName;
  final bool disposeServiceOnClose;

  const WebRTCChatScreen({
    super.key,
    required this.webrtcService,
    this.webShareService,
    required this.roomId,
    required this.onDisconnect,
    this.deviceName,
    this.disposeServiceOnClose = true,
  });

  @override
  State<WebRTCChatScreen> createState() => _WebRTCChatScreenState();
}

class _WebRTCChatScreenState extends State<WebRTCChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _didStartShowcase = false;

  String? _peerName;
  final FocusNode _inputFocus = FocusNode();
  final List<ChatMessage> _messages = [];
  bool _isConnected = true;
  bool _isPickingFile = false;
  int _lastKnownFileCount = 0;
  late VoidCallback _connectionListener;

  // Progress tracking for UI progress bars
  final Map<String, TransferProgress> _outgoingProgress = {};
  final Map<String, TransferProgress> _incomingProgress = {};

  // Shared files handling
  late final ShareIntentService _shareIntentService;
  List<SharedMediaFile> _sharedFiles = [];

  // Drag and drop handling
  bool _dragging = false;

  // Web-specific file storage (since file paths don't work on web)
  final Map<String, List<int>> _webFileBytes = {};
  final Map<String, int> _webFileSizes = {};

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

    // Initialize background service for keeping connection alive
    BackgroundService.initialize();

    // Initialize share intent service for handling shared files
    _shareIntentService = ShareIntentService();
    _shareIntentService.sharedFilesStream.listen((files) {
      print(
        'WebRTCChatScreen: Stream listener received ${files.length} shared files',
      );
      if (mounted) {
        print(
          'WebRTCChatScreen: Received ${files.length} shared files from external app',
        );
        setState(() => _sharedFiles = List<SharedMediaFile>.from(files));
        print(
          'WebRTCChatScreen: Updated _sharedFiles to ${files.length} files',
        );
      } else {
        print('WebRTCChatScreen: Not mounted, skipping setState');
      }
    });

    // Also check for any existing shared files that might have been received before init
    final existingFiles = _shareIntentService.getCurrentSharedFiles();
    if (existingFiles.isNotEmpty) {
      print(
        'WebRTCChatScreen: Found ${existingFiles.length} existing shared files on init',
      );
      setState(() => _sharedFiles = List<SharedMediaFile>.from(existingFiles));
      print(
        'WebRTCChatScreen: Set _sharedFiles from existing files: ${existingFiles.length}',
      );
    } else {
      print('WebRTCChatScreen: No existing shared files found on init');
    }

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

    // Load local saved device name for initial title until peer arrives
    _loadLocalDeviceName();
  }

  Future<void> _loadLocalDeviceName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = (prefs.getString('device_name') ?? '').trim();
      if (name.isNotEmpty && mounted) {
        // _localName is no longer used
      }
    } catch (e) {
      debugPrint('[WebRTCChatScreen] Failed to load local device name: $e');
    }
  }

  void _setupWebRTCCallbacks() {
    // Set up main WebRTC callbacks for connection management
    widget.webrtcService.onConnectionEstablished = () {
      if (!mounted) return;
      debugPrint('[WebRTCChatScreen] 🎉 WebRTC Connection Established!');
      setState(() {
        _isConnected = true;
      });
      // Auto-exchange names when connected (after a short delay to ensure channel ready)
      if (kIsWeb) {
        // Delay on web to let mobile's chat screen open first and data channel stabilize
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && widget.webrtcService.connectionEstablished.value) {
            _sendLocalNameToPeer();
          }
        });
      } else {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted && widget.webrtcService.connectionEstablished.value) {
            _sendLocalNameToPeer();
          }
        });
      }
      // Removed: _addSystemMessage('Connected successfully');
    };

    widget.webrtcService.onConnectionLost = () {
      if (!mounted) return;
      debugPrint('[WebRTCChatScreen] ❌ WebRTC Connection Lost!');
      setState(() {
        _isConnected = false;
      });
    };

    // Set up file transfer callbacks
    widget.webrtcService.onFileReceiveProgress = (filename, received, total) {
      if (!mounted) return;
      // Update progress for incoming transfers
      setState(() {
        _incomingProgress.putIfAbsent(
          'incoming_$filename',
          () => TransferProgress(name: filename, total: total),
        );
        _incomingProgress['incoming_$filename']!.updateProgress(
          received.toDouble(),
        );
      });
    };

    widget.webrtcService.onFileSendProgress = (filename, sent, total) {
      if (!mounted) return;
      // Update progress for outgoing transfers
      setState(() {
        _outgoingProgress.putIfAbsent(
          'outgoing_$filename',
          () => TransferProgress(name: filename, total: total),
        );
        _outgoingProgress['outgoing_$filename']!.updateProgress(
          sent.toDouble(),
        );
      });
    };

    widget.webrtcService.onFileSendComplete = (filename, filePath, fileSize) {
      if (!mounted) return;
      debugPrint('[WebRTCChatScreen] WebRTC send complete: $filename');
      setState(() {
        _outgoingProgress.remove('outgoing_$filename');
      });
    };

    widget.webrtcService.onFileReceiveComplete = (filename, savedPath) {
      if (!mounted) return;
      debugPrint(
        '[WebRTCChatScreen] WebRTC receive complete: $filename at $savedPath',
      );
      setState(() {
        _incomingProgress.remove('incoming_$filename');
      });
      _onWebRTCFileReceiveComplete(filename, savedPath);
    };

    widget.webrtcService.onFileTransferError = (filename, reason, duringSend) {
      if (!mounted) return;
      debugPrint(
        '[WebRTCChatScreen] ❌ WebRTC transfer error: $filename | $reason',
      );

      setState(() {
        if (duringSend) {
          _outgoingProgress.remove('outgoing_$filename');
        } else {
          _incomingProgress.remove('incoming_$filename');
        }
      });
    };

    // Set up additional callbacks for chat updates
    widget.webrtcService.addFileReceiveCompleteListener(
      _onWebRTCFileReceiveComplete,
    );

    // Text chat: received and sent callbacks
    widget.webrtcService.onTextMessageReceived = (message) {
      if (!mounted) return;
      // Check for peer-info plain text message
      if (message.startsWith('peer-info: ')) {
        setState(() {
          _peerName = message.substring(11).trim();
        });
        return; // Do not add a chat bubble for metadata
      }
      setState(() {
        _messages.add(
          ChatMessage(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            content: message,
            type: MessageType.textReceived,
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    };

    widget.webrtcService.onTextMessageSent = (message) {
      if (!mounted) return;
      // Ignore local peer-info from showing as a bubble
      if (message.startsWith('peer-info: ')) {
        return;
      }
      setState(() {
        _messages.add(
          ChatMessage(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            content: message,
            type: MessageType.textSent,
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    };

    // Listen for connection changes
    widget.webrtcService.connectionEstablished.addListener(
      _onConnectionChanged,
    );

    // If already connected (e.g., on web), send name immediately
    if (widget.webrtcService.connectionEstablished.value) {
      if (kIsWeb) {
        // Delay on web to let mobile's chat screen open first and data channel stabilize
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _sendLocalNameToPeer();
        });
      } else {
        _sendLocalNameToPeer();
      }
    }
  }

  Future<void> _sendLocalNameToPeer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString('device_name') ?? '').trim();
      final fallback = (widget.deviceName ?? '').trim();
      String localName = saved.isNotEmpty ? saved : fallback;
      if (localName.isEmpty && kIsWeb) {
        localName = AppStrings.webUser;
      }
      if (localName.isNotEmpty) {
        final message = 'peer-info: $localName';
        widget.webrtcService.sendTextMessage(message);
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && (_peerName == null || _peerName!.isEmpty)) {
            try {
              widget.webrtcService.sendTextMessage(message);
            } catch (_) {}
          }
        });
      }
    } catch (e) {
      debugPrint('[WebRTCChatScreen] Failed to send local name: $e');
    }
  }

  void _onConnectionChanged() {
    final isConnected = widget.webrtcService.connectionEstablished.value;
    if (!mounted) return;

    debugPrint('[WebRTCChatScreen] Connection state changed: $isConnected');
    setState(() {
      _isConnected = isConnected;
    });

    // Update centralized connection state manager
    ConnectionStateManager().updateWebRTCConnections(isConnected);

    if (isConnected) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _onWebRTCFileReceiveComplete(String filename, String savedPath) {
    if (!mounted) return;
    debugPrint(
      '[WebRTCChatScreen] WebRTC receive complete: $filename at $savedPath',
    );

    // Add file to WebShareService
    if (widget.webShareService != null) {
      if (kIsWeb) {
        if (savedPath.startsWith('web-parts:')) {
          final id = savedPath.substring('web-parts:'.length);
          final total = WebReceivedCache.length(id);
          widget.webShareService!.addWebRTCReceivedFile(
            filename,
            savedPath,
            total,
          );
        } else if (savedPath.startsWith('web-bytes:')) {
          final id = savedPath.substring('web-bytes:'.length);
          final data = WebReceivedCache.get(id);
          final len = data?.length ?? 0;
          widget.webShareService!.addWebRTCReceivedFile(
            filename,
            savedPath,
            len,
          );
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
          widget.webShareService!.addWebRTCReceivedFile(
            filename,
            savedPath,
            fileSize,
          );
        } catch (e) {
          debugPrint('[WebRTCChatScreen] Error getting file size: $e');
          // Fallback to expected size
          final fileSize = widget.webrtcService.lastExpectedFileSize;
          widget.webShareService!.addWebRTCReceivedFile(
            filename,
            savedPath,
            fileSize,
          );
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
      // If we already seeded an entry with unknown total (0), and now we
      // have a known total, replace the entry so UI stops showing preparing.
      final existing = _outgoingProgress[transferId];
      if (existing == null) {
        _outgoingProgress[transferId] = TransferProgress(
          name: filename,
          total: total,
          mime: MimeUtils.guessMime(filename.split('.').last),
        );
      } else if (existing.total == 0 && total > 0) {
        final newTp = TransferProgress(
          name: existing.name,
          total: total,
          mime: existing.mime,
        );
        newTp.updateProgress(existing.progress);
        _outgoingProgress[transferId] = newTp;
      }
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
    setState(() {
      _outgoingProgress.remove('outgoing_$filename');
    });

    // Mirror WebShareScreen behavior: record sent file in shared list if available
    final svc = widget.webShareService;
    if (svc != null) {
      final fileId = 'webrtc_${DateTime.now().millisecondsSinceEpoch}';
      svc.addWebRTCSharedFile(fileId, filename, fileSize);
    }
  }

  void _onFileReceiveComplete(String filename, String savedPath) {
    setState(() {
      _incomingProgress.remove('incoming_$filename');
    });
  }

  void _onFileTransferError(String filename, String reason, bool duringSend) {
    final direction = duringSend ? 'sending' : 'receiving';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to $direction $filename: $reason'),
        backgroundColor: Colors.red,
      ),
    );
    setState(() {
      if (duringSend) {
        _outgoingProgress.remove('outgoing_$filename');
      } else {
        _incomingProgress.remove('incoming_$filename');
      }
    });
  }

  Future<int> _getFileSize(String path) async {
    try {
      final file = io.File(path);
      return await file.length();
    } catch (e) {
      print('WebRTCChatScreen: Error getting file size for $path: $e');
      return 0;
    }
  }

  Future<void> _handleDroppedFiles(List<XFile> droppedFiles) async {
    final sharedMediaFiles = <SharedMediaFile>[];

    for (final xFile in droppedFiles) {
      try {
        final fileName = xFile.name;
        final filePath = xFile.path;

        // On web, we need to read the file bytes since file paths don't work
        List<int>? fileBytes;
        int? fileSize;

        if (kIsWeb) {
          fileBytes = await xFile.readAsBytes();
          fileSize = fileBytes.length;
        } else {
          // On mobile/desktop, check if file exists and get size
          final file = io.File(xFile.path);
          if (await file.exists()) {
            fileSize = await file.length();
          }
        }

        // Determine MIME type
        String? mimeType;
        final extension = fileName.split('.').last.toLowerCase();
        switch (extension) {
          case 'jpg':
          case 'jpeg':
            mimeType = 'image/jpeg';
            break;
          case 'png':
            mimeType = 'image/png';
            break;
          case 'gif':
            mimeType = 'image/gif';
            break;
          case 'mp4':
            mimeType = 'video/mp4';
            break;
          case 'pdf':
            mimeType = 'application/pdf';
            break;
          case 'txt':
            mimeType = 'text/plain';
            break;
          case 'zip':
            mimeType = 'application/zip';
            break;
          default:
            mimeType = 'application/octet-stream';
        }

        sharedMediaFiles.add(
          SharedMediaFile(
            path: filePath,
            type: mimeType.contains('image')
                ? SharedMediaType.image
                : mimeType.contains('video')
                ? SharedMediaType.video
                : SharedMediaType.file,
            mimeType: mimeType,
            duration: null, // Not needed for dropped files
            thumbnail: null, // Not needed for dropped files
          ),
        );

        // Store file bytes for web
        if (kIsWeb && fileBytes != null) {
          // Store the bytes for later use when sending
          _webFileBytes[filePath] = fileBytes;
          _webFileSizes[filePath] = fileSize ?? 0;
        }
      } catch (e) {
        debugPrint('Error processing dropped file ${xFile.name}: $e');
      }
    }

    if (sharedMediaFiles.isNotEmpty) {
      setState(() {
        for (final file in sharedMediaFiles) {
          // Check if file already exists (by path)
          if (!_sharedFiles.any((existing) => existing.path == file.path)) {
            _sharedFiles.add(file);
          }
        }
      });
      if (mounted) {
        AppSnackbar.showSuccess(
          context,
          'Files ready to send. Tap send button.',
        );
      }
    }
  }

  void _sendSharedFiles() async {
    if (_sharedFiles.isEmpty || !_isConnected) return;

    int successCount = 0;
    List<String> failedFiles = [];

    try {
      for (final sharedFile in _sharedFiles) {
        print('WebRTCChatScreen: Sending shared file: ${sharedFile.path}');

        // Add file message to chat immediately
        final fileName = sharedFile.path.split('/').last;
        int fileSize;

        if (kIsWeb && _webFileSizes.containsKey(sharedFile.path)) {
          // Use stored size for web files
          fileSize = _webFileSizes[sharedFile.path]!;
        } else {
          // Get size from file system for mobile/desktop
          fileSize = await _getFileSize(sharedFile.path);
        }

        _addFileMessage(fileName, fileSize, true);

        try {
          if (kIsWeb && _webFileBytes.containsKey(sharedFile.path)) {
            // On web, use sendFileBytes with stored file data
            final fileBytes = _webFileBytes[sharedFile.path]!;
            await widget.webrtcService.sendFileBytes(fileName, fileBytes);
          } else {
            // On mobile/desktop, use sendFile with file path
            await widget.webrtcService.sendFile(sharedFile.path);
          }
          successCount++;
          print('WebRTCChatScreen: Successfully sent file: ${sharedFile.path}');
        } catch (fileError) {
          print(
            'WebRTCChatScreen: Failed to send file ${sharedFile.path}: $fileError',
          );
          failedFiles.add(sharedFile.path.split('/').last); // Add filename only
        }
      }

      // Clear the shared files after attempting to send all
      _shareIntentService.clearSharedFiles();
      setState(() => _sharedFiles.clear());

      // Clear web file storage
      _webFileBytes.clear();
      _webFileSizes.clear();

      // Show appropriate message based on results
      if (mounted) {
        if (failedFiles.isEmpty) {
          AppSnackbar.showSuccess(
            context,
            '$successCount file${successCount > 1 ? 's' : ''} sent successfully',
          );
        } else if (successCount > 0) {
          AppSnackbar.showInfo(
            context,
            '$successCount sent, ${failedFiles.length} failed: ${failedFiles.join(', ')}',
          );
        } else {
          AppSnackbar.showError(
            context,
            'Failed to send files: ${failedFiles.join(', ')}',
          );
        }
      }
    } catch (e) {
      print('WebRTCChatScreen: Error in send operation: $e');
      if (mounted) {
        AppSnackbar.showError(context, 'Failed to send files: $e');
      }
    }
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
    if (_isPickingFile) return;
    setState(() => _isPickingFile = true);

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb,
      );
    } catch (e) {
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
    } finally {
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }

    if (result != null && result.files.isNotEmpty) {
      for (final file in result.files) {
        final hasData = kIsWeb
            ? file.bytes != null
            : (file.path != null || file.bytes != null);

        if (hasData) {
          _addFileMessage(file.name, file.size, true);
          setState(() {
            final transferId = 'outgoing_${file.name}';
            _outgoingProgress.putIfAbsent(
              transferId,
              () => TransferProgress(
                name: file.name,
                total: 0,
                mime: MimeUtils.guessMime(file.name.split('.').last),
              ),
            );
            _outgoingProgress[transferId]!.updateProgress(0);
          });

          try {
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
                await widget.webrtcService.sendFileBytes(
                  file.name,
                  file.bytes!,
                );
              } else {
                throw Exception('No file path or bytes available');
              }
            }
          } catch (sendError) {
            print(
              'WebRTCChatScreen: Error sending file ${file.name}: $sendError',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Failed to send ${file.name}: $sendError',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      }
    }
  }

  void _showReceivedFiles() {
    showAppBottomSheet(
      context: context,
      title: 'Received Files',
      subtitle: 'Files received during this session',
      child: widget.webShareService != null
          ? ListView.separated(
              itemCount: widget.webShareService!.receivedFiles.value.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemBuilder: (context, index) {
                final file = widget.webShareService!.receivedFiles.value[index];
                return FileCard(
                  filename: file.filename,
                  sizeBytes: file.sizeBytes,
                  timestamp: file.receivedAt,
                  margin: EdgeInsets.all(0),
                  onTap: () async {
                    if (kIsWeb &&
                        (file.path.startsWith('web-bytes:') ||
                            file.path.startsWith('web-parts:'))) {
                      try {
                        await Future.microtask(() => {});
                        final path = file.path;
                        if (path.startsWith('web-bytes:')) {
                          final id = path.substring('web-bytes:'.length);
                          final data = WebReceivedCache.get(id);
                          if (data != null) {
                            final ext = (file.filename.contains('.')
                                ? file.filename.split('.').last.toLowerCase()
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
                          final id = path.substring('web-parts:'.length);
                          final parts = WebReceivedCache.getParts(id);
                          if (parts != null) {
                            final ext = (file.filename.contains('.')
                                ? file.filename.split('.').last.toLowerCase()
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
                    if (kIsWeb && file.path.startsWith('web-bytes:')) {
                      final id = file.path.substring('web-bytes:'.length);
                      final data = WebReceivedCache.get(id);
                      if (data != null) {
                        final ext = (file.filename.contains('.')
                            ? file.filename.split('.').last.toLowerCase()
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
                    if (kIsWeb && file.path.startsWith('web-parts:')) {
                      final id = file.path.substring('web-parts:'.length);
                      final parts = WebReceivedCache.getParts(id);
                      if (parts != null) {
                        final ext = (file.filename.contains('.')
                            ? file.filename.split('.').last.toLowerCase()
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
                    if (!kIsWeb) {
                      final RenderBox button =
                          context.findRenderObject() as RenderBox;
                      final RenderBox overlay =
                          Navigator.of(
                                context,
                              ).overlay!.context.findRenderObject()
                              as RenderBox;
                      final RelativeRect position = RelativeRect.fromRect(
                        Rect.fromPoints(
                          button.localToGlobal(
                            button.size.bottomRight(Offset.zero),
                            ancestor: overlay,
                          ),
                          button.localToGlobal(
                            button.size.bottomRight(Offset.zero),
                            ancestor: overlay,
                          ),
                        ),
                        Offset.zero & overlay.size,
                      );

                      await showMenu<String>(
                        context: context,
                        position: position,
                        color: AppColors.white,
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        items: [
                          PopupMenuItem<String>(
                            value: 'open',
                            child: Row(
                              children: [
                                const Icon(Icons.open_in_new, size: 20),
                                const SizedBox(width: 12),
                                const Text('Open'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'save',
                            child: Row(
                              children: [
                                const Icon(Icons.save_alt, size: 20),
                                const SizedBox(width: 12),
                                const Text('Save to device…'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'share',
                            child: Row(
                              children: [
                                const Icon(Icons.ios_share, size: 20),
                                const SizedBox(width: 12),
                                const Text('Share / Export'),
                              ],
                            ),
                          ),
                        ],
                      ).then((value) async {
                        switch (value) {
                          case 'open':
                            try {
                              await OpenFilex.open(file.path);
                            } catch (_) {}
                            break;
                          case 'save':
                            await FileSaver.saveToDevicePicker(
                              context: context,
                              filename: file.filename,
                              sourcePath: file.path,
                            );
                            break;
                          case 'share':
                            final box =
                                context.findRenderObject() as RenderBox?;
                            final position =
                                box?.localToGlobal(Offset.zero) ?? Offset.zero;
                            final size = box?.size ?? Size.zero;
                            await Share.shareXFiles(
                              [XFile(file.path)],
                              sharePositionOrigin: Rect.fromLTWH(
                                position.dx,
                                position.dy,
                                size.width,
                                size.height,
                              ),
                            );
                            break;
                        }
                      });
                      return;
                    }
                  },
                  actionIcon: kIsWeb ? Icons.download : Icons.more_vert,
                );
              },
            )
          : const Center(child: Text('Received files not available')),
    );
  }

  void _showConnectionInfo() {
    showConnectionInfoDialog(
      context: context,
      peerName: _peerName,
      networkName: widget.roomId,
      onDisconnect: widget.onDisconnect,
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

    // Only dispose service if this screen owns it
    if (widget.disposeServiceOnClose) {
      // Note: dispose() is async but we can't await in widget dispose
      widget.webrtcService.dispose();
    }

    // Update connection state - background service will be managed by ConnectionStateManager
    ConnectionStateManager().updateWebRTCConnections(false);

    // Disable wakelock
    WakelockPlus.disable();

    super.dispose();
  }

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(AppSizes.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Close Connection?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, size: 24),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.greyLight,
                      padding: const EdgeInsets.all(10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.spaceBtwInputFields),
              // Content
              Text(
                'Are you sure you want to close the connection and go back? '
                'This will disconnect and stops any ongoing transfers.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.darkPrimary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              // Single action button
              AppActionButton(
                text: AppStrings.closeAndGoBackText,
                onPressed: () {
                  if (mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
                backgroundColor: AppColors.red.withOpacity(0.1),
                textColor: AppColors.red,
                borderColor: AppColors.white,
                shadowColor: AppColors.red.withOpacity(0.2),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    const logoHeight = 28.0;
    final logoCacheHeight = (logoHeight * dpr).round();

    if (!_didStartShowcase) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final prefs = await SharedPreferences.getInstance();
        final hasSeenShowcase = prefs.getBool('chat_showcase_seen') ?? false;
        if (!hasSeenShowcase && mounted) {
          // Skip showcase on web to prevent layout crashes
          if (kIsWeb) {
            prefs.setBool('chat_showcase_seen', true);
            return;
          }

          // Add multiple delays and checks for mobile compatibility
          await Future.delayed(const Duration(milliseconds: 1000));
          if (!mounted) return;

          // Additional frame to ensure layout is complete
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            Future.delayed(const Duration(milliseconds: 300), () {
              if (!mounted) return;

              try {
                ShowcaseHelper.startForWebRTCChat(context);
                prefs.setBool('chat_showcase_seen', true);
              } catch (e) {
                // Silently ignore showcase errors
                debugPrint('Showcase initialization failed: $e');
              }
            });
          });
        }
      });
      _didStartShowcase = true;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _onWillPop().then((shouldPop) {
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        });
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PrimaryAppBar(
          leading: BackButtonChip(
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          logo: kIsWeb
              ? Image.asset(
                  'assets/images/web-app-logo.webp',
                  height: logoHeight,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  isAntiAlias: true,
                  cacheHeight: logoCacheHeight,
                )
              : null,
          titleWidget: Padding(
            padding: const EdgeInsets.only(left: AppSizes.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (_peerName?.isNotEmpty == true
                      ? _peerName!
                            .split(RegExp(r'\s+'))
                            .map(
                              (w) => w.isEmpty
                                  ? w
                                  : '${w[0].toUpperCase()}${w.substring(1)}',
                            )
                            .join(' ')
                      : AppStrings.directShare),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  _isConnected
                      ? '${widget.roomId} • Connected'
                      : '${widget.roomId} • Disconnected',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          centerTitle: false,
          trailing: [
            if (widget.webShareService != null)
              Showcase(
                key: ShowcaseHelper.receivedListKey,
                disableBarrierInteraction: false,
                targetPadding: const EdgeInsets.all(8),
                title: 'Received Files',
                description:
                    'Open the list of received files to download or open.',
                tooltipBackgroundColor: Colors.white,
                textColor: Colors.black,
                descTextStyle: const TextStyle(
                  fontSize: 12,
                  color: Colors.black87,
                ),
                titleTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontSize: 16,
                ),
                tooltipBorderRadius: BorderRadius.circular(12),
                targetBorderRadius: BorderRadius.circular(12),
                child: AppIconButton(
                  onPressed: _showReceivedFiles,
                  icon: Icons.folder_open,
                ),
              ),

            AppIconButton(
              onPressed: _showConnectionInfo,
              icon: _isConnected ? Icons.wifi : Icons.wifi_off,
            ),
            AppIconButton(
              onPressed: () {
                try {
                  ShowcaseHelper.startForWebRTCChat(context);
                } catch (_) {}
              },
              icon: Icons.help_outline,
            ),
          ],
          backgroundColor: Colors.transparent,
        ),
        body: DropTarget(
          onDragDone: (detail) async {
            setState(() {
              _dragging = false;
            });

            // Handle dropped files
            if (detail.files.isNotEmpty) {
              await _handleDroppedFiles(detail.files);
            }
          },
          onDragEntered: (detail) {
            setState(() {
              _dragging = true;
            });
          },
          onDragExited: (detail) {
            setState(() {
              _dragging = false;
            });
          },
          child: Stack(
            children: [
              Container(
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
                      const TemporaryFilesWarningBanner(),
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
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSizes.sm,
                            ),
                            itemCount: totalItems,
                            itemBuilder: (context, index) {
                              if (index < _messages.length) {
                                final msg = _messages[index];
                                return _buildMessageBubble(msg);
                              }
                              final extra = index - _messages.length;
                              // First render incoming progress tiles
                              final incomingKeys = _incomingProgress.keys
                                  .toList();
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
                        Showcase(
                          key: ShowcaseHelper.sendFileButtonKey,
                          disableBarrierInteraction: false,
                          targetPadding: const EdgeInsets.all(8),
                          title: 'Send Files',
                          description:
                              'Tap here to select and send files to the connected device.',
                          tooltipBackgroundColor: Colors.white,
                          textColor: Colors.black,
                          descTextStyle: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                          titleTextStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            fontSize: 16,
                          ),
                          tooltipBorderRadius: BorderRadius.circular(12),
                          targetBorderRadius: BorderRadius.circular(12),
                          child: FileTaglineBar(
                            onTapMain: _pickAndSendFile,
                            onTapFab: _pickAndSendFile,
                            pulseController: _fileIconPulse!,
                            fileIcons: _fileIcons,
                            fileIconIndex: _fileIconIndex,
                            slideFromLeft: _slideFromLeft,
                            isLoading: _isPickingFile,
                          ),
                        ),
                      if (_sharedFiles.isNotEmpty)
                        SharedFilesBanner(
                          files: _sharedFiles,
                          onSend: _sendSharedFiles,
                          enabled: _isConnected,
                        ),
                      MessageInputBar(
                        controller: _messageController,
                        focusNode: _inputFocus,
                        onSend: _handleSendPressed,
                        enabled: _isConnected,
                      ),
                    ],
                  ),
                ),
              ),
              // Drag overlay
              ...(_dragging
                  ? [
                      DragOverlay(
                        title: 'Drop files to send',
                        subtitle:
                            'Release to send files to the connected device',
                      ),
                    ]
                  : []),
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
        TransferProgress? preparing;
        final hasOngoing = _outgoingProgress.values.any((tp) {
          final sameName = tp.name == message.content;
          final inProgress = tp.total == 0 || tp.progress < tp.total;
          if (sameName && tp.total == 0) preparing = tp;
          return sameName && inProgress;
        });
        if (hasOngoing) {
          if (preparing != null &&
              preparing!.total == 0 &&
              preparing!.progress == 0) {
            return Align(
              alignment: Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md,
                  vertical: AppSizes.sm,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue.shade400,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Preparing ${message.content}…',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }
        return _buildFileCard(message: message, isMine: true);

      case MessageType.fileReceived:
        return _buildFileCard(message: message, isMine: false);
      case MessageType.textSent:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
          child: MessageBubble(
            message: DeviceMessage(
              content: message.content,
              type: 'text',
              timestamp: message.timestamp,
              senderName: '',
            ),
            isMine: true,
          ),
        );
      case MessageType.textReceived:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
          child: MessageBubble(
            message: DeviceMessage(
              content: message.content,
              type: 'text',
              timestamp: message.timestamp,
              senderName: '',
            ),
            isMine: false,
          ),
        );
    }
  }

  Widget _buildFileCard({required ChatMessage message, required bool isMine}) {
    final isReceived = message.type == MessageType.fileReceived;
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
          top: AppSizes.sm,
          left: isMine ? 0 : 0,
          right: isMine ? 0 : 0,
          bottom: AppSizes.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
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

  void _handleSendPressed() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    _inputFocus.requestFocus();
    widget.webrtcService.sendTextMessage(text);
  }
}

enum MessageType { fileSent, fileReceived, textSent, textReceived }
