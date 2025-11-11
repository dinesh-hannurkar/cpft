import 'package:flutter/material.dart';

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
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ConnectionInfo? _connectionInfo;
  bool _isConnecting = false;
  
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
      setState(() {
        _messages.add(message);
      });
      _scrollToBottom();
    }
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
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),

          // Message input (only show if connected)
          if (isConnected) _buildMessageInput(),
        ],
      ),
    );
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
}
