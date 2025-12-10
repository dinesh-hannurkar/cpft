import 'package:cpft/features/chat/presentation/widgets/lists/received_files_list.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

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
