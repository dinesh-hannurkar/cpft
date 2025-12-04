import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';

/// Reusable bottom sheet wrapper with consistent styling across the app
/// 
/// Features:
/// - Custom drag handle matching app design
/// - Optional title and subtitle
/// - Optional close button
/// - Responsive height with constraints
/// - Consistent padding and spacing
class AppBottomSheet extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final bool showCloseButton;
  final VoidCallback? onClose;
  final double? maxHeightFactor;
  final EdgeInsets? contentPadding;

  const AppBottomSheet({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.showCloseButton = true,
    this.onClose,
    this.maxHeightFactor = 0.85,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final defaultPadding = EdgeInsets.symmetric(
      horizontal: 16,
      vertical: title != null ? 16 : 12,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * (maxHeightFactor ?? 0.85),
      ),
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
        mainAxisSize: MainAxisSize.min,
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

          // Header with title and close button (if provided)
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 16, 25, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkPrimary,
                              ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showCloseButton)
                    IconButton(
                      onPressed: onClose ?? () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 24),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        padding: const EdgeInsets.all(10),
                      ),
                    ),
                ],
              ),
            ),

          // Content
          Flexible(
            child: Padding(
              padding: contentPadding ?? defaultPadding,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to show AppBottomSheet with consistent configuration
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  String? title,
  String? subtitle,
  required Widget child,
  bool showCloseButton = true,
  VoidCallback? onClose,
  double? maxHeightFactor = 0.85,
  EdgeInsets? contentPadding,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (context) => AppBottomSheet(
      title: title,
      subtitle: subtitle,
      showCloseButton: showCloseButton,
      onClose: onClose,
      maxHeightFactor: maxHeightFactor,
      contentPadding: contentPadding,
      child: child,
    ),
  );
}
