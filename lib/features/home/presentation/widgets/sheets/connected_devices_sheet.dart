import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/features/home/presentation/widgets/tiles/device_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:fylooo/features/chat/models/connection_state.dart';
import 'package:fylooo/features/chat/services/connection_manager.dart';
import 'package:fylooo/features/chat/services/connection_service.dart';

/// Bottom sheet showing connected devices
/// Can be used with ConnectionManager for live updates or static list
class ConnectedDevicesBottomSheet extends StatefulWidget {
  final ConnectionManager? connectionManager;
  final List<MapEntry<String, ConnectionService>>? staticConnections;
  final String? currentDeviceId;
  final Function(
    String deviceId, [
    String? ipAddress,
    int? port,
    VoidCallback? onFilesSent,
  ])?
  onDeviceTap;
  final VoidCallback? onFilesSent;
  final bool shouldPop;
  final bool isEmbedded;
  final bool asSliver;

  const ConnectedDevicesBottomSheet({
    super.key,
    this.connectionManager,
    this.staticConnections,
    this.currentDeviceId,
    this.onDeviceTap,
    this.onFilesSent,
    this.shouldPop = true,
    this.isEmbedded = false,
    this.asSliver = false,
  }) : assert(
         connectionManager != null || staticConnections != null,
         'Either connectionManager or staticConnections must be provided',
       );

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

    // Use static connections if provided, otherwise get from ConnectionManager
    if (widget.staticConnections != null) {
      _entries = widget.staticConnections!;
      return;
    }

    // Setup live updates with ConnectionManager
    if (widget.connectionManager != null) {
      // Initialize immediately to avoid LateInitializationError
      _entries = widget.connectionManager!.activeConnections.entries.toList();
      _updateEntries();

      // Listen for new connections
      _connectionListener = (deviceName, service, isIncoming) {
        if (mounted) {
          _updateEntries();
          _addStatusListener(deviceName, service);
        }
      };
      widget.connectionManager!.addConnectionListener(_connectionListener!);

      // Add status listeners for existing connections
      for (final entry in _entries) {
        _addStatusListener(entry.key, entry.value);
      }
    } else {
      _entries = [];
    }
  }

  void _addStatusListener(String deviceId, ConnectionService service) {
    if (_statusListeners.containsKey(deviceId)) return;

    void listener(ConnectionInfo info) {
      if (mounted) {
        _updateEntries();
      }
    }

    _statusListeners[deviceId] = listener;
    service.addStatusListener(listener);
  }

  void _updateEntries() {
    if (!mounted || widget.connectionManager == null) return;

    // Schedule update to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _entries = widget.connectionManager!.activeConnections.entries
              .toList();
        });
      }
    });
  }

  @override
  void dispose() {
    if (_connectionListener != null && widget.connectionManager != null) {
      widget.connectionManager!.removeConnectionListener(_connectionListener!);
    }
    // Remove all status listeners
    for (final entry in _statusListeners.entries) {
      final service = widget.connectionManager?.getConnection(entry.key);
      if (service != null) {
        service.removeStatusListener(entry.value);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asSliver) {
      if (_entries.isEmpty) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.devices_other, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No devices connected',
                    style: TextStyle(color: Colors.black54, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= _entries.length) return null;
          final entry = _entries[index];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDeviceItem(entry),
              if (index < _entries.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.skyBlue.withValues(alpha: 0.1),
                ),
            ],
          );
        }, childCount: _entries.length),
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: widget.isEmbedded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (_entries.isEmpty)
            Expanded(
              flex: widget.isEmbedded ? 1 : 0,
              child: const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(
                  child: Text(
                    'No devices connected',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                itemCount: _entries.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.skyBlue.withValues(alpha: 0.1),
                ),
                itemBuilder: (context, index) {
                  return _buildDeviceItem(_entries[index]);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(MapEntry<String, ConnectionService> entry) {
    final deviceId = entry.key;
    final connection = entry.value;

    // Get connection details
    final status = connection.currentConnection?.status;
    final connected = connection.isConnected;
    final isCurrentDevice = deviceId == widget.currentDeviceId;

    return DeviceListTile(
      deviceId: deviceId,
      status: status,
      connected: connected,
      isCurrentDevice: isCurrentDevice,
      onTap: connected
          ? () {
              if (widget.onDeviceTap != null) {
                final ipAddress = connection.currentConnection?.ipAddress ?? '';
                if (widget.shouldPop) {
                  Navigator.pop(context);
                }
                // Support both callback signatures
                if (ipAddress.isNotEmpty) {
                  widget.onDeviceTap!(
                    deviceId,
                    ipAddress,
                    53318,
                    widget.onFilesSent,
                  );
                } else {
                  widget.onDeviceTap!(deviceId, null, null, widget.onFilesSent);
                }
              }
            }
          : null,
    );
  }
}
