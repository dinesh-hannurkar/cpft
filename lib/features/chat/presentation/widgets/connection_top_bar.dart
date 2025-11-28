import 'package:flutter/material.dart';

class ConnectionTopBar extends StatelessWidget {
  final String deviceName;
  final String statusText;
  final int receivedFilesCount;
  final int connectedDevicesCount;
  final bool isConnected;
  final VoidCallback onBack;
  final VoidCallback onShowReceivedFiles;
  final VoidCallback onShowConnectedDevices;
  final VoidCallback onDisconnect;

  const ConnectionTopBar({
    super.key,
    required this.deviceName,
    required this.statusText,
    required this.receivedFilesCount,
    required this.connectedDevicesCount,
    required this.isConnected,
    required this.onBack,
    required this.onShowReceivedFiles,
    required this.onShowConnectedDevices,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
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
                  'Connected to $deviceName',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
                Text(
                  statusText,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          if (receivedFilesCount > 0)
            IconButton(
              tooltip: 'Received files',
              icon: const Icon(Icons.folder_open),
              onPressed: onShowReceivedFiles,
            ),
          IconButton(
            tooltip: 'All connected devices',
            icon: Badge(
              label: Text('$connectedDevicesCount'),
              child: const Icon(Icons.devices),
            ),
            onPressed: onShowConnectedDevices,
          ),
          if (isConnected)
            IconButton(
              tooltip: 'Disconnect',
              icon: const Icon(Icons.close),
              onPressed: onDisconnect,
            ),
        ],
      ),
    );
  }
}
