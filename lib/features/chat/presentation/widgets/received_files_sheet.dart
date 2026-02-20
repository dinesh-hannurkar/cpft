import 'dart:io' as io;
import 'package:flutter/material.dart';
import '../../models/received_file.dart';

class ReceivedFilesSheet extends StatelessWidget {
  final List<ReceivedFile> files;
  final Future<void> Function(String path, String name)? onOpen;
  final Future<void> Function(String path, String name)? onReveal;
  final Future<void> Function(String path, String name)? onSaveAs;
  const ReceivedFilesSheet({
    super.key,
    required this.files,
    this.onOpen,
    this.onReveal,
    this.onSaveAs,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(child: Text('No received files yet')),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final rf = files[index];
        return ListTile(
          leading: const Icon(Icons.insert_drive_file),
          title: Text(rf.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(rf.path, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: PopupMenuButton<String>(
            color: Colors.white,
            onSelected: (value) async {
              if (value == 'open') {
                await onOpen?.call(rf.path, rf.name);
              } else if (value == 'reveal') {
                try {
                  final file = io.File(rf.path);
                  final parentDir = file.parent.path;
                  debugPrint(
                    '[ReceivedFilesSheet] Revealing file in: $parentDir',
                  );
                  await onReveal?.call(parentDir, rf.name);
                } catch (e) {
                  debugPrint('[ReceivedFilesSheet] Reveal error: $e');
                }
              } else if (value == 'saveas') {
                await onSaveAs?.call(rf.path, rf.name);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(value: 'open', child: Text('Open')),
              PopupMenuItem<String>(value: 'reveal', child: Text('Reveal')),
              PopupMenuItem<String>(value: 'saveas', child: Text('Save As')),
            ],
          ),
        );
      },
    );
  }
}
