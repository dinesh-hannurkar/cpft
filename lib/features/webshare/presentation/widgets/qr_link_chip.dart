import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/webshare/services/webshare_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QrLinkChip extends StatelessWidget {
  final WebShareService webShareService;
  const QrLinkChip({super.key, required this.webShareService});

  String _buildDisplayUrl(String? hostname) {
    final hasValidHostname =
        hostname != null &&
        hostname.isNotEmpty &&
        !hostname.contains('.') &&
        !hostname.contains('_');
    return hasValidHostname
        ? 'http://$hostname.local:${webShareService.port}'
        : 'http://${webShareService.localIP ?? 'localhost'}:${webShareService.port}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: webShareService.actualHostnameNotifier,
      builder: (context, hostname, child) {
        if (hostname == null || hostname.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.greyLight.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.greyLight.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Resolving hostname...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.greyDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        final displayUrl = _buildDisplayUrl(hostname);
        return GestureDetector(
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: displayUrl));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Link copied to clipboard',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.secondary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  displayUrl,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(width: AppSizes.xs),
                Text('Click to copy',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.primary.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                          fontSize: 10
                        )),
              ],
            ),
          ),
        );
      },
    );
  }
}
