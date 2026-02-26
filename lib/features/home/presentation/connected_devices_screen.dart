import 'package:flutter/material.dart';
import 'package:fylooo/features/chat/services/connection_manager.dart';
import 'package:fylooo/features/home/presentation/widgets/sheets/connected_devices_sheet.dart';
import 'package:fylooo/features/chat/presentation/chat_screen.dart';
import 'package:fylooo/services/discovery_service.dart';
import 'package:fylooo/shared/widgets/primary_app_bar.dart';
import 'package:fylooo/shared/widgets/back_button_chip.dart';

class ConnectedDevicesScreen extends StatelessWidget {
  final ConnectionManager connectionManager;
  final String myDeviceName;
  final DiscoveryService discoveryService;
  final VoidCallback? onFilesSent;
  final bool showAppBar;

  const ConnectedDevicesScreen({
    super.key,
    required this.connectionManager,
    required this.myDeviceName,
    required this.discoveryService,
    this.onFilesSent,
    this.showAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: showAppBar
          ? PrimaryAppBar(
              leading: BackButtonChip(onPressed: () => Navigator.pop(context)),
              title: 'Connected Devices',
              centerTitle: true,
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE2F6FB), Color(0xFFFFFFFF)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 8),
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
                            settings: const RouteSettings(name: '/chat'),
                            builder: (_) => ChatScreen(
                              deviceName: deviceId,
                              ipAddress: ipAddress ?? '',
                              port: port ?? DiscoveryService.p2pPort,
                              myDeviceName: myDeviceName,
                              connectionManager: connectionManager,
                              discoveryService: discoveryService,
                              initialDeviceId: deviceId,
                              onFilesSent: onFilesSentCallback,
                            ),
                          ),
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
