import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/chat/services/connection_manager.dart';
import 'package:cpft/features/home/presentation/widgets/buttons/settings_button.dart';
import 'package:cpft/services/discovery_service.dart';
import 'package:cpft/features/settings/presentation/settings_screen.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:cpft/shared/showcase/showcase_helper.dart';

/// Custom AppBar for the home screen
class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final ConnectionManager? connectionManager;
  final DiscoveryService discoveryService;
  final bool isRestartingServices;
  final VoidCallback onRefresh;
  final VoidCallback onShowConnectedDevices;
  final VoidCallback onQrScan;

  const HomeAppBar({
    super.key,
    required this.connectionManager,
    required this.discoveryService,
    required this.isRestartingServices,
    required this.onRefresh,
    required this.onShowConnectedDevices,
    required this.onQrScan,
  });

  @override
  Size get preferredSize => const Size.fromHeight(80);

  @override
  Widget build(BuildContext context) {
    return PreferredSize(
      preferredSize: preferredSize,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: AppColors.skyBlue.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
          ),
          height: AppSizes.appBarHeight,
          child: Stack(
            children: [
              Center(
                child: Text(
                  'CPFT',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.apply(color: AppColors.primary),
                ),
              ),
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Showcase(
                        key: ShowcaseHelper.connectedDevicesKey,
                        disableBarrierInteraction: false,
                        targetPadding: const EdgeInsets.all(8),
                        title: 'Connected Devices',
                        description:
                            'View all currently connected devices and tap to start transferring files.',
                        tooltipBackgroundColor: Colors.white,
                        textColor: Colors.black,
                        descTextStyle: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                        titleTextStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontSize: 16,
                        ),
                        tooltipBorderRadius: BorderRadius.circular(12),
                        targetBorderRadius: BorderRadius.circular(12),
                        child: _buildConnectedDevicesButton(),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Showcase(
                        key: ShowcaseHelper.qrScannerKey,
                        disableBarrierInteraction: false,
                        targetPadding: const EdgeInsets.all(8),
                        title: 'Scan QR Code',
                        description:
                            'Scan a QR code to quickly join a shared network and connect with nearby devices.',
                        tooltipBackgroundColor: Colors.white,
                        textColor: Colors.black,
                        descTextStyle: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                        titleTextStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontSize: 16,
                        ),
                        tooltipBorderRadius: BorderRadius.circular(12),
                        targetBorderRadius: BorderRadius.circular(12),
                        child: AppIconButton(
                          icon: Icons.qr_code_scanner,
                          onPressed: onQrScan,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Showcase(
                        key: ShowcaseHelper.settingsKey,
                        disableBarrierInteraction: false,
                        targetPadding: const EdgeInsets.all(8),
                        title: 'Settings',
                        description:
                            'Change your device name and app preferences.',
                        tooltipBackgroundColor: Colors.white,
                        textColor: Colors.black,
                        descTextStyle: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                        titleTextStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontSize: 16,
                        ),
                        tooltipBorderRadius: BorderRadius.circular(12),
                        targetBorderRadius: BorderRadius.circular(12),
                        child: AppIconButton(
                          icon: Icons.settings_outlined,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SettingsScreen(
                                  currentDeviceName: discoveryService.alias,
                                  discoveryService: discoveryService,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Showcase(
                        key: ShowcaseHelper.helpKey,
                        disableBarrierInteraction: false,
                        targetPadding: const EdgeInsets.all(8),
                        title: 'Help',
                        description: 'Replay this guide anytime.',
                        tooltipBackgroundColor: Colors.white,
                        textColor: Colors.black,
                        descTextStyle: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                        titleTextStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontSize: 16,
                        ),
                        tooltipBorderRadius: BorderRadius.circular(12),
                        targetBorderRadius: BorderRadius.circular(12),
                        child: AppIconButton(
                          icon: Icons.help_outline,
                          onPressed: () {
                            try {
                              ShowcaseHelper.startForHome(context);
                            } catch (_) {}
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedDevicesButton() {
    final connectedCount =
        connectionManager?.activeConnections.values
            .where((service) => service.isConnected)
            .length ??
        0;

    return Badge(
      label: Text(connectedCount.toString()),
      child: AppIconButton(
        onPressed: () => connectedCount > 0 ? onShowConnectedDevices() : null,
        icon: Icons.devices,
      ),
    );
  }
}
