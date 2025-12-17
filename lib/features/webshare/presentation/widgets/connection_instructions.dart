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
        const Icon(Icons.info_outline, size: AppSizes.lg, color: AppColors.red),
        Expanded(
          child: Text(
            'Ensure both devices are on the same Wi‑Fi or Personal Hotspot network.',
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
