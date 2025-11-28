import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/home/presentation/widgets/settings_button.dart';
import 'package:cpft/shared/widgets/back_button_chip.dart';
import 'package:cpft/shared/widgets/primary_app_bar.dart';
import 'package:flutter/material.dart';
import '../../services/connection_manager.dart';

class ChatTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String deviceName;
  final String statusText;
  final int receivedFilesCount;
  final int connectionsCount;
  final VoidCallback onBack;
  final VoidCallback onShowReceivedFiles;
  final VoidCallback onShowDevices;
  final VoidCallback? onDisconnect;
  final ConnectionManager connectionManager;
  final bool isConnected;

  const ChatTopBar({
    super.key,
    required this.deviceName,
    required this.statusText,
    required this.receivedFilesCount,
    required this.connectionsCount,
    required this.onBack,
    required this.onShowReceivedFiles,
    required this.onShowDevices,
    required this.onDisconnect,
    required this.connectionManager,
    required this.isConnected,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  List<Widget> _buildTrailingActions() {
    final actions = <Widget>[];

    if (receivedFilesCount > 0) {
      actions.add(
        AppIconButton(
          // tooltip: 'Received files',
          icon: Icons.folder_open,
          onPressed: onShowReceivedFiles,
        ),
      );
    }

    actions.add(
      Badge(
        label: Text('$connectionsCount'),
        child: AppIconButton(
          // tooltip: 'All connected devices',
          icon: Icons.devices,
          onPressed: onShowDevices,
        ),
      ),
    );

    if (isConnected && onDisconnect != null) {
      actions.add(
        AppIconButton(
          // tooltip: 'Disconnect',
          icon: Icons.close,
          onPressed: onDisconnect!,
        ),
      );
    }

    return actions;
  }

  Widget _buildTitleColumn(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSizes.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            deviceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          Text(
            statusText,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryAppBar(
      leading: BackButtonChip(onPressed: onBack),
      titleWidget: _buildTitleColumn(context),
      centerTitle: false,
      trailing: _buildTrailingActions(),
      backgroundColor: Colors.transparent,
    );
  }
}
