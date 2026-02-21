import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/models/hotspot_info.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';
import 'package:fylooo/shared/widgets/app_bottom_sheet.dart';

class HotspotQrSheet extends StatefulWidget {
  final HotspotInfo hotspotInfo;
  final VoidCallback onStop;
  final Future<HotspotInfo?> Function() onRegenerate;

  const HotspotQrSheet({
    super.key,
    required this.hotspotInfo,
    required this.onStop,
    required this.onRegenerate,
  });

  @override
  State<HotspotQrSheet> createState() => _HotspotQrSheetState();
}

class _HotspotQrSheetState extends State<HotspotQrSheet> {
  late Timer _timer;
  late DateTime _expiryTime;
  bool _isExpired = false;
  bool _isRegenerating = false;
  late HotspotInfo _currentHotspotInfo;

  // Set expiry to 2 minutes by default
  static const Duration _validityDuration = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _currentHotspotInfo = widget.hotspotInfo;
    _resetTimer();
  }

  void _resetTimer() {
    _expiryTime = DateTime.now().add(_validityDuration);
    _isExpired = false;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (DateTime.now().isAfter(_expiryTime)) {
        setState(() {
          _isExpired = true;
        });
        timer.cancel();
      } else {
        setState(() {}); // Update UI for countdown
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _getRemainingTime() {
    final remaining = _expiryTime.difference(DateTime.now());
    if (remaining.isNegative) return '00:00';
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _handleRegenerate() async {
    setState(() => _isRegenerating = true);
    final newInfo = await widget.onRegenerate();
    if (mounted) {
      setState(() {
        _isRegenerating = false;
        if (newInfo != null) {
          _currentHotspotInfo = newInfo;
        }
      });
      _resetTimer();
    }
  }

  Widget _buildStep(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSizes.sm),
          decoration: BoxDecoration(
            color: AppColors.skyBlue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: AppColors.darkPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        AppSnackbar.showSuccess(
          context,
          '$label copied to clipboard',
          duration: const Duration(seconds: 2),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.copy_rounded, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: 'Scan QR Code',
      subtitle: 'Scan and Connect instantly',
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSizes.md),
        child: Column(
          children: [
            const SizedBox(height: AppSizes.sm),

            // QR Container
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.skyBlue.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(
                      color: _isExpired
                          ? Colors.red.withOpacity(0.3)
                          : AppColors.skyBlue.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Opacity(
                        opacity: _isExpired ? 0.1 : 1.0,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.secondary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: QrImageView(
                            data:
                                'WIFI:T:${_currentHotspotInfo.securityType};S:${_currentHotspotInfo.ssid};P:${_currentHotspotInfo.password};;',
                            version: QrVersions.auto,
                            size: 220,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _isExpired
                              ? Colors.red.shade50
                              : AppColors.secondary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 16,
                              color: _isExpired
                                  ? Colors.red
                                  : AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isExpired
                                  ? 'Expired'
                                  : 'Valid for ${_getRemainingTime()}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isExpired
                                    ? Colors.red
                                    : AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isExpired)
                  Positioned.fill(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.broken_image_rounded,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isRegenerating
                                ? null
                                : _handleRegenerate,
                            icon: _isRegenerating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: Text(
                              _isRegenerating
                                  ? 'Regenerating...'
                                  : 'Regenerate QR',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: AppSizes.md),

            // Quick Steps
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Steps',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStep(Icons.camera_alt_rounded, 'Open your Camera app'),
                  const SizedBox(height: 12),
                  _buildStep(
                    Icons.qr_code_scanner_rounded,
                    'Point at the QR code',
                  ),
                  const SizedBox(height: 12),
                  _buildStep(Icons.wifi_rounded, 'Tap to connect'),
                ],
              ),
            ),

            const SizedBox(height: AppSizes.md),

            // Credentials
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manual Connection',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    'Network Name',
                    _currentHotspotInfo.ssid,
                    Icons.wifi,
                  ),
                  const Divider(height: 12),
                  _buildDetailRow(
                    'Password',
                    _currentHotspotInfo.password,
                    Icons.lock,
                  ),
                  const Divider(height: 12),
                  _buildDetailRow(
                    'Security',
                    _currentHotspotInfo.securityType,
                    Icons.security,
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSizes.md),

            // Stop Button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onStop();
                },
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop Hotspot'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.md),
          ],
        ),
      ),
    );
  }
}
