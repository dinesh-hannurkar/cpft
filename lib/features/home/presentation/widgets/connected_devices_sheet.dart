import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/features/chat/models/connection_state.dart';
import 'package:cpft/features/chat/services/connection_manager.dart';
import 'package:cpft/features/chat/services/connection_service.dart';

/// Bottom sheet showing connected devices
class ConnectedDevicesBottomSheet extends StatefulWidget {
  final ConnectionManager connectionManager;
  final Function(String) onDeviceTap;

  const ConnectedDevicesBottomSheet({
    super.key,
    required this.connectionManager,
    required this.onDeviceTap,
  });

  @override
  State<ConnectedDevicesBottomSheet> createState() =>
      _ConnectedDevicesBottomSheetState();
}

class _ConnectedDevicesBottomSheetState
    extends State<ConnectedDevicesBottomSheet> {
  late List<MapEntry<String, ConnectionService>> _entries;
  Function(String, ConnectionService, bool)? _connectionListener;
  final Map<String, Function(ConnectionInfo)> _statusListeners = {};

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[ConnectedDevicesSheet] ============ INIT STATE ============',
    );
    debugPrint(
      '[ConnectedDevicesSheet] Active connections count: ${widget.connectionManager.activeConnections.length}',
    );
    debugPrint(
      '[ConnectedDevicesSheet] Connection keys: ${widget.connectionManager.activeConnections.keys.join(", ")}',
    );
    for (final entry in widget.connectionManager.activeConnections.entries) {
      debugPrint(
        '[ConnectedDevicesSheet]   - ${entry.key}: status=${entry.value.currentConnection?.status}, isConnected=${entry.value.isConnected}',
      );
    }
    _updateEntries();

    // Listen for new connections
    _connectionListener = (deviceName, service, isIncoming) {
      debugPrint(
        '[ConnectedDevicesSheet] New connection listener fired for $deviceName',
      );
      if (mounted) {
        _updateEntries();
        _addStatusListener(deviceName, service);
      }
    };
    widget.connectionManager.addConnectionListener(_connectionListener!);

    // Add status listeners for existing connections
    for (final entry in _entries) {
      debugPrint(
        '[ConnectedDevicesSheet] Adding status listener for existing connection: ${entry.key}',
      );
      _addStatusListener(entry.key, entry.value);
    }
  }

  void _addStatusListener(String deviceId, ConnectionService service) {
    if (_statusListeners.containsKey(deviceId)) return;

    void listener(ConnectionInfo info) {
      debugPrint(
        '[ConnectedDevicesSheet] Status changed for $deviceId: ${info.status}',
      );
      if (mounted) {
        _updateEntries();
      }
    }

    _statusListeners[deviceId] = listener;
    service.addStatusListener(listener);
  }

  void _updateEntries() {
    if (!mounted) return;
    setState(() {
      _entries = widget.connectionManager.activeConnections.entries.toList();
      debugPrint(
        '[ConnectedDevicesSheet] Updated entries: ${_entries.length} devices',
      );
      for (final entry in _entries) {
        debugPrint(
          '[ConnectedDevicesSheet]   Entry: ${entry.key}, status=${entry.value.currentConnection?.status}',
        );
      }
    });
  }

  @override
  void dispose() {
    if (_connectionListener != null) {
      widget.connectionManager.removeConnectionListener(_connectionListener!);
    }
    // Remove all status listeners
    for (final entry in _statusListeners.entries) {
      final service = widget.connectionManager.getConnection(entry.key);
      if (service != null) {
        service.removeStatusListener(entry.value);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Connected Devices',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_entries.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'No devices connected',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final deviceId = _entries[index].key;
                      final connection = _entries[index].value;
                      final status = connection.currentConnection?.status;
                      final connected = connection.isConnected;

                      return _DeviceListTile(
                        deviceId: deviceId,
                        status: status,
                        connected: connected,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onDeviceTap(deviceId);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Individual device list tile
class _DeviceListTile extends StatelessWidget {
  final String deviceId;
  final ConnectionStatus? status;
  final bool connected;
  final VoidCallback onTap;

  const _DeviceListTile({
    required this.deviceId,
    required this.status,
    required this.connected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Determine status display
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (status == ConnectionStatus.connected) {
      statusText = 'Connected';
      statusColor = AppColors.green;
      statusIcon = Icons.wifi;
    } else if (status == ConnectionStatus.connecting) {
      statusText = 'Connecting...';
      statusColor = Colors.blue;
      statusIcon = Icons.sync;
    } else if (status == ConnectionStatus.disconnected) {
      statusText = 'Disconnected';
      statusColor = Colors.orange;
      statusIcon = Icons.wifi_off;
    } else if (status == ConnectionStatus.failed) {
      statusText = 'Failed';
      statusColor = AppColors.red;
      statusIcon = Icons.error_outline;
    } else {
      statusText = 'Unknown';
      statusColor = Colors.grey;
      statusIcon = Icons.help_outline;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        vertical: 4,
        horizontal: 4,
      ),
      leading: CircleAvatar(
        backgroundColor: statusColor,
        child: Icon(statusIcon, color: Colors.white),
      ),
      title: Text(
        deviceId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        statusText,
        style: TextStyle(color: statusColor),
      ),
      trailing: connected
          ? IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Open Chat',
              onPressed: onTap,
            )
          : IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reconnect',
              onPressed: onTap,
            ),
      onTap: onTap,
    );
  }
}
