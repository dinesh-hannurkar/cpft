import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/services/hotspot_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

class HotspotScreen extends StatefulWidget {
  const HotspotScreen({super.key});

  @override
  State<HotspotScreen> createState() => _HotspotScreenState();
}

class _HotspotScreenState extends State<HotspotScreen> {
  HotspotInfo? hotspotInfo;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkHotspotStatus();
  }

  Future<void> _checkHotspotStatus() async {
    final running = await LocalHotspotService.isHotspotRunning();
    if (running) {
      final info = await LocalHotspotService.getHotspotDetails();
      setState(() {
        hotspotInfo = info;
      });
    }
  }

  Future<void> _startHotspot() async {
    setState(() => isLoading = true);

    try {
      final info = await LocalHotspotService.startHotspot();

      setState(() {
        hotspotInfo = info;
        isLoading = false;
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hotspot started: ${info?.ssid}')),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _stopHotspot() async {
    setState(() => isLoading = true);

    final success = await LocalHotspotService.stopHotspot();

    setState(() {
      if (success) {
        hotspotInfo = null;
      }
      isLoading = false;
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Hotspot stopped' : 'Error stopping hotspot')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Hotspot',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE2F6FB), Color(0xFFFFFFFF)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: AppSizes.xl),
          // Hotspot Status Card
          Container(
            padding: const EdgeInsets.all(AppSizes.lg),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.md),
              boxShadow: [
                BoxShadow(
                  color: AppColors.skyBlue.withValues(alpha: 0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Hotspot Status',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Switch(
                      value: hotspotInfo != null,
                      onChanged: (value) => value ? _startHotspot() : _stopHotspot(),
                      activeThumbColor: AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.md,
                    vertical: AppSizes.sm,
                  ),
                  decoration: BoxDecoration(
                    color: hotspotInfo != null
                        ? AppColors.green.withValues(alpha: 0.1)
                        : AppColors.greyLight.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSizes.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hotspotInfo != null ? Icons.wifi : Icons.wifi_off,
                        color: hotspotInfo != null ? AppColors.green : AppColors.greyLight,
                        size: 16,
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Text(
                        hotspotInfo != null ? 'Active' : 'Inactive',
                        style: TextStyle(
                          color: hotspotInfo != null ? AppColors.green : AppColors.greyLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.xl),

          // Hotspot Details
          if (hotspotInfo != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSizes.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSizes.md),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.skyBlue.withValues(alpha: 0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hotspot Details',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  _buildDetailRow('Network Name', hotspotInfo!.ssid),
                  const SizedBox(height: AppSizes.sm),
                  _buildDetailRow('Password', hotspotInfo!.password),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.xl),
            // QR Code
            Container(
              padding: const EdgeInsets.all(AppSizes.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSizes.md),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.skyBlue.withValues(alpha: 0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'Scan to Connect',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSizes.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppSizes.sm),
                      border: Border.all(color: AppColors.greyLight),
                    ),
                    child: QrImageView(
                      data: 'WIFI:T:${hotspotInfo!.securityType};S:${hotspotInfo!.ssid};P:${hotspotInfo!.password};;',
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Loading indicator
          if (isLoading) ...[
            const SizedBox(height: AppSizes.xl),
            const CircularProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.greyDark,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}