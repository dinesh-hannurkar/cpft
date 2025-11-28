import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../models/connection_state.dart';

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

class DeviceConnectionTile extends StatelessWidget {
  final DeviceConnectionEntry entry;
  final bool isCurrentDevice;
  final VoidCallback onSwitchChat;

  const DeviceConnectionTile({
    super.key,
    required this.entry,
    required this.isCurrentDevice,
    required this.onSwitchChat,
  });

  ConnectionStatusInfo _getStatusInfo(ConnectionStatus? status) {
    switch (status) {
      case ConnectionStatus.connected:
        return ConnectionStatusInfo(
          text: 'Connected',
          color: AppColors.green,
          icon: Icons.wifi,
        );
      case ConnectionStatus.connecting:
        return ConnectionStatusInfo(
          text: 'Connecting...',
          color: Colors.blue,
          icon: Icons.sync,
        );
      case ConnectionStatus.disconnected:
        return ConnectionStatusInfo(
          text: 'Disconnected',
          color: Colors.orange,
          icon: Icons.wifi_off,
        );
      case ConnectionStatus.failed:
        return ConnectionStatusInfo(
          text: 'Failed',
          color: AppColors.red,
          icon: Icons.error_outline,
        );
      default:
        return ConnectionStatusInfo(
          text: 'Unknown',
          color: AppColors.greyDark,
          icon: Icons.help_outline,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getStatusInfo(entry.status);
    final canSwitch = !isCurrentDevice && entry.status == ConnectionStatus.connected;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: statusInfo.color,
        child: Icon(statusInfo.icon, color: Colors.white),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              entry.deviceId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrentDevice)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Current',
                style: TextStyle(fontSize: 10, color: Colors.blue),
              ),
            ),
        ],
      ),
      subtitle: Text(
        statusInfo.text,
        style: TextStyle(color: statusInfo.color),
      ),
      trailing: canSwitch
          ? IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Switch to this chat',
              onPressed: onSwitchChat,
            )
          : null,
      onTap: canSwitch ? onSwitchChat : null,
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
