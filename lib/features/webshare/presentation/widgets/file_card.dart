import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/chat/utils/file_utils.dart';
import 'package:cpft/widgets/file_icon.dart';
import 'package:flutter/material.dart';

class FileCard extends StatelessWidget {
  final String filename;
  final int sizeBytes;
  final DateTime timestamp;
  final VoidCallback? onTap;
  final void Function(BuildContext)? onAction;
  final IconData? actionIcon;
  final EdgeInsetsGeometry? margin;

  const FileCard({
    super.key,
    required this.filename,
    required this.sizeBytes,
    required this.timestamp,
    this.onTap,
    this.onAction,
    this.actionIcon,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.blue.withValues(alpha: 0.08),
        highlightColor: Colors.blue.withValues(alpha: 0.04),
        hoverColor: Colors.blue.withValues(alpha: 0.03),
        mouseCursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          margin: margin ?? const EdgeInsets.symmetric(horizontal: AppSizes.md),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.blue.shade50),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FileIcon(filename: filename),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFBBDEFB),
                                ),
                              ),
                              child: Text(
                                filename.contains('.')
                                    ? extensionTrim(filename.split('.').last)
                                    : 'FILE',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                  letterSpacing: .5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              formatBytes(sizeBytes),
                              style: const TextStyle(
                                color: AppColors.darkPrimary,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              formatTime(timestamp),
                              style: const TextStyle(
                                color: AppColors.darkPrimary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (onAction != null)
                    Builder(
                      builder: (buttonContext) => IconButton(
                        icon: Icon(
                          actionIcon ?? Icons.delete_forever,
                          color: actionIcon == Icons.download
                              ? AppColors.primary
                              : AppColors.darkPrimary,
                          size: 22,
                        ),
                        onPressed: () => onAction!.call(buttonContext),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
