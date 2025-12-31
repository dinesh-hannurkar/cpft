import 'package:flutter/material.dart';
import 'package:fylooo/core/constants/app_sizes.dart';

class StatusBanner extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final IconData? icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool isLoading;
  final String? action;
  final VoidCallback? onAction;
  final bool useWhiteText;

  const StatusBanner({
    super.key,
    required this.color,
    required this.borderColor,
    this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.isLoading = false,
    this.action,
    this.onAction,
    this.useWhiteText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        color: color,
        border: Border(bottom: BorderSide(color: borderColor)),
        gradient: useWhiteText ? LinearGradient(
          colors: [color, borderColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ) : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: useWhiteText ? Colors.white.withOpacity(0.2) : iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        useWhiteText ? Colors.white : iconColor,
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    color: useWhiteText ? Colors.white : iconColor,
                    size: 20,
                  ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: useWhiteText ? Colors.white : iconColor.withOpacity(0.9),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: useWhiteText ? Colors.white.withOpacity(0.9) : iconColor.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
          ),
          if (action != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: useWhiteText ? Colors.white.withOpacity(0.2) : iconColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    action!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
