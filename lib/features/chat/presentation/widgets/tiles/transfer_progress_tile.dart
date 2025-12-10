import 'package:flutter/material.dart';
import '../../../models/transfer_progress.dart';
import '../../../utils/file_utils.dart';
import '../file_type_icon.dart';

class TransferProgressTile extends StatelessWidget {
  final TransferProgress progress;
  final VoidCallback? onCancel;
  final VoidCallback? onResume;
  const TransferProgressTile({super.key, required this.progress, this.onCancel, this.onResume});

  @override
  Widget build(BuildContext context) {
    final tp = progress;
    final percent = tp.total > 0 ? (tp.progress / tp.total * 100).clamp(0, 100) : null;
    final now = DateTime.now();
    final stalled = now.difference(tp.lastUpdate).inSeconds >= 10 && tp.progress > 0 && (tp.total == 0 || tp.progress < tp.total);
    final failed = now.difference(tp.lastUpdate).inSeconds >= 60 && tp.progress > 0 && (tp.total == 0 || tp.progress < tp.total);
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      padding: const EdgeInsets.only(left: 12, right: 0, top: 12, bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
        border: Border.all(color: Colors.blue.shade50),
      ),
      child: Column(
        children: [
          Row(children: [
            FileTypeIcon(tp.name),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFBBDEFB)),
                  ),
                  child: Text(
                    extensionTrim(tp.name.split('.').last),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF1565C0), letterSpacing: .5),
                  ),
                ),
                Expanded(
                  child: Text(tp.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                ),
                PopupMenuButton<String>(
                  color: Colors.white,
                  icon: const Icon(Icons.more_vert, size: 28),
                  onSelected: (val) async {
                    if (val == 'cancel') {
                      onCancel?.call();
                    } else if (val == 'resume') {
                      onResume?.call();
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'resume', child: Text('Resume')),
                    PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                  ],
                ),
              ]),
              if (tp.mime != null)
                Text(readableMime(tp.mime!), style: const TextStyle(color: Colors.black45, fontSize: 12)),
              if (tp.total > 0)
                Text(formatBytes(tp.total), style: const TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 6),
            ])),
          ]),
          SizedBox(
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: tp.total > 0 ? (tp.progress / tp.total).clamp(0.0, 1.0) : null,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(
                    failed ? Colors.redAccent : (stalled ? Colors.orange : Colors.blue.shade400),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(children: [
              Expanded(
                child: Text(tp.total > 0 ? '${formatBytes(tp.progress.toInt())} / ${formatBytes(tp.total)}' : 'Preparing…',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ),
              if (failed)
                const Text('Failed', style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w700))
              else if (stalled)
                const Text('Stalled', style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w600))
              else if (tp.speed > 0)
                Text(formatSpeed(tp.speed).replaceAll('/s', '/s'),
                    style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (percent != null)
                Text('${percent.toStringAsFixed(0)}% completed', style: const TextStyle(fontSize: 11, color: Colors.black54)),
              const SizedBox(width: 8),
              Text(formatTime(DateTime.now()), style: const TextStyle(fontSize: 10, color: Colors.black38)),
            ]),
          ),
        ],
      ),
    );
  }
}
