import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';

class ConnectionInstructions extends StatelessWidget {
  const ConnectionInstructions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSizes.xs * 0.4),
          child: const Icon(Icons.info_outline, size: 16, color: AppColors.red),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Ensure both devices are on the same Wi‑Fi or Personal Hotspot network for the fastest and most reliable connection.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.red),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
