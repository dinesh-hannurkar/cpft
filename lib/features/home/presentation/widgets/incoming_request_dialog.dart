import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';

class IncomingRequestDialog extends StatefulWidget {
  final String deviceName;

  const IncomingRequestDialog({super.key, required this.deviceName});

  @override
  State<IncomingRequestDialog> createState() => _IncomingRequestDialogState();
}

class _IncomingRequestDialogState extends State<IncomingRequestDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.red),
                      foregroundColor: AppColors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Reject',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Accept',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
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
