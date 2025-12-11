import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'app_action_button.dart';

class AppConfirmDialog extends StatelessWidget {
  final String title;
  final Widget? content;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool destructive;

  const AppConfirmDialog({
    super.key,
    required this.title,
    this.content,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.onConfirm,
    this.onCancel,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSizes.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                bottom: AppSizes.spaceBtwInputFields,
              ),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (content != null) ...[
              const SizedBox(height: AppSizes.md),
              content!,
            ],
            const SizedBox(height: AppSizes.lg),
            Row(
              children: [
                Expanded(
                  child: AppActionButton(
                    text: cancelLabel,
                    onPressed:
                        onCancel ?? () => Navigator.of(context).pop(false),
                    backgroundColor: AppColors.red.withValues(alpha: 0.1),
                    textColor: AppColors.red,
                    borderColor: AppColors.white,
                    shadowColor: AppColors.red.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: AppActionButton(
                    text: confirmLabel,
                    onPressed:
                        onConfirm ?? () => Navigator.of(context).pop(true),
                    backgroundColor: AppColors.green.withValues(alpha: 0.09),
                    textColor: AppColors.green,
                    borderColor: AppColors.white,
                    shadowColor: AppColors.green.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
