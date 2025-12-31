import 'package:flutter/material.dart';
import 'package:fylooo/shared/widgets/status_banner.dart';
import '../../models/connection_state.dart';

class WiFiDirectBanner extends StatelessWidget {
  final ValueNotifier<WifiDirectStatus> statusNotifier;
  final bool canConnect;
  final VoidCallback? onConnect;

  const WiFiDirectBanner({
    super.key,
    required this.statusNotifier,
    required this.canConnect,
    this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WifiDirectStatus>(
      valueListenable: statusNotifier,
      builder: (context, status, child) {
        if (status == WifiDirectStatus.connected) {
          return StatusBanner(
            color: Colors.green.shade50,
            borderColor: Colors.green.shade200,
            icon: Icons.bolt_rounded,
            iconColor: Colors.green.shade700,
            title: 'High-Speed Connection Active',
            subtitle: '5GHz channel enabled',
          );
        }

        if (status == WifiDirectStatus.connecting) {
          return StatusBanner(
            color: Colors.blue.shade50,
            borderColor: Colors.blue.shade200,
            iconColor: Colors.blue.shade700,
            title: 'Optimizing Connection...',
            subtitle: 'Switching to high-speed mode',
            isLoading: true,
          );
        }

        if (status == WifiDirectStatus.failed) {
          return StatusBanner(
            color: Colors.orange.shade50,
            borderColor: Colors.orange.shade200,
            icon: Icons.warning_amber_rounded,
            iconColor: Colors.orange.shade700,
            title: 'Connection Optimization Failed',
            subtitle: 'Retrying...',
          );
        }

        if (canConnect) {
          return StatusBanner(
            color: Colors.blue.shade50,
            borderColor: Colors.blue.shade200,
            icon: Icons.speed_rounded,
            iconColor: Colors.blue.shade700,
            title: 'High Speed Available',
            subtitle: 'Tap to enable 5GHz transfer',
            action: 'Enable',
            onAction: onConnect,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
