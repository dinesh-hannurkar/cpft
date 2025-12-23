import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/features/home/presentation/widgets/ios_step_card.dart';
import 'package:fylooo/services/wifi_service.dart';
import 'package:flutter/material.dart';

class IosHotspotInstructionsSheet extends StatelessWidget {
  const IosHotspotInstructionsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.lg,
                vertical: AppSizes.md,
              ),
              child: Column(
                children: [
                  // Header with close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enable Personal Hotspot',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkPrimary,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Follow these simple steps',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
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
                  const SizedBox(height: AppSizes.md),

                  // Step Cards
                  IosStepCard(
                    number: 1,
                    icon: Icons.settings_rounded,
                    title: 'Open Settings',
                    description: 'Tap the Settings app on your home screen',
                    accentColor: AppColors.primary,
                  ),
                  const SizedBox(height: AppSizes.sm),
                  IosStepCard(
                    number: 2,
                    icon: Icons.signal_cellular_alt_rounded,
                    title: 'Navigate to Hotspot',
                    description: 'Tap "Personal Hotspot" or "Cellular" menu',
                    accentColor: AppColors.primary,
                  ),
                  const SizedBox(height: AppSizes.sm),
                  IosStepCard(
                    number: 3,
                    icon: Icons.toggle_on_rounded,
                    title: 'Turn It On',
                    description: 'Toggle "Allow Others to Join" switch',
                    accentColor: AppColors.primary,
                  ),
                  const SizedBox(height: AppSizes.sm),
                  IosStepCard(
                    number: 4,
                    icon: Icons.done_all_rounded,
                    title: 'You\'re All Set!',
                    description: 'Return to this app and continue',
                    accentColor: AppColors.primary,
                  ),
                  const SizedBox(height: AppSizes.sm),

                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(AppSizes.md),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.blue.shade50, Colors.cyan.shade50],
                      ),
                      borderRadius: BorderRadius.circular(AppSizes.md),
                      border: Border.all(
                        color: Colors.blue.shade200.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.info_outline_rounded,
                            color: Colors.blue.shade700,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'iOS requires manual hotspot setup for security. This takes just few seconds!',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.sm),

                  // Action button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        try {
                          debugPrint('🔵 Attempting to open settings...');
                          await WifiService.openWifiSettings();
                          debugPrint('✅ Settings opened successfully');
                        } catch (e) {
                          debugPrint('❌ Error opening settings: $e');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not open settings: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 0,
                        shadowColor: AppColors.primary.withValues(alpha: 0.4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.settings_rounded, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Open Settings Now',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
