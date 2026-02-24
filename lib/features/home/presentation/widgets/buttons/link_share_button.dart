import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';

class LinkShareButton extends StatelessWidget {
  final VoidCallback onPressed;
  const LinkShareButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(AppSizes.cardRadiusLg * 10),
          border: Border.all(color: AppColors.white, width: 5),
          boxShadow: const [
            BoxShadow(
              color: AppColors.lightSecondary,
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share via Link',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: AppSizes.sm),
            Icon(Icons.link, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }
}
