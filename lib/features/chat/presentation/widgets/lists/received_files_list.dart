import 'package:cpft/features/chat/presentation/widgets/tiles/received_file_tile.dart';
import 'package:flutter/material.dart';

class ReceivedFilesList extends StatelessWidget {
  final List<ReceivedFileItem> files;
  final Function(String path, String name) onOpen;
  final Function(String path, String name) onReveal;
  final Function(String path, String name) onSaveAs;

  const ReceivedFilesList({
    super.key,
    required this.files,
    required this.onOpen,
    required this.onReveal,
    required this.onSaveAs,
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
        final file = files[index];
        return ReceivedFileTile(
          file: file,
          onOpen: () => onOpen(file.path, file.name),
          onReveal: () => onReveal(file.path, file.name),
          onSaveAs: () => onSaveAs(file.path, file.name),
        );
      },
    );
  }
}

class ReceivedFileItem {
  final String name;
  final String path;
  final DateTime timestamp;

  ReceivedFileItem({
    required this.name,
    required this.path,
    required this.timestamp,
  });
}
