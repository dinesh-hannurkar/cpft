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

  final VoidCallback? onScan;
  final VoidCallback? onShowQR;

  const WiFiDirectBanner({
    super.key,
    required this.statusNotifier,
    required this.canConnect,
    required this.canRequest,
    required this.isAndroid,
    this.onConnect,
    this.onRequest,
    this.onInfo,
    this.onScan,
    this.onShowQR,
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
            action: (isAndroid && onShowQR != null) ? 'Show QR' : null,
            onAction: isAndroid ? onShowQR : null,
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
            subtitle: 'Ensure hotspot is active',
          );
        }

        if (canConnect || canRequest) {
          final isScanning = onScan != null && !isAndroid;
          final String actionLabel = canConnect
              ? 'Enable'
              : (isAndroid ? 'Enable' : (isScanning ? 'Scan QR' : 'Request'));

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
                : (isAndroid
                      ? 'Start Android hotspot for faster transfer'
                      : (isScanning
                            ? 'Scan the QR code on the other device'
                            : 'Request faster transfer protocol')),
            action: actionLabel,
            onAction: canConnect
                ? onConnect
                : (isScanning ? onScan : onRequest),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
