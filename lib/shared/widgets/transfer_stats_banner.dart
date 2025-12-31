import 'package:flutter/material.dart';
import 'package:fylooo/shared/widgets/status_banner.dart';

class TransferStatsBanner extends StatelessWidget {
  final int totalBytes;
  final Duration duration;

  const TransferStatsBanner({
    super.key,
    required this.totalBytes,
    required this.duration,
  });

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '${seconds}s';
    final minutes = duration.inMinutes;
    final remainingSeconds = seconds % 60;
    if (minutes < 60) return '${minutes}m ${remainingSeconds}s';
    final hours = duration.inHours;
    final remainingMinutes = minutes % 60;
    return '${hours}h ${remainingMinutes}m';
  }

  String _formatSpeed(int bytes, Duration duration) {
    final micros = duration.inMicroseconds;
    if (micros <= 0 || bytes <= 0) return '0 MiB/s (0 Mbps)';

    final seconds = micros / 1000000.0;
    final bytesPerSecond = bytes / seconds;
    final mibPerSecond = bytesPerSecond / (1024.0 * 1024.0);

    return '${mibPerSecond.toStringAsFixed(1)} MiB/s';
  }

  @override
  Widget build(BuildContext context) {
    return StatusBanner(
      color: Colors.green.shade400,
      borderColor: Colors.teal.shade500,
      icon: Icons.check_circle_outline,
      iconColor: Colors.white,
      title: 'Transfer Complete: ${_formatBytes(totalBytes)} in ${_formatDuration(duration)}',
      subtitle: 'Avg Speed: ${_formatSpeed(totalBytes, duration)}',
      useWhiteText: true,
    );
  }
}
