import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:cpft/features/chat/presentation/widgets/constants/file_icons_list.dart';
import 'package:cpft/features/chat/presentation/widgets/empty_data_widget.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/services/sound_service.dart';
import 'package:cpft/shared/widgets/app_snackbar.dart';
import 'package:cpft/features/chat/models/transfer_progress.dart';
import 'package:cpft/features/chat/models/received_file.dart';
import 'package:cpft/features/chat/presentation/widgets/tiles/transfer_progress_tile.dart';
import 'package:cpft/features/chat/presentation/widgets/message_bubble.dart';
import 'package:cpft/features/chat/presentation/widgets/completed_file_card.dart';
import 'package:cpft/features/chat/presentation/widgets/received_files_sheet.dart';
import 'package:cpft/features/chat/presentation/widgets/chat_top_bar.dart';
import 'package:cpft/features/chat/presentation/widgets/connecting_banner.dart';
import 'package:cpft/features/chat/presentation/widgets/error_banner.dart';
import 'package:cpft/features/chat/presentation/widgets/file_tagline_bar.dart';
import 'package:cpft/features/chat/presentation/widgets/message_input_bar.dart';
import 'package:cpft/features/home/presentation/widgets/sheets/connected_devices_sheet.dart';
import 'package:cpft/shared/widgets/app_bottom_sheet.dart';
import 'package:cpft/shared/widgets/temporary_files_warning_banner.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:cpft/shared/showcase/showcase_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/connection_state.dart';
import '../services/connection_service.dart';
import '../services/connection_manager.dart';

class ChatScreen extends StatefulWidget {
  final String deviceName;
  final String ipAddress;
  final int port;
  final String myDeviceName;
  final ConnectionManager connectionManager;
  final String? initialDeviceId;

