import 'package:flutter/material.dart';
import 'package:fylooo/shared/widgets/status_banner.dart';
import '../../models/connection_state.dart';

class WiFiDirectBanner extends StatelessWidget {
  final ValueNotifier<WifiDirectStatus> statusNotifier;
  final bool canConnect;
  final bool canRequest;
  final bool isAndroid;
  final VoidCallback? onConnect;
  final VoidCallback? onRequest;
  final VoidCallback? onInfo;

  const WiFiDirectBanner({
    super.key,
    required this.statusNotifier,
    required this.canConnect,
    required this.canRequest,
    required this.isAndroid,
    this.onConnect,
    this.onRequest,
    this.onInfo,
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
            trailing: IconButton(
              icon: Icon(Icons.info_outline, color: Colors.green.shade700),
              tooltip: 'Connection Details',
              onPressed: onInfo,
            ),
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

        if (canConnect || canRequest) {
          // Use 'Enable' for Android-Android or if we are the Android side of cross-platform
          // Use 'Request' for non-Android side of cross-platform
          final String actionLabel = canConnect
              ? 'Enable'
              : (canRequest && isAndroid ? 'Enable' : 'Request');

          return StatusBanner(
            color: Colors.blue.shade50,
            borderColor: Colors.blue.shade200,
            icon: Icons.speed_rounded,
            iconColor: Colors.blue.shade700,
            title: canConnect
                ? 'High Speed Available'
                : 'High Speed Optimization',
            subtitle: canConnect
                ? 'Tap to enable 5GHz transfer'
                : (canRequest
                      ? (isAndroid
                            ? 'Start Android hotspot for faster transfer'
                            : 'Request faster transfer protocol')
                      : 'Switch to high-speed mode'),
            action: actionLabel,
            onAction: canConnect ? onConnect : onRequest,
            trailing: IconButton(
              icon: Icon(Icons.info_outline, color: Colors.blue.shade700),
              tooltip: 'Connection Details',
              onPressed: onInfo,
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
