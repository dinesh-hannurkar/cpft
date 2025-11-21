import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/chat/services/connection_manager.dart';
import 'package:cpft/features/home/presentation/widgets/settings_button.dart';
import 'package:cpft/services/discovery_service.dart';

/// Custom AppBar for the home screen
class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final ConnectionManager? connectionManager;
  final DiscoveryService discoveryService;
  final bool isRestartingServices;
  final VoidCallback onRefresh;
  final VoidCallback onShowConnectedDevices;

  const HomeAppBar({
    super.key,
    required this.connectionManager,
    required this.discoveryService,
    required this.isRestartingServices,
    required this.onRefresh,
    required this.onShowConnectedDevices,
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
            alignment: Alignment.center,
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
                right: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildRefreshButton(context),
                    const SizedBox(width: AppSizes.sm),
                    _buildConnectedDevicesButton(),
                    const SizedBox(width: AppSizes.sm),
                    SettingsButton(
                      onPressed: () {
                        /* TODO: navigate to settings */
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshButton(BuildContext context) {
    return IconButton(
      icon: isRestartingServices
          ? SizedBox(
              width: AppSizes.iconMd,
              height: AppSizes.iconMd,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            )
          : Icon(
              Icons.refresh,
              color: AppColors.primary,
              size: AppSizes.iconMd,
            ),
      onPressed: isRestartingServices ? null : onRefresh,
      tooltip: 'Restart All Services',
    );
  }

  Widget _buildConnectedDevicesButton() {
    final connectedCount = connectionManager?.activeConnections.values
            .where((service) => service.isConnected)
            .length ??
        0;

    return Badge(
      label: Text(connectedCount.toString()),
      child: IconButton(
        onPressed: connectedCount > 0 ? onShowConnectedDevices : null,
        icon: Icon(
          Icons.devices,
          color: AppColors.primary,
          size: AppSizes.iconMd,
        ),
        tooltip: 'Connected Devices ($connectedCount)',
      ),
    );
  }
}
