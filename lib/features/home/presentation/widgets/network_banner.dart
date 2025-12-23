import 'dart:io';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

class NetworkBanner extends StatelessWidget {
  final String? networkName;
  final bool hotspotActive;
  final bool hotspotStarting;
  final String? hotspotName;
  final VoidCallback? onSwitchToWifi;
  final VoidCallback? onShowQrCode;
  final VoidCallback? onSwitchToHotspot;
  final bool iosPersonalHotspot;

  const NetworkBanner({
    super.key,
    this.networkName,
    this.hotspotActive = false,
    this.hotspotStarting = false,
    this.hotspotName,
    this.onSwitchToWifi,
    this.onShowQrCode,
    this.onSwitchToHotspot,
    this.iosPersonalHotspot = false,
  });

  @override
  Widget build(BuildContext context) {
    // Show "Switching to temporary hotspot..." state
    if (hotspotStarting) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF2962FF),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Switching to temporary hotspot...',
              style: TextStyle(
                color: Color(0xFF2962FF),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Treat explicit networkName 'Personal Hotspot' same as hotspotActive
    final isPersonalHotspotName = (networkName == 'Personal Hotspot');
    if (hotspotActive || isPersonalHotspotName) {
      final name = hotspotName ?? 'Hotspot';
      final displayName = isPersonalHotspotName ? 'Personal Hotspot' : name;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.wifi_tethering,
                  color: Color(0xFF2962FF),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Color(0xFF2962FF),
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onShowQrCode != null) ...[
                  OutlinedButton.icon(
                    onPressed: onShowQrCode,
                    icon: const Icon(Icons.qr_code, size: 16),
                    label: const Text(
                      'QR Code',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      side: const BorderSide(color: Color(0xFF2962FF)),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (onSwitchToWifi != null)
                  OutlinedButton(
                    onPressed: onSwitchToWifi,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      side: const BorderSide(color: Color(0xFF2962FF)),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(
                      iosPersonalHotspot
                          ? 'Turn off Hotspot to switch to Wi‑Fi'
                          : 'Switch to Wi‑Fi',
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    final isConnected = networkName != null && networkName != 'Not Connected';
    final color = isConnected ? const Color(0xFF00C853) : AppColors.red;
    final icon = isConnected ? Icons.wifi : Icons.wifi_off;
    final text = isConnected
        ? (networkName?.toLowerCase().contains('local') == true
              ? 'Connected to WiFi'
              : 'Connected to $networkName')
        : 'Not connected';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (isConnected && onSwitchToHotspot != null && !Platform.isMacOS) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onSwitchToHotspot,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                side: const BorderSide(color: Color(0xFF00C853)),
                minimumSize: const Size(0, 32),
              ),
              child: const Text(
                'Switch to Temporary Hotspot',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
