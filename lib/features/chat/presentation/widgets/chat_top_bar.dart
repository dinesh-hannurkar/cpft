import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/features/home/presentation/widgets/buttons/settings_button.dart';
import 'package:fylooo/shared/widgets/back_button_chip.dart';
import 'package:fylooo/shared/widgets/primary_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:fylooo/shared/showcase/showcase_helper.dart';
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
  final VoidCallback? onSaveAll;
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
    this.onSaveAll,
    required this.connectionManager,
    required this.isConnected,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  List<Widget> _buildTrailingActions() {
    final actions = <Widget>[];

    // Save All button when multiple files received
    if (onSaveAll != null) {
      actions.add(
        Showcase(
          key: ShowcaseHelper.downloadAllKey,
          disableBarrierInteraction: false,
          targetPadding: const EdgeInsets.all(8),
          title: 'Download All',
          description:
              'Save all received files at once to a folder of your choice',
          tooltipBackgroundColor: Colors.white,
          textColor: Colors.black,
          descTextStyle: const TextStyle(fontSize: 12, color: Colors.black87),
          titleTextStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: 16,
          ),
          tooltipBorderRadius: BorderRadius.circular(12),
          targetBorderRadius: BorderRadius.circular(12),
          child: AppIconButton(icon: Icons.download, onPressed: onSaveAll!),
        ),
      );
    }

    if (receivedFilesCount > 0) {
      actions.add(
        Showcase(
          key: ShowcaseHelper.receivedListKey,
          disableBarrierInteraction: false,
          targetPadding: const EdgeInsets.all(8),
          title: 'Received Files',
          description: 'View all received files to download or open them.',
          tooltipBackgroundColor: Colors.white,
          textColor: Colors.black,
          descTextStyle: const TextStyle(fontSize: 12, color: Colors.black87),
          titleTextStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: 16,
          ),
          tooltipBorderRadius: BorderRadius.circular(12),
          targetBorderRadius: BorderRadius.circular(12),
          child: AppIconButton(
            // tooltip: 'Received files',
            icon: Icons.folder_open,
            onPressed: onShowReceivedFiles,
          ),
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
        Showcase(
          key: ShowcaseHelper.disconnectKey,
          disableBarrierInteraction: false,
          targetPadding: const EdgeInsets.all(8),
          title: 'Disconnect',
          description: 'End the connection with this device.',
          tooltipBackgroundColor: Colors.white,
          textColor: Colors.black,
          descTextStyle: const TextStyle(fontSize: 12, color: Colors.black87),
          titleTextStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: 16,
          ),
          tooltipBorderRadius: BorderRadius.circular(12),
          targetBorderRadius: BorderRadius.circular(12),
          child: AppIconButton(
            // tooltip: 'Disconnect',
            icon: Icons.close,
            onPressed: onDisconnect!,
          ),
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
