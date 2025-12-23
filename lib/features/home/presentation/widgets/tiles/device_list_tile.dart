import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/features/chat/models/connection_state.dart';
import 'package:flutter/material.dart';

/// Individual device list tile
class DeviceListTile extends StatelessWidget {
  final String deviceId;
  final ConnectionStatus? status;
  final bool connected;
  final bool isCurrentDevice;
  final VoidCallback onTap;

  const DeviceListTile({
    super.key,
    required this.deviceId,
    required this.status,
    required this.connected,
    required this.isCurrentDevice,
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
      statusIcon = Icons.check_circle;
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
      dense: true,
      contentPadding: const EdgeInsets.symmetric(
        vertical: 8,
        horizontal: AppSizes.lg,
      ),
      leading: CircleAvatar(
        backgroundColor: statusColor,
        child: Icon(statusIcon, color: Colors.white, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              deviceId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.darkPrimary),
            ),
          ),
          if (isCurrentDevice)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Current',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        statusText,
        style: TextStyle(color: statusColor, fontSize: 12),
      ),
      trailing: !isCurrentDevice && connected
          ? Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400])
          : null,
      onTap: !isCurrentDevice && connected ? onTap : null,
    );
  }
}
