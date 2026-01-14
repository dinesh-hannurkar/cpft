import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:fylooo/features/chat/models/connection_state.dart';
import 'package:fylooo/features/chat/presentation/widgets/constants/file_icons_list.dart';
import 'package:fylooo/features/chat/presentation/widgets/empty_data_widget.dart';
import 'package:fylooo/features/chat/services/connection_manager.dart';
import 'package:fylooo/features/chat/services/connection_service.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fylooo/services/sound_service.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';
import 'package:fylooo/features/chat/models/transfer_progress.dart';
import 'package:fylooo/features/chat/models/received_file.dart';
import 'package:fylooo/features/chat/presentation/widgets/tiles/transfer_progress_tile.dart';
import 'package:fylooo/features/chat/presentation/widgets/message_bubble.dart';
import 'package:fylooo/features/chat/presentation/widgets/completed_file_card.dart';
import 'package:fylooo/features/chat/presentation/widgets/received_files_sheet.dart';
import 'package:fylooo/features/chat/presentation/widgets/chat_top_bar.dart';
import 'package:fylooo/features/chat/presentation/widgets/connecting_banner.dart';
import 'package:fylooo/features/chat/presentation/widgets/error_banner.dart';
import 'package:fylooo/features/chat/presentation/widgets/wifi_direct_banner.dart';
import 'package:fylooo/features/chat/presentation/widgets/file_tagline_bar.dart';
import 'package:fylooo/features/chat/presentation/widgets/message_input_bar.dart';
import 'package:fylooo/features/home/presentation/widgets/sheets/connected_devices_sheet.dart';
import 'package:fylooo/shared/widgets/app_bottom_sheet.dart';
import 'package:fylooo/shared/widgets/temporary_files_warning_banner.dart';
import 'package:fylooo/shared/widgets/transfer_stats_banner.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:fylooo/shared/showcase/showcase_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:fylooo/services/share_intent_service.dart';
import 'package:fylooo/features/chat/presentation/widgets/shared_files_banner.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:fylooo/shared/widgets/drag_overlay.dart';
import 'package:fylooo/utils/permissions.dart';

class ChatScreen extends StatefulWidget {
  final String deviceName;
  final String ipAddress;
  final int port;
  final String myDeviceName;
  final ConnectionManager connectionManager;
  final String? initialDeviceId;
  final List<XFile>? droppedFiles;
  final VoidCallback? onFilesSent;

