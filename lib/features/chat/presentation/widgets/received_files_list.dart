import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

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

class ReceivedFileTile extends StatelessWidget {
  final ReceivedFileItem file;
  final VoidCallback onOpen;
  final VoidCallback onReveal;
  final VoidCallback onSaveAs;

  const ReceivedFileTile({
    super.key,
    required this.file,
    required this.onOpen,
    required this.onReveal,
    required this.onSaveAs,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.insert_drive_file),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        file.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        color: Colors.white,
        onSelected: (value) {
          if (value == 'open') {
            onOpen();
          } else if (value == 'reveal') {
            onReveal();
          } else if (value == 'saveas') {
            onSaveAs();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'open', child: Text('Open')),
          PopupMenuItem(value: 'reveal', child: Text('Reveal in Folder')),
          PopupMenuItem(value: 'saveas', child: Text('Save As...')),
        ],
      ),
      onTap: () async {
        await OpenFilex.open(file.path);
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
