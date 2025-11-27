import 'package:cpft/features/webshare/services/webshare_service.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrImageSection extends StatelessWidget {
  final WebShareService webShareService;
  const QrImageSection({super.key, required this.webShareService});

  String _buildQrUrl(String? hostname) {
    final hasValidHostname =
        hostname != null &&
        hostname.isNotEmpty &&
        !hostname.contains('.') &&
        !hostname.contains('_');
    return hasValidHostname
        ? 'http://$hostname.local:${webShareService.port}'
        : 'http://${webShareService.localIP ?? 'localhost'}:${webShareService.port}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: webShareService.actualHostnameNotifier,
      builder: (context, hostname, child) {
        if (hostname == null || hostname.isEmpty) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 150,
                height: 150,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(color: Colors.blue.shade50),
                ),
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Preparing QR link...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          );
        }

        final qrUrl = _buildQrUrl(hostname);
        return QrImageView(data: qrUrl, size: 150.0);
      },
    );
  }
}
