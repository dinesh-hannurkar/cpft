import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../services/share_intent_service.dart';
import '../../core/constants/app_sizes.dart';

class SharedContentBanner extends StatefulWidget {
  const SharedContentBanner({super.key});

  @override
  State<SharedContentBanner> createState() => _SharedContentBannerState();
}

class _SharedContentBannerState extends State<SharedContentBanner> {
  List<SharedMediaFile> _sharedFiles = [];

  @override
  void initState() {
    super.initState();
    _listenForSharedContent();
  }

  void _listenForSharedContent() {
    ShareIntentService().sharedFilesStream.listen((files) {
      if (mounted) {
        setState(() {
          _sharedFiles = List<SharedMediaFile>.from(files);
        });
      }
    });

    // Check for initial shared files
    _sharedFiles = List<SharedMediaFile>.from(ShareIntentService().getCurrentSharedFiles());
  }

  @override
  Widget build(BuildContext context) {
    if (_sharedFiles.isEmpty) {
      return const SizedBox.shrink();
    }

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
              '${_sharedFiles.length} file${_sharedFiles.length > 1 ? 's' : ''} selected to transfer - select device to start transfer',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              ShareIntentService().clearSharedFiles();
              setState(() {
                _sharedFiles.clear();
              });
            },
            icon: const Icon(
              Icons.close,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  void _handleSharedFiles(BuildContext context) {
    // Removed - send files option should be in chat
  }
}