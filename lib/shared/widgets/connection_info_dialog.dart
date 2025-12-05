import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/shared/widgets/app_action_button.dart';
import 'package:cpft/utils/network_utils.dart';

/// Dialog widget for displaying WebRTC connection information
///
/// Shows peer device name, network name, and disconnect option
class ConnectionInfoDialog extends StatefulWidget {
  final String? peerName;
  final String networkName;
  final VoidCallback onDisconnect;

  const ConnectionInfoDialog({
    super.key,
    required this.peerName,
    required this.networkName,
    required this.onDisconnect,
  });

  @override
  State<ConnectionInfoDialog> createState() => _ConnectionInfoDialogState();
}

class _ConnectionInfoDialogState extends State<ConnectionInfoDialog> {
  String? _wifiName;
  bool _isLoadingWifi = true;

  @override
  void initState() {
    super.initState();
    _loadWifiName();
  }

  Future<void> _loadWifiName() async {
    try {
      final wifiName = await NetworkUtils.getWifiName();
      if (mounted) {
        setState(() {
          _wifiName = wifiName;
          _isLoadingWifi = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _wifiName = 'Unknown Network';
          _isLoadingWifi = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSizes.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with title and close icon
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Connection Info',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 24),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                    padding: const EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.spaceBtwInputFields),
            // Connection info content
            _buildInfoRow(
              icon: Icons.devices,
              label: 'Device Name',
              value: widget.peerName ?? 'Unknown Device',
            ),
            const SizedBox(height: AppSizes.sm),
            _buildInfoRow(
              icon: Icons.wifi,
              label: 'Network Name',
              value: _isLoadingWifi ? 'Loading...' : (_wifiName ?? 'Unknown Network'),
            ),
            const SizedBox(height: AppSizes.sm),
            _buildInfoRow(
              icon: Icons.link,
              label: 'Connection ID',
              value: widget.networkName,
            ),
            const SizedBox(height: AppSizes.lg),
            // Disconnect button
            AppActionButton(
              text: 'Disconnect',
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                widget.onDisconnect(); // Disconnect
              },
              backgroundColor: AppColors.red.withValues(alpha: 0.09),
              textColor: AppColors.red,
              borderColor: AppColors.white,
              shadowColor: AppColors.red.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.greyDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.blackDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Helper function to show connection info dialog
Future<void> showConnectionInfoDialog({
  required BuildContext context,
  required String? peerName,
  required String networkName,
  required VoidCallback onDisconnect,
}) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => ConnectionInfoDialog(
      peerName: peerName,
      networkName: networkName,
      onDisconnect: onDisconnect,
    ),
  );
}