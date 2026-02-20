import 'package:flutter/material.dart';
import 'package:fylooo/features/chat/services/connection_manager.dart';
import 'package:fylooo/features/home/presentation/widgets/sheets/connected_devices_sheet.dart';
import 'package:fylooo/features/chat/presentation/chat_screen.dart';
import 'package:fylooo/services/discovery_service.dart';

class ConnectedDevicesScreen extends StatelessWidget {
  final ConnectionManager connectionManager;
  final String myDeviceName;
  final VoidCallback? onFilesSent;

  final bool showAppBar;

  const ConnectedDevicesScreen({
    super.key,
    required this.connectionManager,
    required this.myDeviceName,
    this.onFilesSent,
    this.showAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              title: const Text('Connected Devices'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 1,
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: () {
                    // Navigate to history screen
                    // Use standard navigator push
                    // But first we need verify HistoryListScreen import and usage
                    // Assuming HistoryListScreen is available or needs import
                  },
                ),
              ],
            )
          : null,
      body: CustomScrollView(
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverPadding(
              padding: EdgeInsets.only(
                top: showAppBar ? 0 : 0, // SliverSafeArea handles status bar
              ),
              sliver: ConnectedDevicesBottomSheet(
                connectionManager: connectionManager,
                currentDeviceId: myDeviceName,
                onFilesSent: onFilesSent,
                shouldPop: false,
                isEmbedded: true,
                asSliver: true,
                onDeviceTap:
                    (deviceId, [ipAddress, port, onFilesSentCallback]) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            deviceName: deviceId,
                            ipAddress: ipAddress ?? '',
                            port: port ?? DiscoveryService.p2pPort,
                            myDeviceName: myDeviceName,
                            connectionManager: connectionManager,
                            initialDeviceId: deviceId,
                            onFilesSent: onFilesSentCallback,
                          ),
                        ),
                      );
                    },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
