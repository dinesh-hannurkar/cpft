import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart'; // For MissingPluginException

import '../models/connection_state.dart';
import '../services/connection_service.dart';
import '../services/connection_manager.dart';

class ConnectionScreen extends StatefulWidget {
  final String deviceName;
  final String ipAddress;
  final int port;
  final String myDeviceName;
  final ConnectionManager connectionManager;

  const ConnectionScreen({
    super.key,
    required this.deviceName,
    required this.ipAddress,
    required this.port,
    required this.myDeviceName,
    required this.connectionManager,
  });

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late ConnectionService _connectionService;
  final List<DeviceMessage> _messages = [];
  // Transfer progress: transferId -> (received/total) and name
  final Map<String, _TransferProgress> _incomingProgress = {};
  final Map<String, _TransferProgress> _outgoingProgress = {};
  // Keep a simple history of received files for quick access
  final List<_ReceivedFile> _receivedFiles = [];
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ConnectionInfo? _connectionInfo;
  bool _isConnecting = false;

  void _showReceivedFilesSheet() {
    showModalBottomSheet(
      context: context,
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
              title: Text(rf.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(rf.path, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'open') {
                    await OpenFilex.open(rf.path);
                  } else if (value == 'reveal') {
                    try {
                      final parent = rf.path.contains('/') ? rf.path.substring(0, rf.path.lastIndexOf('/')) : rf.path;
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
                  const PopupMenuItem(value: 'reveal', child: Text('Reveal in Folder')),
                  const PopupMenuItem(value: 'saveas', child: Text('Save As...')),
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
    
    // Get or create connection service from the shared ConnectionManager
    _connectionService = widget.connectionManager.getOrCreateConnection(widget.deviceName);
    
    _connectionService.addMessageListener(_onMessageReceived);
    _connectionService.addStatusListener(_onStatusChanged);
    _connectionInfo = _connectionService.currentConnection;
    
    // Check if already connected (incoming connection case)
    if (_connectionService.isConnected) {
      print('[ConnectionScreen] Already connected to ${widget.deviceName}');
      _connectionInfo = _connectionService.currentConnection;
    } else if (_connectionInfo?.status == ConnectionStatus.connecting) {
      // Avoid starting an outgoing connection while an incoming connection is being established
      print('[ConnectionScreen] Connection to ${widget.deviceName} is already in progress (incoming). Not starting outgoing connect.');
    } else {
      // Not connected yet - initiate outgoing connection
      _connectToDevice();
    }
  }

  @override
  void dispose() {
    // Remove listeners but don't dispose the service - it's managed by ConnectionManager
    _connectionService.removeMessageListener(_onMessageReceived);
    _connectionService.removeStatusListener(_onStatusChanged);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _connectToDevice() async {
    setState(() {
      _isConnecting = true;
    });

    // Use dedicated P2P port (53318) instead of HTTP server port (53317)
    final success = await _connectionService.connect(
      widget.deviceName,
      widget.ipAddress,
      p2pPort,
    );

    setState(() {
      _isConnecting = false;
    });

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to connect to ${widget.deviceName}'),
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
        final outgoing = message.metadata?['outgoing'] as bool? ?? false;
        if (tId != null && bytes != null && total != null) {
          setState(() {
            final map = outgoing ? _outgoingProgress : _incomingProgress;
            map.putIfAbsent(tId, () => _TransferProgress(name: message.content, total: total));
            map[tId]!.updateProgress(bytes.toDouble());
          });
        }
      } else if (message.type == 'file_complete') {
        // Preserve the original message so UI can show actions (Open/Reveal/Save As)
        final tId = message.metadata?['transferId'] as String?;
        final path = message.metadata?['path'] as String?;
        setState(() {
          _messages.add(message);
          if (tId != null) {
            _incomingProgress.remove(tId);
            _outgoingProgress.remove(tId);
          }
          if (path != null && path.isNotEmpty) {
            _receivedFiles.add(_ReceivedFile(
              name: message.content,
              path: path,
              timestamp: message.timestamp,
            ));
          }
        });
      } else {
        setState(() {
          _messages.add(message);
        });
      }
      _scrollToBottom();
    }
  }

  void _handleIncomingOffer(DeviceMessage message) async {
  final size = message.metadata?['size'] as int?;
  final mime = message.metadata?['mime'] as String?;
  final transferId = message.metadata?['transferId'] as String?;
    final name = message.content;
    // Show prompt
    if (!mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Incoming file'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name),
              if (size != null) Text('Size: ${_fmtBytes(size)}'),
              if (mime != null) Text('Type: $mime'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Decline')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accept')),
          ],
        );
      },
    );
  if (accept == true) {
      // Start progress tracking
      if (transferId != null) {
    final saveDir = await _chooseSaveDirEveryTime(context);
    await _connectionService.acceptFileOffer(transferId, saveDir: saveDir);
        setState(() {
          _incomingProgress[transferId] = _TransferProgress(name: name, total: size ?? 0);
          _messages.add(DeviceMessage(type: 'text', content: 'Receiving: $name', senderName: message.senderName));
        });
      }
    } else {
      if (transferId != null) {
        await _connectionService.declineFileOffer(transferId);
      }
      setState(() {
        _messages.add(DeviceMessage(type: 'text', content: 'Declined file: $name', senderName: widget.myDeviceName));
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
        final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a folder for received files');
        if (dir != null) chosen = dir;
      }
    } catch (_) {}

    // Fallbacks
    if (chosen == null) {
      if (Theme.of(context).platform == TargetPlatform.iOS || Theme.of(context).platform == TargetPlatform.android) {
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
            content: Text('Connected to ${info.deviceName}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (info.status == ConnectionStatus.disconnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnected from ${info.deviceName}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (info.status == ConnectionStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${info.error ?? "Unknown error"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
          content: Text('Failed to send message'),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share plugin not initialized. Rebuild app.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionInfo?.status == ConnectionStatus.connected;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.deviceName),
            Text(
              _getStatusText(),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (_receivedFiles.isNotEmpty)
            IconButton(
              tooltip: 'Received files',
              icon: const Icon(Icons.folder_open),
              onPressed: _showReceivedFilesSheet,
            ),
          if (isConnected)
            IconButton(
              tooltip: 'Send file',
              icon: const Icon(Icons.attach_file),
              onPressed: () async {
                await _connectionService.pickAndSendFile();
              },
            ),
          // Removed persistent folder menu; we ask per transfer
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection status banner
          if (_isConnecting || _connectionInfo?.status == ConnectionStatus.connecting)
            _buildConnectingBanner(),
          if (_connectionInfo?.status == ConnectionStatus.failed)
            _buildErrorBanner(),

          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + _incomingProgress.length + _outgoingProgress.length,
                    itemBuilder: (context, index) {
                      // Render messages first
                      if (index < _messages.length) {
                        return _buildMessageBubble(_messages[index]);
                      }
                      // Then render progress items
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
                  ),
          ),

          // Message input (only show if connected)
          if (isConnected) _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildProgressTile(_TransferProgress tp) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          const Icon(Icons.file_present, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tp.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: tp.total > 0 ? (tp.progress / tp.total).clamp(0.0, 1.0) : null),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tp.total > 0 ? '${_fmtBytes(tp.progress.toInt())} / ${_fmtBytes(tp.total)}' : 'Receiving…',
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    if (tp.speed > 0)
                      Text(
                        _fmtSpeed(tp.speed),
                        style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.close),
            onPressed: () {
              // Find transferId and cancel via service
              String? tId;
              for (final e in _incomingProgress.entries) {
                if (e.value == tp) { tId = e.key; break; }
              }
              if (tId == null) {
                for (final e in _outgoingProgress.entries) {
                  if (e.value == tp) { tId = e.key; break; }
                }
              }
              if (tId == null) return;
              _connectionService.cancelTransfer(tId);
              setState(() {
                _incomingProgress.remove(tId);
                _outgoingProgress.remove(tId);
              });
            },
          ),
        ],
      ),
    );
  }

  String _fmtBytes(int bytes) {
    const units = ['B','KB','MB','GB','TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
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
              'Connecting to ${widget.deviceName}...',
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
          TextButton(
            onPressed: _connectToDevice,
            child: const Text('Retry'),
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
            'Send a message to start the conversation',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(DeviceMessage message) {
    final isMyMessage = message.senderName == widget.myDeviceName;
  final isFileComplete = message.type == 'file_complete';
  final savedPath = message.metadata?['path'] as String?;

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
            if (isFileComplete && savedPath != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      // Open file using default app
                      await OpenFilex.open(savedPath);
                    },
                    child: const Text('Open'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      // Reveal in folder (desktop platforms); fallback: open parent dir
                      try {
                        final parent = savedPath.contains('/') ? savedPath.substring(0, savedPath.lastIndexOf('/')) : savedPath;
                        await OpenFilex.open(parent);
                      } catch (_) {
                        await OpenFilex.open(savedPath);
                      }
                    },
                    child: const Text('Reveal'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      await _saveAs(savedPath, message.content);
                    },
                    child: const Text('Save As'),
                  ),
                ],
              ),
            ],
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

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.blue,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText() {
    if (_isConnecting || _connectionInfo?.status == ConnectionStatus.connecting) {
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Storage permission denied')));
        return;
      }
    }

    String? targetDir;
    try {
      if (isAndroid) {
        targetDir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose destination folder');
      } else if (!isIOS) {
        targetDir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose destination folder');
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
        targetDir = (downloads ?? await getApplicationDocumentsDirectory()).path;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to: $destPath')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }
}

class _TransferProgress {
  final String name;
  final int total; // 0 if unknown
  double progress; // bytes progressed (approx)
  DateTime lastUpdate;
  double lastBytes;
  double speed; // bytes per second
  
  _TransferProgress({required this.name, required this.total})
      : progress = 0,
        lastUpdate = DateTime.now(),
        lastBytes = 0,
        speed = 0;
  
  void updateProgress(double newBytes) {
    final now = DateTime.now();
    final elapsed = now.difference(lastUpdate).inMilliseconds / 1000.0;
    if (elapsed > 0.1) { // Update speed every 100ms minimum
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
  _ReceivedFile({required this.name, required this.path, required this.timestamp});
}
