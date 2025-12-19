import 'package:cpft/features/home/presentation/widgets/tiles/device_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:cpft/features/chat/models/connection_state.dart';
import 'package:cpft/features/chat/services/connection_manager.dart';
import 'package:cpft/features/chat/services/connection_service.dart';

/// Bottom sheet showing connected devices
/// Can be used with ConnectionManager for live updates or static list
class ConnectedDevicesBottomSheet extends StatefulWidget {
  final ConnectionManager? connectionManager;
  final List<MapEntry<String, ConnectionService>>? staticConnections;
  final String? currentDeviceId;
  final Function(String deviceId, [String? ipAddress, int? port, VoidCallback? onFilesSent])? onDeviceTap;
  final VoidCallback? onFilesSent;

  const ConnectedDevicesBottomSheet({
    super.key,
    this.connectionManager,
    this.staticConnections,
    this.currentDeviceId,
    this.onDeviceTap,
    this.onFilesSent,
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
      debugPrint(
        '[ConnectedDevicesSheet] ============ INIT STATE ============',
      );
      debugPrint(
        '[ConnectedDevicesSheet] Active connections count: ${widget.connectionManager!.activeConnections.length}',
      );
      debugPrint(
        '[ConnectedDevicesSheet] Connection keys: ${widget.connectionManager!.activeConnections.keys.join(", ")}',
      );
      for (final entry in widget.connectionManager!.activeConnections.entries) {
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
      widget.connectionManager!.addConnectionListener(_connectionListener!);

      // Add status listeners for existing connections
      for (final entry in _entries) {
        debugPrint(
          '[ConnectedDevicesSheet] Adding status listener for existing connection: ${entry.key}',
        );
        _addStatusListener(entry.key, entry.value);
      }
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
    if (!mounted || widget.connectionManager == null) return;
    setState(() {
      _entries = widget.connectionManager!.activeConnections.entries.toList();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(
              child: Text(
                'No devices connected',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final deviceId = _entries[index].key;
                final connection = _entries[index].value;
                final status = connection.currentConnection?.status;
                final connected = connection.isConnected;
                final isCurrentDevice = deviceId == widget.currentDeviceId;

                return DeviceListTile(
                  deviceId: deviceId,
                  status: status,
                  connected: connected,
                  isCurrentDevice: isCurrentDevice,
                  onTap: () {
                    if (widget.onDeviceTap != null) {
                      final ipAddress =
                          connection.currentConnection?.ipAddress ?? '';
                      Navigator.pop(context);
                      // Support both callback signatures
                      if (ipAddress.isNotEmpty) {
                        widget.onDeviceTap!(deviceId, ipAddress, 53318, widget.onFilesSent);
                      } else {
                        widget.onDeviceTap!(deviceId, null, null, widget.onFilesSent);
                      }
                    }
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
