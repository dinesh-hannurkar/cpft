import 'package:cpft/features/chat/presentation/widgets/tiles/device_connection_tile.dart';
import 'package:flutter/material.dart';
import '../../../models/connection_state.dart';

class ConnectedDevicesList extends StatelessWidget {
  final List<DeviceConnectionEntry> connections;
  final String currentDeviceId;
  final Function(String deviceId, String ipAddress) onSwitchChat;

  const ConnectedDevicesList({
    super.key,
    required this.connections,
    required this.currentDeviceId,
    required this.onSwitchChat,
  });

  @override
  Widget build(BuildContext context) {
    if (connections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(child: Text('No connections')),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Connected Devices (${connections.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              itemCount: connections.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = connections[index];
                final isCurrentDevice = entry.deviceId == currentDeviceId;

                return DeviceConnectionTile(
                  entry: entry,
                  isCurrentDevice: isCurrentDevice,
                  onSwitchChat: () => onSwitchChat(
                    entry.deviceId,
                    entry.ipAddress,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DeviceConnectionEntry {
  final String deviceId;
  final String ipAddress;
  final ConnectionStatus? status;

  DeviceConnectionEntry({
    required this.deviceId,
    required this.ipAddress,
    required this.status,
  });
}

class ConnectionStatusInfo {
  final String text;
  final Color color;
  final IconData icon;

  ConnectionStatusInfo({
    required this.text,
    required this.color,
    required this.icon,
  });
}