  const ChatScreen({
    super.key,
    required this.deviceName,
    required this.ipAddress,
    required this.port,
    required this.myDeviceName,
    required this.connectionManager,
    this.initialDeviceId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  late ConnectionService _connectionService;
  final List<DeviceMessage> _messages = [];
  final Map<String, TransferProgress> _incomingProgress = {};
  final Map<String, TransferProgress> _outgoingProgress = {};
  final Map<String, String> _savedFilePaths = {}; // Maps original path to new saved path
  final List<ReceivedFile> _receivedFiles = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  final Set<String> _shownOfferDialogs = {};

  int _fileIconIndex = 0;
  bool _slideFromLeft = true;
  AnimationController? _fileIconPulse;
  Timer? _fileIconTimer;

  ConnectionInfo? _connectionInfo;
  bool _isConnecting = false;
  bool _didStartShowcase = false;
  bool _didShowFileReceivedShowcase = false;

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
    _messages.addAll(_connectionService.messageHistory);

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

    // Check pending offers after frame
    _inputFocus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkPendingFileOffers(),
    );
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
        'Failed to connect to ${_connectionService.deviceName}',
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _connectToDevice,
        ),
      );
    }
  }

  void _onMessageReceived(DeviceMessage message) {
    if (!mounted) return;
    switch (message.type) {
      case 'file_offer':
        _handleIncomingOffer(message);
        break;
      case 'file_progress':
        final tId = message.metadata?['transferId'] as String?;
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
          });
          
          // Play sound when transfer starts (first progress update)
          if (isNewTransfer) {
            SoundService().playTransferStart();
          }
        }
        break;
      case 'file_pending':
        final tId = message.metadata?['transferId'] as String?;
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
        final path = message.metadata?['path'] as String?;
        final isOutgoing = message.metadata?['outgoing'] as bool? ?? false;
        final wasFirstReceivedFile = _receivedFiles.isEmpty && !isOutgoing;
        final wasSecondReceivedFile = _receivedFiles.length == 1 && !isOutgoing;
        
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
        
        // Trigger showcase when first file is received
        if (wasFirstReceivedFile && path != null && !isOutgoing && !_didShowFileReceivedShowcase) {
          _triggerFileReceivedShowcase();
        }
        // Trigger showcase for Download All when second file is received
        else if (wasSecondReceivedFile && path != null && !isOutgoing && !_didShowFileReceivedShowcase) {
          _triggerDownloadAllShowcase();
        }
        break;
      default:
        // Play sound for received text messages (not sent by me)
        if (message.senderName != widget.myDeviceName && message.type == 'text') {
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
    String? chosen;
    try {
      // Only ask for directory on desktop platforms
      if (Theme.of(context).platform == TargetPlatform.macOS ||
          Theme.of(context).platform == TargetPlatform.linux ||
          Theme.of(context).platform == TargetPlatform.windows) {
        final dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose a folder for received files',
        );
        if (dir != null) chosen = dir;
      }
    } catch (_) {}
    // Fallback to default directories
    if (chosen == null) {
      final downloads = await getDownloadsDirectory();
      chosen = (downloads ?? await getApplicationDocumentsDirectory()).path;
    }
    return chosen;
  }

  void _onStatusChanged(ConnectionInfo info) {
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
        AppSnackbar.showSuccess(context, 'Connected to ${info.deviceName}', duration: const Duration(seconds: 2));
      });
    } else if (info.status == ConnectionStatus.disconnected) {
      WakelockPlus.disable();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackbar.showWarning(context, 'Disconnected from ${info.deviceName}', duration: const Duration(seconds: 2));
      });
    } else if (info.status == ConnectionStatus.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackbar.showError(context, 'Connection failed: ${info.error ?? "Unknown error"}');
      });
    }
  }

  void _scrollToBottom() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
    } else if (mounted) {
      AppSnackbar.showError(context, 'Failed to send message');
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
          final status = await Permission.requestInstallPackages.request();
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
        dialogTitle: 'Choose destination folder for ${unsavedFiles.length} files',
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
        AppSnackbar.showInfo(context, 'File has already been saved and is no longer in temp location', duration: const Duration(seconds: 3));
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
    final hasSeenFileShowcase = prefs.getBool('file_received_showcase_seen') ?? false;
    
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
    final hasSeenFileShowcase = prefs.getBool('file_received_showcase_seen') ?? false;
    
    if (!hasSeenFileShowcase && mounted) {
      // Delay to ensure Download All button is rendered
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          try {
            // Only show Download All showcase
            ShowCaseWidget.of(context).startShowCase([
              ShowcaseHelper.downloadAllKey,
            ]);
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
      // return '${widget.ipAddress}:${widget.port} • Connected';
      return 'Connected';
    } else if (_connectionInfo?.status == ConnectionStatus.failed) {
      return 'Connection Failed';
    } else if (_connectionInfo?.status == ConnectionStatus.disconnected) {
      return 'Disconnected';
    }
    return widget.ipAddress;
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
        onDeviceTap: (deviceId, [ipAddress, port]) {
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
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
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
              } catch (_) {}
            }
          });
        }
      });
      _didStartShowcase = true;
    }

    final isConnected = _connectionInfo?.status == ConnectionStatus.connected;
    // ignore: deprecated_member_use
    return ShowCaseWidget(
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
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
                ChatTopBar(
                  deviceName: _connectionService.deviceName,
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
                    _connectionInfo?.status == ConnectionStatus.connecting)
                  ConnectingBanner(deviceName: _connectionService.deviceName),
                if (_connectionInfo?.status == ConnectionStatus.failed)
                  ErrorBanner(
                    error: _connectionInfo?.error,
                    onRetry: _connectToDevice,
                  ),
                const TemporaryFilesWarningBanner(),
                Expanded(
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: totalItems,
                      itemBuilder: (context, index) {
                        if (index < _messages.length) {
                          final msg = _messages[index];
                          final isMine = msg.senderName == widget.myDeviceName;
                          if (msg.type == 'file_complete') {
                            // Use 'outgoing' metadata for file transfers to be more reliable
                            final isOutgoing =
                                msg.metadata?['outgoing'] as bool? ?? isMine;
                            final savedPath = msg.metadata?['path'] as String?;
                            // Use updated path if file was saved
                            final actualPath = savedPath != null ? (_savedFilePaths[savedPath] ?? savedPath) : null;
                            
                            // Show showcase on first received file only
                            final isFirstReceivedFile = !isOutgoing && 
                                _messages.where((m) => 
                                  m.type == 'file_complete' && 
                                  (m.metadata?['outgoing'] as bool? ?? false) == false
                                ).first == msg;
                            
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
                          return MessageBubble(message: msg, isMine: isMine);
                        }
                        final extra = index - _messages.length;
                        final incomingKeys = _incomingProgress.keys.toList();
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
                                await _connectionService.resumeIncoming(tId);
                              } else if (_outgoingProgress.containsKey(tId)) {
                                await _connectionService.requestResume(tId);
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
                                await _connectionService.resumeIncoming(tId);
                              } else if (_outgoingProgress.containsKey(tId)) {
                                await _connectionService.requestResume(tId);
                              }
                            },
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  })(),
                ),
                if (isConnected)
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
                      onTapMain: () => _connectionService.pickAndSendFile(),
                      onTapFab: () => _connectionService.pickAndSendFile(),
                      pulseController: _fileIconPulse!,
                      fileIcons: fileIcons,
                      fileIconIndex: _fileIconIndex,
                      slideFromLeft: _slideFromLeft,
                    ),
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
      ),
    );
  }
}
