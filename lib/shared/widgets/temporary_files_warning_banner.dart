import 'package:flutter/material.dart';
import 'package:fylooo/shared/widgets/status_banner.dart';

class TemporaryFilesWarningBanner extends StatelessWidget {
  const TemporaryFilesWarningBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusBanner(
      color: Colors.orange.shade400,
      borderColor: Colors.deepOrange.shade500,
      icon: Icons.download_outlined,
      iconColor: Colors.white,
      title: 'Files are temporary',
      subtitle: 'Save before closing chat',
      useWhiteText: true,
    );
  }
}
