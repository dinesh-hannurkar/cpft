import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:fylooo/core/constants/app_sizes.dart';

class SharedFilesBanner extends StatelessWidget {
  final List<SharedMediaFile> files;
  final VoidCallback onSend;
  final bool enabled;

  const SharedFilesBanner({
    super.key,
    required this.files,
    required this.onSend,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.share,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text(
              '${files.length} file${files.length > 1 ? 's' : ''} selected to send',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: enabled ? onSend : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: enabled ? Colors.white : Colors.grey.shade300,
              foregroundColor: enabled ? Colors.orange.shade600 : Colors.grey.shade600,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Send', style: TextStyle(fontWeight: FontWeight.bold, color: enabled ? Colors.orange.shade600 : Colors.grey.shade600)),
          ),
        ],
      ),
    );
  }
}