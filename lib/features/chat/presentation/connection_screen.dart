import 'dart:io' as io;
import 'dart:async';
import 'dart:convert';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart'; // For MissingPluginException
import 'package:cpft/shared/widgets/dialog_helpers.dart' as app_dialog;
import 'package:cpft/shared/widgets/app_confirm_dialog.dart';

import '../models/connection_state.dart';
import '../services/connection_service.dart';
import '../services/connection_manager.dart';

class ConnectionScreen extends StatefulWidget {
  final String deviceName;
  final String ipAddress;
  final int port;
  final String myDeviceName;
  final ConnectionManager connectionManager;
  final String? initialDeviceId;

  const ConnectionScreen({
    super.key,
    required this.deviceName,
    required this.ipAddress,
    required this.port,
    required this.myDeviceName,
    required this.connectionManager,
    this.initialDeviceId,
  });

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with TickerProviderStateMixin {
  late ConnectionService _connectionService;
  final List<DeviceMessage> _messages = [];
  // Transfer progress: transferId -> (received/total) and name
  final Map<String, _TransferProgress> _incomingProgress = {};
  final Map<String, _TransferProgress> _outgoingProgress = {};
  // Keep a simple history of received files for quick access
  final List<_ReceivedFile> _receivedFiles = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
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
  ConnectionInfo? _connectionInfo;
  bool _isConnecting = false;
  String _extensionTrim(String ext) {
    ext = ext.trim();
    if (ext.length > 6) ext = ext.substring(0, 6);
    return ext.toUpperCase();
  }

  void _showReceivedFilesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) {
        if (_receivedFiles.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('No received files yet')),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _receivedFiles.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final rf = _receivedFiles[index];
            return ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: Text(
                rf.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                rf.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: PopupMenuButton<String>(
                color: Colors.white,
                onSelected: (value) async {
                  if (value == 'open') {
                    await OpenFilex.open(rf.path);
                  } else if (value == 'reveal') {
                    try {
                      final parent = rf.path.contains('/')
                          ? rf.path.substring(0, rf.path.lastIndexOf('/'))
                          : rf.path;
                      await OpenFilex.open(parent);
                    } catch (_) {
                      await OpenFilex.open(rf.path);
                    }
                  } else if (value == 'saveas') {
                    await _saveAs(rf.path, rf.name);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'open', child: Text('Open')),
                  const PopupMenuItem(
                    value: 'reveal',
                    child: Text('Reveal in Folder'),
                  ),
                  const PopupMenuItem(
                    value: 'saveas',
                    child: Text('Save As...'),
                  ),
                ],
              ),
              onTap: () async {
                await OpenFilex.open(rf.path);
              },
            );
          },
        );
      },
    );
  }

  // Use a different port for peer-to-peer connections (53318)
  static const int p2pPort = 53318;

  @override
  void initState() {
    super.initState();

    // Use initialDeviceId if provided, otherwise use the widget.deviceName
    final targetDeviceName = widget.initialDeviceId ?? widget.deviceName;

    // Get or create connection service from the shared ConnectionManager
    _connectionService = widget.connectionManager.getOrCreateConnection(
      targetDeviceName,
    );

    // Preload existing history filtering out any unexpected types (defensive)
    _messages.addAll(
      _connectionService.messageHistory.where((m) => const {
        'text', 'file_complete', 'goodbye'
      }.contains(m.type)),
    );

    _connectionService.addMessageListener(_onMessageReceived);
    _connectionService.addStatusListener(_onStatusChanged);
    _connectionInfo = _connectionService.currentConnection;
    _inputFocus.addListener(() => setState(() {}));

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

    // Check if already connected (incoming connection case)
    if (_connectionService.isConnected) {
      print('[ConnectionScreen] Already connected to ${_connectionService.deviceName}');
      _connectionInfo = _connectionService.currentConnection;
    } else if (_connectionInfo?.status == ConnectionStatus.connecting) {
      // Avoid starting an outgoing connection while an incoming connection is being established
      print(
        '[ConnectionScreen] Connection to ${_connectionService.deviceName} is already in progress (incoming). Not starting outgoing connect.',
      );
    } else {
      // Not connected yet - initiate outgoing connection
      _connectToDevice();
    }
    
    // Check for pending file offers and show dialogs
    _checkPendingFileOffers();
  }

  /// Check for any pending file offers and show dialogs for them
  void _checkPendingFileOffers() {
    // Wait a bit for the screen to be fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      final pendingOffers = _connectionService.pendingOffers;
      debugPrint('[ConnectionScreen] Checking pending offers: ${pendingOffers.length}');
      
      for (final entry in pendingOffers.entries) {
        final transferId = entry.key;
        final offer = entry.value;
        
        debugPrint('[ConnectionScreen] Showing dialog for pending offer: ${offer.fileName}');
        
        // Create a DeviceMessage for the offer to use existing handler
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

  @override
  void dispose() {
    // Remove listeners but don't dispose the service - it's managed by ConnectionManager
    _connectionService.removeMessageListener(_onMessageReceived);
    _connectionService.removeStatusListener(_onStatusChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _fileIconTimer?.cancel();
    _fileIconPulse?.dispose();
    super.dispose();
  }

  Future<void> _connectToDevice() async {
    setState(() {
      _isConnecting = true;
    });

    // Use dedicated P2P port (53318) instead of HTTP server port (53317)
    final success = await _connectionService.connect(
      _connectionService.deviceName,
      widget.ipAddress,
      p2pPort,
    );

    setState(() {
      _isConnecting = false;
    });

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect to ${_connectionService.deviceName}'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _connectToDevice,
          ),
        ),
      );
    }
  }

  void _onMessageReceived(DeviceMessage message) {
    if (mounted) {
      if (message.type == 'file_offer') {
        _handleIncomingOffer(message);
      } else if (message.type == 'file_progress') {
        final tId = message.metadata?['transferId'] as String?;
        final bytes = message.metadata?['bytes'] as int?;
        final total = message.metadata?['total'] as int?;
        final mime = message.metadata?['mime'] as String?;
        final outgoing = message.metadata?['outgoing'] as bool? ?? false;
        if (tId != null && bytes != null && total != null) {
          setState(() {
            final map = outgoing ? _outgoingProgress : _incomingProgress;
            map.putIfAbsent(
              tId,
              () => _TransferProgress(
                name: message.content,
                total: total,
                mime: mime,
              ),
            );
            map[tId]!.updateProgress(bytes.toDouble());
          });
        }
      } else if (message.type == 'file_complete') {
        // Preserve the original message so UI can show actions (Open/Reveal/Save As)
        final tId = message.metadata?['transferId'] as String?;
        final path = message.metadata?['path'] as String?;
        setState(() {
          // Skip if already in messages (preloaded from history or already added)
          if (!_messages.any((m) => m.timestamp == message.timestamp && m.content == message.content)) {
            _messages.add(message);
          }
          if (tId != null) {
            _incomingProgress.remove(tId);
            _outgoingProgress.remove(tId);
          }
          if (path != null && path.isNotEmpty) {
            _receivedFiles.add(
              _ReceivedFile(
                name: message.content,
                path: path,
                timestamp: message.timestamp,
              ),
            );
          }
        });
      } else {
        setState(() {
          // Skip if already in messages (preloaded from history or already added)
          if (!_messages.any((m) => m.timestamp == message.timestamp && m.content == message.content)) {
            _messages.add(message);
          }
        });
      }
      _scrollToBottom();
    }
  }

  void _handleIncomingOffer(DeviceMessage message) async {
    // Support both legacy flat metadata and nested 'payload'
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
    String name = message.content;
    if (name.trim().isEmpty) {
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
    debugPrint(
      '[ConnectionScreen] Incoming offer transferId=$transferId name="$name" size=$size mime=$mime rawContent="${message.content}"',
    );
    // Show prompt
    if (!mounted) return;
    final accept = await app_dialog.showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppConfirmDialog(
        title: 'Incoming File Transfer',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: AppSizes.spaceBtwInputFields),
                _buildFileIcon(name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Extension badge
                          // if (name.contains('.') )
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            margin: const EdgeInsets.only(right: 6, top: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F2FD),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFBBDEFB),
                              ),
                            ),
                            child: Text(
                              _extensionTrim(name.split('.').last),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1565C0),
                                letterSpacing: .5,
                              ),
                            ),
                          ),
                          // Filename text
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (size != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _fmtBytes(size),
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (mime != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _readableMime(mime),
                            style: const TextStyle(
                              color: Colors.black45,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (size != null || mime != null) const SizedBox(height: 8),
            if (size != null && size > 50 * 1024 * 1024)
              Row(
                children: const [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orange,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Large file. Keep app in foreground for reliability.',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                  ),
                ],
              ),
          ],
        ),
        cancelLabel: 'Decline',
        confirmLabel: 'Accept',
      ),
    );
    if (accept == true) {
      // Start progress tracking
      if (transferId != null) {
        final saveDir = await _chooseSaveDirEveryTime(context);
        await _connectionService.acceptFileOffer(transferId, saveDir: saveDir);
        setState(() {
          _incomingProgress[transferId] = _TransferProgress(
            name: name,
            total: size ?? 0,
            mime: mime,
          );
        });
      }
    } else {
      if (transferId != null) {
        await _connectionService.declineFileOffer(transferId);
      }
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
    // Try a directory picker on desktop platforms
    try {
      if (Theme.of(context).platform == TargetPlatform.macOS ||
          Theme.of(context).platform == TargetPlatform.linux ||
          Theme.of(context).platform == TargetPlatform.windows ||
          Theme.of(context).platform == TargetPlatform.android) {
        final dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose a folder for received files',
        );
        if (dir != null) chosen = dir;
      }
    } catch (_) {}

    // Fallbacks
    if (chosen == null) {
      if (Theme.of(context).platform == TargetPlatform.iOS ||
          Theme.of(context).platform == TargetPlatform.android) {
        final docs = await getApplicationDocumentsDirectory();
        chosen = docs.path;
      } else {
        final downloads = await getDownloadsDirectory();
        chosen = (downloads ?? await getApplicationDocumentsDirectory()).path;
      }
    }

    return chosen;
  }

  void _onStatusChanged(ConnectionInfo info) {
    if (mounted) {
      setState(() {
        _connectionInfo = info;
      });

      // Show status changes
      if (info.status == ConnectionStatus.connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Connected to ${info.deviceName}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.white),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (info.status == ConnectionStatus.disconnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Disconnected from ${info.deviceName}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.white),
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (info.status == ConnectionStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Connection failed: ${info.error ?? "Unknown error"}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
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
      setState(() {
        _messages.add(message);
        _messageController.clear();
      });
      _scrollToBottom();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to send message',
            style: TextStyle(color: AppColors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    await _connectionService.disconnect();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _tryShareFile(String sourcePath, String originalName) async {
    try {
      await Share.shareXFiles([XFile(sourcePath)], text: originalName);
    } on MissingPluginException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Share plugin not initialized. Rebuild app.',
            style: TextStyle(color: AppColors.white),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Share failed: $e',
            style: TextStyle(color: AppColors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionInfo?.status == ConnectionStatus.connected;
    return Scaffold(
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
              _buildTopBar(isConnected),
              if (_isConnecting ||
                  _connectionInfo?.status == ConnectionStatus.connecting)
                _buildConnectingBanner(),
              if (_connectionInfo?.status == ConnectionStatus.failed)
                _buildErrorBanner(),
              Expanded(
                child: (() {
                  final totalItems =
                      _messages.length +
                      _incomingProgress.length +
                      _outgoingProgress.length;
                  if (totalItems == 0) {
                    return _buildEmptyState();
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
                        return _buildMessageBubble(_messages[index]);
                      }
                      final extra = index - _messages.length;
                      final incomingKeys = _incomingProgress.keys.toList();
                      if (extra < incomingKeys.length) {
                        final tId = incomingKeys[extra];
                        return _buildProgressTile(_incomingProgress[tId]!);
                      }
                      final outExtra = extra - incomingKeys.length;
                      final outKeys = _outgoingProgress.keys.toList();
                      if (outExtra < outKeys.length) {
                        final tId = outKeys[outExtra];
                        return _buildProgressTile(_outgoingProgress[tId]!);
                      }
                      return const SizedBox.shrink();
                    },
                  );
                })(),
              ),
              if (isConnected) _buildFileTaglineBar(),
              if (isConnected) _buildMessageInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isConnected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back, color: Colors.blue),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connected to ${_connectionService.deviceName}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
                Text(
                  _getStatusText(),
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          if (_receivedFiles.isNotEmpty)
            IconButton(
              tooltip: 'Received files',
              icon: const Icon(Icons.folder_open),
              onPressed: _showReceivedFilesSheet,
            ),
          if (isConnected)
            IconButton(
              tooltip: 'Disconnect',
              icon: const Icon(Icons.close),
              onPressed: _disconnect,
            ),
        ],
      ),
    );
  }

  Widget _buildFileTaglineBar() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: () async {
            await _connectionService.pickAndSendFile();
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 62, vertical: 14),
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
                    'Any file, any format—share it instantly.',
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
              onTap: () async {
                await _connectionService.pickAndSendFile();
              },
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

  Widget _buildProgressTile(_TransferProgress tp) {
    final percent = tp.total > 0
        ? (tp.progress / tp.total * 100).clamp(0, 100)
        : null;
    final now = DateTime.now();
    final stalled =
        now.difference(tp.lastUpdate).inSeconds >= 10 && // no updates for 10s
        tp.progress > 0 &&
        (tp.total == 0 || tp.progress < tp.total);
    final failed =
        now.difference(tp.lastUpdate).inSeconds >= 60 &&
        tp.progress > 0 &&
        (tp.total == 0 || tp.progress < tp.total);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.only(left: 12, right: 0, top: 0, bottom: 10),
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
        children: [
          Row(
            // crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFileIcon(tp.name),
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
                            border: Border.all(color: const Color(0xFFBBDEFB)),
                          ),
                          child: Text(
                            _extensionTrim(tp.name.split('.').last),
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
                            tp.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          color: Colors.white,
                          icon: const Icon(Icons.more_vert, size: 28),
                          onSelected: (val) async {
                            // Determine transferId for actions
                            String? tId;
                            for (final e in _incomingProgress.entries) {
                              if (e.value == tp) {
                                tId = e.key;
                                break;
                              }
                            }
                            if (tId == null) {
                              for (final e in _outgoingProgress.entries) {
                                if (e.value == tp) {
                                  tId = e.key;
                                  break;
                                }
                              }
                            }
                            if (val == 'cancel') {
                              if (tId != null) {
                                _connectionService.cancelTransfer(tId);
                                setState(() {
                                  _incomingProgress.remove(tId);
                                  _outgoingProgress.remove(tId);
                                });
                              }
                            } else if (val == 'resume') {
                              if (tId != null) {
                                // Try resume depending on direction
                                if (_incomingProgress.containsKey(tId)) {
                                  await _connectionService.resumeIncoming(tId);
                                } else if (_outgoingProgress.containsKey(tId)) {
                                  await _connectionService.requestResume(tId);
                                }
                              }
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'resume',
                              child: Text('Resume'),
                            ),
                            const PopupMenuItem(
                              value: 'cancel',
                              child: Text('Cancel'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (tp.mime != null)
                      Text(
                        _readableMime(tp.mime!),
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    if (tp.total > 0)
                      Text(
                        _fmtBytes(tp.total),
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: tp.total > 0
                      ? (tp.progress / tp.total).clamp(0.0, 1.0)
                      : null,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(
                    failed
                        ? Colors.redAccent
                        : (stalled ? Colors.orange : Colors.blue.shade400),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tp.total > 0
                        ? '${_fmtBytes(tp.progress.toInt())} / ${_fmtBytes(tp.total)}'
                        : 'Preparing…',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
                if (failed)
                  const Text(
                    'Failed',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (stalled)
                  const Text(
                    'Stalled',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (tp.speed > 0)
                  Text(
                    _fmtSpeed(tp.speed).replaceAll('/s', '/s'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(width: 8),
                if (percent != null)
                  Text(
                    '${percent.toStringAsFixed(0)}% completed',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                const SizedBox(width: 8),
                Text(
                  _formatTime(DateTime.now()),
                  style: const TextStyle(fontSize: 10, color: Colors.black38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build a file icon whose glyph & colors depend on file extension.
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

  String _readableMime(String mime) {
    final lower = mime.toLowerCase();
    if (lower.startsWith('image/')) return 'Image (${lower.split('/').last})';
    if (lower.startsWith('video/')) return 'Video (${lower.split('/').last})';
    if (lower.startsWith('audio/')) return 'Audio (${lower.split('/').last})';
    if (lower == 'application/pdf') return 'PDF document';
    if (lower.contains('zip') || lower.contains('compressed')) return 'Archive';
    if (lower.contains('text')) return 'Text';
    return mime; // fallback
  }

  String _fmtSpeed(double bytesPerSecond) {
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    double speed = bytesPerSecond;
    int unit = 0;
    while (speed >= 1024 && unit < units.length - 1) {
      speed /= 1024;
      unit++;
    }
    return '${speed.toStringAsFixed(speed < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
  }

  Widget _buildConnectingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.blue.shade100,
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Connecting to ${_connectionService.deviceName}...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.red.shade100,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade900),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _connectionInfo?.error ?? 'Connection failed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.red.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: _connectToDevice, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to start the conversation',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(DeviceMessage message) {
    final isMyMessage = message.senderName == widget.myDeviceName;
    final isFileComplete = message.type == 'file_complete';
    final savedPath = message.metadata?['path'] as String?;

    if (isFileComplete) {
      return _buildCompletedFileCard(message, isMyMessage, savedPath);
    }

    return Align(
      alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isMyMessage ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMyMessage ? 16 : 4),
            bottomRight: Radius.circular(isMyMessage ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.type == 'handshake')
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.handshake,
                    size: 16,
                    color: isMyMessage ? Colors.white70 : Colors.black54,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: isMyMessage ? Colors.white : Colors.black87,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              )
            else if (message.type == 'goodbye')
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.waving_hand,
                    size: 16,
                    color: isMyMessage ? Colors.white70 : Colors.black54,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: isMyMessage ? Colors.white : Colors.black87,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                message.content,
                style: TextStyle(
                  color: isMyMessage ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                color: isMyMessage ? Colors.white70 : Colors.black54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedFileCard(
    DeviceMessage message,
    bool isMyMessage,
    String? savedPath,
  ) {
    final name = message.content;
    final size = message.metadata?['size'] as int?;
    final mime = message.metadata?['mime'] as String?;

    return Align(
      alignment: isMyMessage ? Alignment.centerLeft : Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: savedPath != null
              ? () async {
                  await OpenFilex.open(savedPath);
                }
              : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMyMessage ? 4 : 16),
            bottomRight: Radius.circular(isMyMessage ? 16 : 4),
          ),
          splashColor: Colors.blue.withOpacity(0.08),
          highlightColor: Colors.blue.withOpacity(0.04),
          hoverColor: Colors.blue.withOpacity(0.03),
          mouseCursor: savedPath != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.only(
              left: 12,
              right: 12,
              top: 10,
              bottom: 6,
            ),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMyMessage ? 4 : 16),
                bottomRight: Radius.circular(isMyMessage ? 16 : 4),
              ),
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
                    _buildFileIcon(name),
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
                                  name.contains('.')
                                      ? _extensionTrim(name.split('.').last)
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
                                  name,
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
                          SizedBox(height: 4),
                          if (mime != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                _readableMime(mime),
                                style: const TextStyle(
                                  color: Colors.black45,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (size != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Row(
                                children: [
                                  Text(
                                    _fmtBytes(size),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatTime(message.timestamp),
                                    style: const TextStyle(
                                      color: Colors.black38,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                // if (savedPath != null && isMyMessage) ...[
                //   const SizedBox(height: 6),
                //   Wrap(
                //     alignment: WrapAlignment.start,
                //     spacing: 8,
                //     runSpacing: 0,
                //     children: [
                //       TextButton.icon(
                //         onPressed: () async {
                //           try {
                //             final parent = savedPath.contains('/')
                //                 ? savedPath.substring(0, savedPath.lastIndexOf('/'))
                //                 : savedPath;
                //             await OpenFilex.open(parent);
                //           } catch (_) {
                //             await OpenFilex.open(savedPath);
                //           }
                //         },
                //         icon: const Icon(Icons.folder_open, size: 16),
                //         label: const Text('Reveal'),
                //         style: TextButton.styleFrom(
                //           foregroundColor: Colors.blue.shade700,
                //           padding: const EdgeInsets.symmetric(horizontal: 10),
                //           minimumSize: const Size(0, 34),
                //           shape: RoundedRectangleBorder(
                //             borderRadius: BorderRadius.circular(8),
                //           ),
                //         ),
                //       ),
                //       TextButton.icon(
                //         onPressed: () async {
                //           await _saveAs(savedPath, name);
                //         },
                //         icon: const Icon(Icons.save_alt, size: 16),
                //         label: const Text('Save As'),
                //         style: TextButton.styleFrom(
                //           foregroundColor: Colors.blue.shade700,
                //           padding: const EdgeInsets.symmetric(horizontal: 10),
                //           minimumSize: const Size(0, 34),
                //           shape: RoundedRectangleBorder(
                //             borderRadius: BorderRadius.circular(8),
                //           ),
                //         ),
                //       ),
                //     ],
                //   ),
                // ],
                // Padding(
                //   padding: const EdgeInsets.only(top: 4.0),
                //   child: Row(
                //     children: [
                //       const Spacer(),
                //       Text(
                //         _formatTime(message.timestamp),
                //         style: const TextStyle(
                //           color: Colors.black38,
                //           fontSize: 10,
                //         ),
                //       ),
                //     ],
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final hasText = _messageController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Text field capsule with gradient border and white fill
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _inputFocus.hasFocus
                        ? [const Color(0xFF64B5F6), const Color(0xFF81D4FA)]
                        : [const Color(0xFFCAE6FF), const Color(0xFFE3F2FD)],
                  ),
                ),
                padding: const EdgeInsets.all(1.2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(27),
                  ),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    style: const TextStyle(color: Colors.black87),
                    cursorColor: Colors.blue,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Send button
            GestureDetector(
              onTap: hasText ? _sendMessage : null,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasText
                      ? const LinearGradient(
                          colors: [Color(0xFF2F80ED), Color(0xFF56CCF2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: hasText ? null : const Color(0xFFE9EEF3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.send,
                  size: 22,
                  color: hasText ? Colors.white : Colors.blueGrey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText() {
    if (_isConnecting ||
        _connectionInfo?.status == ConnectionStatus.connecting) {
      return 'Connecting...';
    } else if (_connectionInfo?.status == ConnectionStatus.connected) {
      return '${widget.ipAddress}:${widget.port} • Connected';
    } else if (_connectionInfo?.status == ConnectionStatus.failed) {
      return 'Connection Failed';
    } else if (_connectionInfo?.status == ConnectionStatus.disconnected) {
      return 'Disconnected';
    }
    return widget.ipAddress;
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _saveAs(String sourcePath, String originalName) async {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    if (isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Storage permission denied',
              style: TextStyle(color: AppColors.white),
            ),
          ),
        );
        return;
      }
    }

    String? targetDir;
    try {
      if (isAndroid) {
        targetDir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose destination folder',
        );
      } else if (!isIOS) {
        targetDir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose destination folder',
        );
      }
    } catch (_) {}

    if (isIOS && (targetDir == null || targetDir.isEmpty)) {
      await _tryShareFile(sourcePath, originalName);
      return; // Share sheet used; exit
    }

    if (targetDir == null || targetDir.isEmpty) {
      if (isAndroid || isIOS) {
        final docs = await getApplicationDocumentsDirectory();
        targetDir = docs.path;
      } else {
        final downloads = await getDownloadsDirectory();
        targetDir =
            (downloads ?? await getApplicationDocumentsDirectory()).path;
      }
    }

    final safeName = originalName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    String destPath = '$targetDir/$safeName';
    int dup = 1;
    while (await io.File(destPath).exists()) {
      final dot = safeName.lastIndexOf('.');
      if (dot > 0) {
        final base = safeName.substring(0, dot);
        final ext = safeName.substring(dot);
        destPath = '$targetDir/${base}($dup)$ext';
      } else {
        destPath = '$targetDir/${safeName}($dup)';
      }
      dup++;
    }

    try {
      await io.File(sourcePath).copy(destPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved to: $destPath',
            style: const TextStyle(color: AppColors.white),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Save failed: $e',
            style: const TextStyle(color: AppColors.white),
          ),
        ),
      );
    }
  }
}

class _TransferProgress {
  final String name;
  final int total; // 0 if unknown
  final String? mime;
  double progress; // bytes progressed (approx)
  DateTime lastUpdate;
  double lastBytes;
  double speed; // bytes per second

  _TransferProgress({required this.name, required this.total, this.mime})
    : progress = 0,
      lastUpdate = DateTime.now(),
      lastBytes = 0,
      speed = 0;

  void updateProgress(double newBytes) {
    final now = DateTime.now();
    final elapsed = now.difference(lastUpdate).inMilliseconds / 1000.0;
    if (elapsed > 0.1) {
      // Update speed every 100ms minimum
      final delta = newBytes - lastBytes;
      speed = delta / elapsed;
      lastUpdate = now;
      lastBytes = newBytes;
    }
    progress = newBytes;
  }

  void pulsate() {
    // If total unknown, keep indeterminate in UI (progress ignored)
    if (total > 0) {
      // Add a small step for visible movement; sender-side ack-based updates could replace this
      progress = (progress + (total * 0.01)).clamp(0, total).toDouble();
    }
  }
}

class _ReceivedFile {
  final String name;
  final String path;
  final DateTime timestamp;
  _ReceivedFile({
    required this.name,
    required this.path,
    required this.timestamp,
  });
}
