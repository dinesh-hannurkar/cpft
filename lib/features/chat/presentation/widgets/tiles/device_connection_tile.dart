import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/features/chat/models/connection_state.dart';
import 'package:cpft/features/chat/presentation/widgets/lists/connected_devices_list.dart';
import 'package:flutter/material.dart';

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
