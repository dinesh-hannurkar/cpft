import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/chat/services/connection_manager.dart';
import 'package:cpft/features/home/presentation/widgets/settings_button.dart';
import 'package:cpft/services/discovery_service.dart';
import 'package:cpft/features/settings/presentation/settings_screen.dart';

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
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.apply(color: AppColors.primary),
                ),
              ),
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: AppIconButton(
                    icon: Icons.qr_code_scanner,
                    onPressed: onQrScan,
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
                      _buildConnectedDevicesButton(),
                      const SizedBox(width: AppSizes.sm),
                      AppIconButton(
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
