import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/shared/widgets/app_action_button.dart';

class IncomingRequestDialog extends StatefulWidget {
  final String deviceName;

  const IncomingRequestDialog({super.key, required this.deviceName});

  @override
  State<IncomingRequestDialog> createState() => _IncomingRequestDialogState();
}

class _IncomingRequestDialogState extends State<IncomingRequestDialog> {
  @override
  Widget build(BuildContext context) {
    final initial = widget.deviceName.isNotEmpty
        ? widget.deviceName[0].toUpperCase()
        : '?';

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSizes.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Requesting to connect',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: AppSizes.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [_avatar(initial)],
            ),
            const SizedBox(height: AppSizes.lg),
            Row(
              children: [
                Expanded(
                  child: AppActionButton(
                    text: 'Reject',
                    onPressed: () => Navigator.of(context).pop(false),
                    backgroundColor: AppColors.red.withValues(alpha: 0.1),
                    textColor: AppColors.red,
                    borderColor: AppColors.white,
                    shadowColor: AppColors.red.withValues(alpha: 0.1),
                    icon: Icons.close,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: AppActionButton(
                    icon: Icons.check,
                    text: 'Accept',
                    onPressed: () => Navigator.of(context).pop(true),
                    backgroundColor: AppColors.green.withValues(alpha: 0.1),
                    textColor: AppColors.green,
                    borderColor: AppColors.white,
                    shadowColor: AppColors.primary.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String text) {
    final label = text.length == 1 ? text : (text == 'You' ? text : text[0]);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.15),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.greyDark,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          child: Text(
            text == 'You' ? text : widget.deviceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