  const ChatScreen({
    super.key,
    required this.deviceName,
    required this.ipAddress,
    required this.port,
    required this.myDeviceName,
    required this.connectionManager,
    this.initialDeviceId,
    this.droppedFiles,
    this.onFilesSent,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  late ConnectionService _connectionService;
  final List<DeviceMessage> _messages = [];
  final Map<String, TransferProgress> _incomingProgress = {};
  final Map<String, TransferProgress> _outgoingProgress = {};
  final Map<String, String> _savedFilePaths =
      {}; // Maps original path to new saved path
  final List<ReceivedFile> _receivedFiles = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  final Set<String> _shownOfferDialogs = {};

  late final ShareIntentService _shareIntentService;
  List<SharedMediaFile> _sharedFiles = [];

  int _fileIconIndex = 0;
  bool _slideFromLeft = true;
  AnimationController? _fileIconPulse;
  Timer? _fileIconTimer;

  ConnectionInfo? _connectionInfo;
  bool _isConnecting = false;
  bool _didStartShowcase = false;
  bool _didShowFileReceivedShowcase = false;
  bool _isPickingFile = false;

  bool _dragging = false; // For drag and drop visual feedback
  bool _wasKeyboardOpen = false; // Track previous keyboard state
  bool _isProgrammaticScroll = false; // Track programmatic scrolling

  // Transfer statistics tracking
  final Map<String, DateTime> _transferStartTimes = {};
  DateTime? _lastTransferEndTime;
  int? _lastTransferBytes;
  Duration? _lastTransferDuration;

  // Peer‑to‑peer port constant
  static const int p2pPort = 53318;

  @override
  void initState() {
    super.initState();
    // Use initialDeviceId if provided to stay consistent with existing screen logic
    final targetDeviceName = widget.initialDeviceId ?? widget.deviceName;
    _connectionService = widget.connectionManager.getOrCreateConnection(
      targetDeviceName,
    );

    // Preload existing messages (history)
    _messages.addAll(_connectionService.getMessageHistory());

    _connectionService.addStatusListener(_onStatusChanged);
    _connectionService.addMessageListener(_onMessageReceived);

    // Start connect if needed
    if (_connectionService.isConnected) {
      _connectionInfo = _connectionService.currentConnection;
    } else if (_connectionService.currentConnection?.status ==
        ConnectionStatus.connecting) {
      // Already connecting (incoming) – do not start outgoing connect
      _connectionInfo = _connectionService.currentConnection;
    } else {
      _connectToDevice();
    }

    // Animation for file icon pulse + cycling
    _fileIconPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _fileIconTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _slideFromLeft = !_slideFromLeft;
        _fileIconIndex = (_fileIconIndex + 1) % fileIcons.length;
      });
    });

    _scrollController.addListener(() {
      // Close keyboard when scrolling (but not during programmatic scrolls)
      if (_inputFocus.hasFocus && !_isProgrammaticScroll) {
        _inputFocus.unfocus();
      }
    });

    // Check pending offers after frame
    _inputFocus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkPendingFileOffers(),
    );

    _shareIntentService = ShareIntentService();
    _shareIntentService.sharedFilesStream.listen((files) {
      print(
        'ChatScreen: Stream listener received ${files.length} shared files',
      );
      if (mounted) {
        print(
          'ChatScreen: Received ${files.length} shared files from external app',
        );
        setState(() => _sharedFiles = List<SharedMediaFile>.from(files));
      }
    });

    // Also check for any existing shared files that might have been received before init
    final existingFiles = _shareIntentService.getCurrentSharedFiles();
    if (existingFiles.isNotEmpty) {
      print(
        'ChatScreen: Found ${existingFiles.length} existing shared files on init',
      );
      setState(() => _sharedFiles = List<SharedMediaFile>.from(existingFiles));
    }

    // Handle dropped files if provided
    if (widget.droppedFiles != null && widget.droppedFiles!.isNotEmpty) {
      _handleDroppedFiles(widget.droppedFiles!);
    }
  }

  @override
  void dispose() {
    _connectionService.removeStatusListener(_onStatusChanged);
    _connectionService.removeMessageListener(_onMessageReceived);
    _fileIconTimer?.cancel();
    _fileIconPulse?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _connectToDevice() async {
    setState(() => _isConnecting = true);
    final success = await _connectionService.connect(
      _connectionService.deviceName,
      widget.ipAddress,
      p2pPort,
    );
    if (mounted) {
      setState(() => _isConnecting = false);
    }
    if (!success && mounted) {
      AppSnackbar.showError(
        context,
        'Failed to connect to ${_remoteDeviceName()}',
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _connectToDevice,
        ),
      );
    }
  }

  Future<void> _handleDroppedFiles(List<XFile> droppedFiles) async {
    final sharedMediaFiles = <SharedMediaFile>[];

    for (final xFile in droppedFiles) {
      final file = io.File(xFile.path);
      if (await file.exists()) {
        final fileName = xFile.name;
        final filePath = xFile.path;
        await file.length();

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
      AppSnackbar.showSuccess(context, 'Files ready to send. Tap send button.');
    }
  }

  final Set<String> _completedTransferIds = {};

  void _onMessageReceived(DeviceMessage message) {
    if (!mounted) return;
    switch (message.type) {
      case 'file_offer':
        _handleIncomingOffer(message);
        break;
      case 'file_progress':
        final tId = message.metadata?['transferId'] as String?;

        // 🛡️ Guard: Ignore progress for already completed transfers
        if (tId != null && _completedTransferIds.contains(tId)) {
          return;
        }

        final bytes = message.metadata?['bytes'] as int?;
        final total = message.metadata?['total'] as int?;
        final mime = message.metadata?['mime'] as String?;
        final outgoing = message.metadata?['outgoing'] as bool? ?? false;
        if (tId != null && bytes != null && total != null) {
          final map = outgoing ? _outgoingProgress : _incomingProgress;
          final isNewTransfer = !map.containsKey(tId);

          setState(() {
            map.putIfAbsent(
              tId,
              () => TransferProgress(
                name: message.content,
                total: total,
                mime: mime,
              ),
            );
            map[tId]!.updateProgress(bytes.toDouble());
            map[tId]!.isPending = false; // Clear pending state on progress

            // Track transfer start time
            if (isNewTransfer) {
              _transferStartTimes[tId] = DateTime.now();
            }
          });

          // Play sound when transfer starts (first progress update)
          if (isNewTransfer) {
            SoundService().playTransferStart();
          }
        }
        break;
      case 'file_pending':
        final tId = message.metadata?['transferId'] as String?;
        if (tId != null && _completedTransferIds.contains(tId)) return;

        final buffered = message.metadata?['buffered'] as int? ?? 0;
        final outgoing = message.metadata?['outgoing'] as bool? ?? false;
        if (tId != null) {
          setState(() {
            final map = outgoing ? _outgoingProgress : _incomingProgress;
            if (map.containsKey(tId)) {
              map[tId]!.isPending = true;
              map[tId]!.pendingChunks = buffered;
            }
          });
        }
        break;
      case 'file_complete':
        final tId = message.metadata?['transferId'] as String?;
        if (tId != null) _completedTransferIds.add(tId);

        final path = message.metadata?['path'] as String?;
        final isOutgoing = message.metadata?['outgoing'] as bool? ?? false;
        final wasFirstReceivedFile = _receivedFiles.isEmpty && !isOutgoing;
        final wasSecondReceivedFile = _receivedFiles.length == 1 && !isOutgoing;

        // Calculate transfer statistics
        // Calculate transfer statistics
        final durationMs = message.metadata?['durationMs'] as int?;
        if (durationMs != null) {
          _lastTransferDuration = Duration(milliseconds: durationMs);
          _lastTransferEndTime = DateTime.now(); // Just for timestamp reference
          final size = message.metadata?['size'] as int?;
          if (size != null) {
            _lastTransferBytes = size;
          }
          if (tId != null) _transferStartTimes.remove(tId);
        } else if (tId != null && _transferStartTimes.containsKey(tId)) {
          final endTime = DateTime.now();
          final startTime = _transferStartTimes[tId]!;
          _lastTransferDuration = endTime.difference(startTime);
          _lastTransferEndTime = endTime;
          final size = message.metadata?['size'] as int?;
          if (size != null) {
            _lastTransferBytes = size;
          }
          _transferStartTimes.remove(tId);
        }

        // Play transfer complete sound
        SoundService().playTransferComplete();

        setState(() {
          if (!_messages.any(
            (m) =>
                m.timestamp == message.timestamp &&
                m.content == message.content,
          )) {
            _messages.add(message);
          }
          if (tId != null) {
            _incomingProgress.remove(tId);
            _outgoingProgress.remove(tId);
          }
          // Only add received files (not sent files) to the received files list
          if (path != null && path.isNotEmpty && !isOutgoing) {
            _receivedFiles.add(
              ReceivedFile(
                name: message.content,
                path: path,
                timestamp: message.timestamp,
              ),
            );
          }
        });
        _scrollToBottom();

        // Keep keyboard open when receiving file completion messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _inputFocus.hasFocus) {
            _inputFocus.requestFocus();
          }
        });

        // Trigger showcase when first file is received
        if (wasFirstReceivedFile &&
            path != null &&
            !isOutgoing &&
            !_didShowFileReceivedShowcase) {
          _triggerFileReceivedShowcase();
        }
        // Trigger showcase for Download All when second file is received
        else if (wasSecondReceivedFile &&
            path != null &&
            !isOutgoing &&
            !_didShowFileReceivedShowcase) {
          _triggerDownloadAllShowcase();
        }
        break;
      default:
        // Play sound for received text messages (not sent by me)
        if (message.senderName != widget.myDeviceName &&
            message.type == 'text') {
          SoundService().playMessageReceived();
        }
        setState(() {
          if (!_messages.any(
            (m) =>
                m.timestamp == message.timestamp &&
                m.content == message.content,
          )) {
            _messages.add(message);
          }
        });
        _scrollToBottom();
        // Keep keyboard open when receiving messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _inputFocus.hasFocus) {
            _inputFocus.requestFocus();
          }
        });
    }
  }

  void _handleIncomingOffer(DeviceMessage message) async {
    // Support legacy flat metadata & nested payload
    Map<String, dynamic>? payload;
    final rawPayload = message.metadata?['payload'];
    if (rawPayload is Map<String, dynamic>) {
      payload = rawPayload;
    } else if (rawPayload is String) {
      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } catch (_) {}
    }

    final size = (message.metadata?['size'] ?? payload?['fileSize']) as int?;
    final mime = (message.metadata?['mime'] ?? payload?['mimeType']) as String?;
    final transferId =
        (message.metadata?['transferId'] ?? payload?['transferId']) as String?;

    if (transferId != null && _shownOfferDialogs.contains(transferId)) {
      debugPrint(
        '[ConnectionScreenRefactored] Duplicate offer dialog suppressed: $transferId',
      );
      return;
    }

    String name = message.content.trim();
    if (name.isEmpty) {
      final dynamicName =
          message.metadata?['fileName'] ??
          message.metadata?['name'] ??
          payload?['fileName'];
      if (dynamicName is String && dynamicName.trim().isNotEmpty) {
        name = dynamicName;
      } else {
        name = 'Unnamed file';
      }
    }

    if (transferId != null) _shownOfferDialogs.add(transferId);
    if (!mounted) return;

    // Auto-accept file transfers without showing confirmation dialog
    if (transferId != null) {
      // On Android and iOS, auto-accept to temp directory for speed
      // User can save/move file later from the completed file card
      String? saveDir;
      if (Theme.of(context).platform == TargetPlatform.macOS ||
          Theme.of(context).platform == TargetPlatform.linux ||
          Theme.of(context).platform == TargetPlatform.windows) {
        saveDir = await _chooseSaveDirEveryTime(context);
      }
      // For mobile (Android/iOS), saveDir remains null -> uses Documents directory
      await _connectionService.acceptFileOffer(transferId, saveDir: saveDir);
      setState(() {
        _incomingProgress[transferId] = TransferProgress(
          name: name,
          total: size ?? 0,
          mime: mime,
        );
      });
      _shownOfferDialogs.remove(transferId);
    } else if (transferId != null) {
      await _connectionService.declineFileOffer(transferId);
      _shownOfferDialogs.remove(transferId);
      setState(() {
        _messages.add(
          DeviceMessage(
            type: 'text',
            content: 'Declined file: $name',
            senderName: widget.myDeviceName,
          ),
        );
      });
    }
  }

  Future<String?> _chooseSaveDirEveryTime(BuildContext context) async {
    try {
      // 1. Check Preference first
      final prefs = await SharedPreferences.getInstance();
      String? savedPath = prefs.getString('download_save_path');

      if (savedPath != null) {
        // Validate it exists
        final dir = io.Directory(savedPath);
        if (await dir.exists()) {
          return savedPath;
        }
      }

      // 2. If no preference or invalid, Default to Downloads (Don't ask!)
      // The user explicitly requested to skip the file picker.
      final downloads = await getDownloadsDirectory();
      final defaultPath =
          (downloads ?? await getApplicationDocumentsDirectory()).path;

      // Save it for future consistent behavior
      await prefs.setString('download_save_path', defaultPath);

      return defaultPath;
    } catch (_) {
      // Fallback
      final downloads = await getDownloadsDirectory();
      return (downloads ?? await getApplicationDocumentsDirectory()).path;
    }
  }

  void _onStatusChanged(ConnectionInfo info) {
    print('ChatScreen: Connection status changed to: ${info.status}');
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _connectionInfo = info);
    });

    // Manage wake lock based on connection status
    if (info.status == ConnectionStatus.connected) {
      WakelockPlus.enable();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackbar.showSuccess(
          context,
          'Connected to ${info.deviceName}',
          duration: const Duration(seconds: 2),
        );
      });

      // Auto-send shared files when connection is established
      if (_sharedFiles.isNotEmpty) {
        print(
          'ChatScreen: Auto-send triggered - sharedFiles: ${_sharedFiles.length}',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          print(
            'ChatScreen: Executing auto-send for ${_sharedFiles.length} files',
          );
          _sendSharedFiles();
        });
      } else {
        print('ChatScreen: No shared files to auto-send');
      }
    } else if (info.status == ConnectionStatus.disconnected) {
      WakelockPlus.disable();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackbar.showWarning(
          context,
          'Disconnected from ${info.deviceName}',
          duration: const Duration(seconds: 2),
        );
      });
    } else if (info.status == ConnectionStatus.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackbar.showError(
          context,
          'Connection failed: ${info.error ?? "Unknown error"}',
        );
      });
    }
  }

  void _scrollToBottom() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _isProgrammaticScroll = true;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        // Reset the flag after a short delay to allow the scroll to complete
        Future.delayed(const Duration(milliseconds: 100), () {
          _isProgrammaticScroll = false;
        });
      }
    });
  }

  Future<void> _pickAndSendFile() async {
    if (_isPickingFile) return;
    setState(() => _isPickingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        withReadStream: true,
        allowMultiple: true,
      );

      // Hide loader immediately after picking is done
      if (mounted) {
        setState(() => _isPickingFile = false);
      }

      if (result != null && result.files.isNotEmpty) {
        // Fire and forget (don't await transfer completion)
        _connectionService.sendFiles(result.files);
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final message = DeviceMessage(
      type: 'text',
      content: text,
      senderName: widget.myDeviceName,
    );
    final success = await _connectionService.sendMessage(message);
    if (success) {
      SoundService().playMessageSent();
      setState(() {
        _messages.add(message);
        _messageController.clear();
      });
      _scrollToBottom();
      // Keep keyboard open after sending
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputFocus.requestFocus();
        }
      });
    } else if (mounted) {
      AppSnackbar.showError(context, 'Failed to send message');
    }
  }

  void _sendSharedFiles() {
    print(
      'ChatScreen: _sendSharedFiles called with ${_sharedFiles.length} files',
    );
    if (_sharedFiles.isNotEmpty) {
      print('ChatScreen: Sending shared files to connection service');
      _connectionService.sendSharedFiles(_sharedFiles);
      setState(() {
        _sharedFiles = [];
      });
      _shareIntentService.clearSharedFiles();
      // Notify that files were sent
      widget.onFilesSent?.call();
      print('ChatScreen: Shared files sent and cleared');
    } else {
      print('ChatScreen: No shared files to send');
    }
  }

  Future<void> _disconnect() async {
    SoundService().playDisconnect();
    await _connectionService.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openFile(String path, String name) async {
    try {
      if (path.toLowerCase().endsWith('.apk')) {
        if (Theme.of(context).platform == TargetPlatform.android) {
          final status = await AppPermissions.runGuarded(
            () => Permission.requestInstallPackages.request(),
          );
          if (!status.isGranted) {
            if (mounted) {
              AppSnackbar.showWarning(context, 'Install permission denied');
            }
            return;
          }
        }
      }
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        AppSnackbar.showError(context, 'Open failed (${result.message})');
      }
    } catch (e) {
      try {
        final parent = io.File(path).parent.path;
        await OpenFilex.open(parent);
      } catch (_) {}
      if (mounted) {
        AppSnackbar.showError(context, 'Open failed: $e');
      }
    }
  }

  Future<void> _saveAll() async {
    // Get all received files that haven't been saved yet
    final unsavedFiles = _receivedFiles.where((file) {
      final actualPath = _savedFilePaths[file.path] ?? file.path;
      return io.File(actualPath).existsSync();
    }).toList();

    if (unsavedFiles.isEmpty) {
      if (mounted) {
        AppSnackbar.showInfo(context, 'All files have already been saved');
      }
      return;
    }

    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    // On iOS, share all files
    if (isIOS) {
      final xFiles = unsavedFiles
          .map((f) => XFile(_savedFilePaths[f.path] ?? f.path))
          .toList();
      await Share.shareXFiles(xFiles);
      return;
    }

    // On Android and Desktop, use directory picker
    String? targetDir;
    try {
      targetDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle:
            'Choose destination folder for ${unsavedFiles.length} files',
      );
    } catch (e) {
      debugPrint('[SaveAll] Directory picker error: $e');
    }

    // User cancelled
    if (targetDir == null || targetDir.isEmpty) {
      return;
    }

    int successCount = 0;
    int failCount = 0;

    for (final file in unsavedFiles) {
      final actualSourcePath = _savedFilePaths[file.path] ?? file.path;
      final safeName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      String destPath = '$targetDir/$safeName';

      // Handle duplicate names
      int dup = 1;
      while (await io.File(destPath).exists()) {
        final dot = safeName.lastIndexOf('.');
        if (dot > 0) {
          final base = safeName.substring(0, dot);
          final ext = safeName.substring(dot);
          destPath = '$targetDir/$base($dup)$ext';
        } else {
          destPath = '$targetDir/$safeName($dup)';
        }
        dup++;
      }

      try {
        final sourceFile = io.File(actualSourcePath);
        try {
          await sourceFile.rename(destPath);
        } catch (moveError) {
          await sourceFile.copy(destPath);
          try {
            await sourceFile.delete();
          } catch (e) {
            debugPrint('[SaveAll] Failed to delete temp file: $e');
          }
        }

        // Track the new path
        setState(() {
          _savedFilePaths[file.path] = destPath;
        });
        successCount++;
      } catch (e) {
        debugPrint('[SaveAll] Failed to save ${file.name}: $e');
        failCount++;
      }
    }

    if (mounted) {
      AppSnackbar.show(
        context,
        successCount > 0
            ? 'Saved $successCount file${successCount > 1 ? 's' : ''} to: $targetDir${failCount > 0 ? '\n$failCount failed' : ''}'
            : 'Failed to save files',
        type: successCount > 0 ? SnackbarType.success : SnackbarType.error,
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _saveAs(String sourcePath, String originalName) async {
    // Check if using saved path instead of original
    final actualSourcePath = _savedFilePaths[sourcePath] ?? sourcePath;

    // Check if file exists at the source path
    if (!await io.File(actualSourcePath).exists()) {
      if (mounted) {
        AppSnackbar.showInfo(
          context,
          'File has already been saved and is no longer in temp location',
          duration: const Duration(seconds: 3),
        );
      }
      return;
    }

    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    // On iOS, use Share sheet for better UX
    if (isIOS) {
      await Share.shareXFiles([XFile(actualSourcePath)], text: originalName);
      return;
    }

    // On Android and Desktop, use directory picker (no storage permission needed with SAF)
    String? targetDir;
    try {
      targetDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose destination folder',
      );
    } catch (e) {
      debugPrint('[SaveAs] Directory picker error: $e');
    }

    // User cancelled the picker
    if (targetDir == null || targetDir.isEmpty) {
      return;
    }

    final safeName = originalName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    String destPath = '$targetDir/$safeName';
    int dup = 1;
    while (await io.File(destPath).exists()) {
      final dot = safeName.lastIndexOf('.');
      if (dot > 0) {
        final base = safeName.substring(0, dot);
        final ext = safeName.substring(dot);
        destPath = '$targetDir/$base($dup)$ext';
      } else {
        destPath = '$targetDir/$safeName($dup)';
      }
      dup++;
    }
    try {
      final sourceFile = io.File(actualSourcePath);

      // Use move instead of copy to avoid duplicating storage
      // If move fails (cross-partition), fall back to copy
      try {
        await sourceFile.rename(destPath);
        debugPrint('[SaveAs] File moved to: $destPath');
      } catch (moveError) {
        debugPrint('[SaveAs] Move failed, falling back to copy: $moveError');
        await sourceFile.copy(destPath);
        // Delete temp file after successful copy
        try {
          await sourceFile.delete();
          debugPrint('[SaveAs] Temp file deleted after copy');
        } catch (e) {
          debugPrint('[SaveAs] Failed to delete temp file: $e');
        }
      }

      // Track the new path for future save attempts
      setState(() {
        _savedFilePaths[sourcePath] = destPath;
      });

      if (mounted) {
        AppSnackbar.showSuccess(context, 'Saved to: $destPath');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, 'Save failed: $e');
      }
    }
  }

  void _triggerFileReceivedShowcase() async {
    _didShowFileReceivedShowcase = true;
    final prefs = await SharedPreferences.getInstance();
    final hasSeenFileShowcase =
        prefs.getBool('file_received_showcase_seen') ?? false;

    if (!hasSeenFileShowcase && mounted) {
      // Delay to ensure widgets are built
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          try {
            final showcaseKeys = <GlobalKey>[];

            // Add file card showcase
            showcaseKeys.add(ShowcaseHelper.receivedFileCardKey);
            showcaseKeys.add(ShowcaseHelper.saveButtonKey);

            // Add download all if multiple files
            if (_receivedFiles.length > 1) {
              showcaseKeys.add(ShowcaseHelper.downloadAllKey);
            }

            ShowCaseWidget.of(context).startShowCase(showcaseKeys);
            prefs.setBool('file_received_showcase_seen', true);
          } catch (e) {
            debugPrint('[ChatScreen] Error starting file showcase: $e');
          }
        }
      });
    }
  }

  void _triggerDownloadAllShowcase() async {
    _didShowFileReceivedShowcase = true;
    final prefs = await SharedPreferences.getInstance();
    final hasSeenFileShowcase =
        prefs.getBool('file_received_showcase_seen') ?? false;

    if (!hasSeenFileShowcase && mounted) {
      // Delay to ensure Download All button is rendered
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          try {
            // Only show Download All showcase
            ShowCaseWidget.of(
              context,
            ).startShowCase([ShowcaseHelper.downloadAllKey]);
            prefs.setBool('file_received_showcase_seen', true);
          } catch (e) {
            debugPrint('[ChatScreen] Error starting download all showcase: $e');
          }
        }
      });
    }
  }

  void _checkPendingFileOffers() {
    // Delay to ensure build complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pendingOffers = _connectionService.pendingOffers;
      for (final entry in pendingOffers.entries) {
        final transferId = entry.key;
        final offer = entry.value;
        final offerMessage = DeviceMessage(
          type: 'file_offer',
          content: offer.fileName,
          senderName: _connectionService.deviceName,
          timestamp: DateTime.now(),
          metadata: {
            'transferId': transferId,
            'size': offer.fileSize,
            'mime': offer.mimeType,
          },
        );
        _handleIncomingOffer(offerMessage);
      }
    });
  }

  String _statusText() {
    if (_isConnecting ||
        _connectionInfo?.status == ConnectionStatus.connecting) {
      return 'Connecting...';
    } else if (_connectionInfo?.status == ConnectionStatus.connected) {
      return 'Connected';
    } else if (_connectionInfo?.status == ConnectionStatus.failed) {
      return 'Connection Failed';
    } else if (_connectionInfo?.status == ConnectionStatus.disconnected) {
      return 'Disconnected';
    }
    // Don't show IP address - show disconnected status instead
    return 'Disconnected';
  }

  String _remoteDeviceName() {
    // Use the device name from ConnectionInfo if available (updated after handshake)
    // Otherwise fall back to the initial device name from widget
    return _connectionInfo?.deviceName ?? widget.deviceName;
  }

  void _showReceivedFilesSheet() {
    showAppBottomSheet(
      context: context,
      title: 'Received Files',
      subtitle: 'Files from this chat',
      maxHeightFactor: 0.6,
      contentPadding: const EdgeInsets.only(top: 16),
      child: ReceivedFilesSheet(
        files: _receivedFiles,
        onOpen: (path, name) => _openFile(path, name),
        onReveal: (dirPath, _) async {
          try {
            await OpenFilex.open(io.File(dirPath).path);
          } catch (e) {
            if (mounted) {
              AppSnackbar.showError(context, 'Reveal failed: $e');
            }
          }
        },
        onSaveAs: (path, name) => _saveAs(path, name),
      ),
    );
  }

  void _showAllConnectedDevices() {
    showAppBottomSheet(
      context: context,
      title: 'Connected Devices',
      subtitle: 'Switch to another chat',
      maxHeightFactor: 0.6,
      contentPadding: const EdgeInsets.only(top: 16),
      child: ConnectedDevicesBottomSheet(
        staticConnections: widget.connectionManager.activeConnections.entries
            .toList(),
        currentDeviceId: widget.initialDeviceId ?? widget.deviceName,
        onDeviceTap: (deviceId, [ipAddress, port, onFilesSent]) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                deviceName: deviceId,
                ipAddress: ipAddress ?? '',
                port: port ?? 53318,
                myDeviceName: widget.myDeviceName,
                connectionManager: widget.connectionManager,
                initialDeviceId: deviceId,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Trigger showcase only on first chat session
    if (!_didStartShowcase) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final prefs = await SharedPreferences.getInstance();
        final hasSeenShowcase =
            prefs.getBool('p2p_chat_showcase_seen') ?? false;

        if (!hasSeenShowcase && mounted) {
          // Skip showcase on web to prevent layout crashes
          if (kIsWeb) {
            prefs.setBool('p2p_chat_showcase_seen', true);
            return;
          }

          // Add delay and additional frame check for mobile compatibility
          await Future.delayed(const Duration(milliseconds: 1000));
          if (!mounted) return;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            Future.delayed(const Duration(milliseconds: 300), () {
              if (!mounted) return;

              try {
                // Only showcase widgets that are guaranteed to be present
                final showcaseKeys = <GlobalKey>[
                  ShowcaseHelper.sendFileButtonKey,
                ];

                if (_receivedFiles.isNotEmpty) {
                  showcaseKeys.add(ShowcaseHelper.receivedListKey);
                }
                if (_connectionInfo?.status == ConnectionStatus.connected) {
                  showcaseKeys.add(ShowcaseHelper.disconnectKey);
                }

                ShowCaseWidget.of(context).startShowCase(showcaseKeys);
                prefs.setBool('p2p_chat_showcase_seen', true);
              } catch (e) {
                // Silently ignore showcase errors
                debugPrint('Chat showcase initialization failed: $e');
              }
            });
          });
        }
      });
      _didStartShowcase = true;
    }

    // Check if keyboard just opened and scroll to bottom
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (isKeyboardOpen && !_wasKeyboardOpen && _messages.isNotEmpty) {
      // Delay scrolling to ensure keyboard is fully open
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _inputFocus.hasFocus) {
            _scrollToBottom();
          }
        });
      });
    }
    _wasKeyboardOpen = isKeyboardOpen;

    final isConnected = _connectionInfo?.status == ConnectionStatus.connected;
    // print(
    //   'ChatScreen: isConnected = $isConnected, sharedFiles = ${_sharedFiles.length}',
    // );
    print(
      'ChatScreen: Build - isConnected = $isConnected, sharedFiles = ${_sharedFiles.length}, connectionInfo = ${_connectionInfo?.status}',
    );
    // ignore: deprecated_member_use
    return ShowCaseWidget(
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
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
                      ChatTopBar(
                        deviceName: _remoteDeviceName(),
                        statusText: _statusText(),
                        receivedFilesCount: _receivedFiles.length,
                        connectionsCount:
                            widget.connectionManager.activeConnections.length,
                        onBack: () => Navigator.of(context).pop(),
                        onShowReceivedFiles: _showReceivedFilesSheet,
                        onShowDevices: _showAllConnectedDevices,
                        onDisconnect: isConnected ? _disconnect : null,
                        onSaveAll: _receivedFiles.length > 1 ? _saveAll : null,
                        connectionManager: widget.connectionManager,
                        isConnected: isConnected,
                      ),
                      if (_isConnecting ||
                          _connectionInfo?.status ==
                              ConnectionStatus.connecting)
                        ConnectingBanner(deviceName: _remoteDeviceName()),
                      if (_connectionInfo?.status == ConnectionStatus.failed)
                        ErrorBanner(
                          error: _connectionInfo?.error,
                          onRetry: _connectToDevice,
                        ),
                      WiFiDirectBanner(
                        statusNotifier:
                            _connectionService.wifiDirectStatusNotifier,
                        canConnect: _connectionService.canConnectWifiDirect,
                        onConnect: () async {
                          await _connectionService.connectWifiDirect();
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        onInfo: () {
                          if (!mounted) return;

                          // Show connection details dialog
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Row(
                                children: [
                                  Icon(
                                    Icons.wifi_tethering,
                                    color: Colors.green,
                                  ),
                                  SizedBox(width: 12),
                                  Text('WiFi Direct Info'),
                                ],
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow(
                                    'Status',
                                    _connectionService.isUsingWifiDirect
                                        ? 'Connected (5GHz)'
                                        : 'Available (Not Connected)',
                                    _connectionService.isUsingWifiDirect
                                        ? Icons.check_circle
                                        : Icons.info_outline,
                                    _connectionService.isUsingWifiDirect
                                        ? Colors.green
                                        : Colors.blue,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(
                                    'Role',
                                    _connectionService.isUsingWifiDirect
                                        ? (_connectionService
                                                  .isWifiDirectGroupOwner
                                              ? 'Group Owner (Host)'
                                              : 'Client (Peer)')
                                        : 'Pending Negotiation',
                                    _connectionService.isUsingWifiDirect
                                        ? (_connectionService
                                                  .isWifiDirectGroupOwner
                                              ? Icons.router
                                              : Icons.devices)
                                        : Icons.hourglass_empty,
                                    Colors.blue,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(
                                    'Peer IP',
                                    _connectionService.wifiDirectIp ??
                                        'Not assigned',
                                    Icons.link,
                                    Colors.orange,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(
                                    'Peer Name',
                                    _connectionService.remoteWifiDirectName ??
                                        'Unknown',
                                    Icons.smartphone,
                                    Colors.purple,
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Divider(),
                                  ),
                                  Text(
                                    'Credentials (MAC)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildInfoRow(
                                    'Remote ID',
                                    _connectionService.remoteWifiDirectMac ??
                                        'Scanning...',
                                    Icons.radar,
                                    Colors.grey,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildInfoRow(
                                    'Local ID',
                                    _connectionService.localWifiDirectMac ??
                                        'Initializing...',
                                    Icons.fingerprint,
                                    Colors.grey,
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const TemporaryFilesWarningBanner(),
                      if (_lastTransferBytes != null &&
                          _lastTransferDuration != null)
                        TransferStatsBanner(
                          totalBytes: _lastTransferBytes!,
                          duration: _lastTransferDuration!,
                        ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            // Close keyboard when tapping outside input field
                            FocusScope.of(context).unfocus();
                          },
                          child: (() {
                            final totalItems =
                                _messages.length +
                                _incomingProgress.length +
                                _outgoingProgress.length;
                            if (totalItems == 0) {
                              return EmptyDataWidget();
                            }
                            return ListView.builder(
                              controller: _scrollController,
                              physics: const ClampingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              itemCount: totalItems,
                              itemBuilder: (context, index) {
                                if (index < _messages.length) {
                                  final msg = _messages[index];
                                  final isMine =
                                      msg.senderName == widget.myDeviceName;
                                  if (msg.type == 'file_complete') {
                                    // Use 'outgoing' metadata for file transfers to be more reliable
                                    final isOutgoing =
                                        msg.metadata?['outgoing'] as bool? ??
                                        isMine;
                                    final savedPath =
                                        msg.metadata?['path'] as String?;
                                    // Use updated path if file was saved
                                    final actualPath = savedPath != null
                                        ? (_savedFilePaths[savedPath] ??
                                              savedPath)
                                        : null;

                                    // Show showcase on first received file only
                                    final isFirstReceivedFile =
                                        !isOutgoing &&
                                        _messages
                                                .where(
                                                  (m) =>
                                                      m.type ==
                                                          'file_complete' &&
                                                      (m.metadata?['outgoing']
                                                                  as bool? ??
                                                              false) ==
                                                          false,
                                                )
                                                .first ==
                                            msg;

                                    return CompletedFileCard(
                                      message: msg,
                                      isMine: isOutgoing,
                                      savedPath: actualPath,
                                      onOpen: (p, n) => _openFile(p, n),
                                      onSaveAs: (p, n) => _saveAs(p, n),
                                      showShowcase: isFirstReceivedFile,
                                    );
                                  }
                                  if (msg.type == 'file_offer') {
                                    return const SizedBox.shrink();
                                  }
                                  return MessageBubble(
                                    message: msg,
                                    isMine: isMine,
                                  );
                                }
                                final extra = index - _messages.length;
                                final incomingKeys = _incomingProgress.keys
                                    .toList();
                                if (extra < incomingKeys.length) {
                                  final tId = incomingKeys[extra];
                                  return TransferProgressTile(
                                    progress: _incomingProgress[tId]!,
                                    onCancel: () {
                                      _connectionService.cancelTransfer(tId);
                                      setState(() {
                                        _incomingProgress.remove(tId);
                                        _outgoingProgress.remove(tId);
                                      });
                                    },
                                    onResume: () async {
                                      if (_incomingProgress.containsKey(tId)) {
                                        await _connectionService.resumeIncoming(
                                          tId,
                                        );
                                      } else if (_outgoingProgress.containsKey(
                                        tId,
                                      )) {
                                        await _connectionService.requestResume(
                                          tId,
                                        );
                                      }
                                    },
                                  );
                                }
                                final outExtra = extra - incomingKeys.length;
                                final outKeys = _outgoingProgress.keys.toList();
                                if (outExtra < outKeys.length) {
                                  final tId = outKeys[outExtra];
                                  return TransferProgressTile(
                                    progress: _outgoingProgress[tId]!,
                                    onCancel: () {
                                      _connectionService.cancelTransfer(tId);
                                      setState(() {
                                        _incomingProgress.remove(tId);
                                        _outgoingProgress.remove(tId);
                                      });
                                    },
                                    onResume: () async {
                                      if (_incomingProgress.containsKey(tId)) {
                                        await _connectionService.resumeIncoming(
                                          tId,
                                        );
                                      } else if (_outgoingProgress.containsKey(
                                        tId,
                                      )) {
                                        await _connectionService.requestResume(
                                          tId,
                                        );
                                      }
                                    },
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            );
                          })(),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) =>
                            SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 1),
                                end: Offset.zero,
                              ).animate(animation),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                        child:
                            (isConnected &&
                                MediaQuery.of(context).viewInsets.bottom == 0)
                            ? Showcase(
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
                                  fileIcons: fileIcons,
                                  fileIconIndex: _fileIconIndex,
                                  slideFromLeft: _slideFromLeft,
                                  isLoading: _isPickingFile,
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('hidden')),
                      ),
                      if (_sharedFiles.isNotEmpty &&
                          isConnected) // Auto-send enabled, banner disabled
                        // print('ChatScreen: Showing shared files banner, files: ${_sharedFiles.length}, connected: $isConnected');
                        SharedFilesBanner(
                          files: _sharedFiles,
                          onSend: _sendSharedFiles,
                        ),

                      MessageInputBar(
                        controller: _messageController,
                        focusNode: _inputFocus,
                        onSend: _sendMessage,
                        enabled: isConnected,
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
                        subtitle: 'Release to send files to this device',
                      ),
                    ]
                  : []),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
