import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';

/// A reusable, consistent confirm dialog used across the app.
class AppConfirmDialog extends StatelessWidget {
  final String title;
  final Widget? content;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  /// If true, confirm action is styled as destructive (red), else primary (green).
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
    final confirmColor = destructive ? AppColors.red : AppColors.green;
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
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
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
          child: OutlinedButton(
                    onPressed: onCancel ?? () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.greyDark.withValues(alpha: 0.5)),
                      foregroundColor: AppColors.greyDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: FilledButton(
                    onPressed: onConfirm ?? () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: confirmColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(confirmLabel),
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
