import 'dart:io';
import 'package:cpft/features/webshare/models/webshare_models.dart';
import 'package:cpft/utils/time_utils.dart';
import 'package:cpft/widgets/file_icon.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/dialog_helpers.dart' as app_dialog;
import '../../../shared/widgets/app_confirm_dialog.dart';
import '../../../services/discovery_service.dart';

class WebFileManagerScreen extends StatefulWidget {
  final DiscoveryService discoveryService;

  const WebFileManagerScreen({super.key, required this.discoveryService});

  @override
  State<WebFileManagerScreen> createState() => _WebFileManagerScreenState();
}

class _WebFileManagerScreenState extends State<WebFileManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<ReceivedFileInfo> _receivedFiles = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    widget.discoveryService.addWebFileListener(_onFileReceived);
    _loadReceivedFiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    widget.discoveryService.removeWebFileListener(_onFileReceived);
    super.dispose();
  }

  void _onFileReceived(String filename, String path) {
    setState(() {
      _receivedFiles.insert(
        0,
        ReceivedFileInfo(
          filename: filename,
          path: path,
          receivedAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> _loadReceivedFiles() async {
    // TODO: Load from persistent storage if needed
    // For now, files are only tracked during app session
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web File Manager'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.upload_file), text: 'Shared to Web'),
            Tab(icon: Icon(Icons.download), text: 'Received from Web'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSharedFilesTab(), _buildReceivedFilesTab()],
      ),
    );
  }

  Widget _buildSharedFilesTab() {
    final sharedFilesData = widget.discoveryService.getSharedFiles();
    final sharedFiles = sharedFilesData
        .map(
          (data) => SharedFileInfo(
            id: data['id'] as String,
            filename: data['filename'] as String,
            path: data['path'] as String,
            size: data['size'] as int,
            sharedAt: DateTime.parse(data['sharedAt'] as String),
          ),
        )
        .toList();

    if (sharedFiles.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cloud_upload,
        title: 'No Files Shared',
        message:
            'Files you share to the web browser will appear here.\n\nUse the "Share to Web" option to make files available for download.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sharedFiles.length,
      itemBuilder: (context, index) {
        final file = sharedFiles[index];
        return _buildSharedFileCard(file);
      },
    );
  }

  Widget _buildReceivedFilesTab() {
    if (_receivedFiles.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cloud_download,
        title: 'No Files Received',
        message:
            'Files uploaded from the web browser will appear here.\n\nShare the web link and upload files to see them listed.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_receivedFiles.length} file(s) received',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ),
              TextButton.icon(
                onPressed: _clearReceivedFiles,
                icon: const Icon(Icons.delete_sweep, size: 20),
                label: const Text('Clear All'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _receivedFiles.length,
            itemBuilder: (context, index) {
              final file = _receivedFiles[index];
              return _buildReceivedFileCard(file, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSharedFileCard(SharedFileInfo file) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: FileIcon(filename: file.filename),
        ),
        title: Text(
          file.filename,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              _formatFileSize(file.size),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              'Shared ${TimeUtils.formatTimeAgo(file.sharedAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: 'Remove from web',
          onPressed: () => _removeSharedFile(file),
        ),
        onTap: () => _showFileOptions(file.path),
      ),
    );
  }

  Widget _buildReceivedFileCard(ReceivedFileInfo file, int index) {
    final fileExists = File(file.path).existsSync();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: FileIcon(filename: file.filename),
        ),
        title: Text(
          file.filename,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (fileExists)
              Text(
                _formatFileSize(File(file.path).lengthSync()),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            Text(
              'Received ${TimeUtils.formatTimeAgo(file.receivedAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            if (!fileExists)
              Text(
                'File deleted from device',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red[400],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'remove') {
              _removeReceivedFile(index);
            } else if (value == 'open') {
              _showFileOptions(file.path);
            } else if (value == 'delete') {
              _deleteReceivedFile(file, index);
            }
          },
          itemBuilder: (context) => [
            if (fileExists)
              const PopupMenuItem(
                value: 'open',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 20),
                    SizedBox(width: 12),
                    Text('Open'),
                  ],
                ),
              ),
            if (fileExists)
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Delete File', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'remove',
              child: Row(
                children: [
                  Icon(Icons.clear, size: 20),
                  SizedBox(width: 12),
                  Text('Remove from List'),
                ],
              ),
            ),
          ],
        ),
        onTap: fileExists ? () => _showFileOptions(file.path) : null,
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  void _removeSharedFile(SharedFileInfo file) {
    app_dialog.showAppDialog(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: 'Remove from Web?',
        content: Text(
          'Stop sharing "${file.filename}" on the web?\n\nThe file will no longer be available for download.',
        ),
        cancelLabel: 'Cancel',
        confirmLabel: 'Remove',
        destructive: true,
        onConfirm: () {
          widget.discoveryService.removeFileFromWeb(file.id);
          Navigator.pop(context);
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Removed "${file.filename}" from web',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
            ),
          );
        },
      ),
    );
  }

  void _removeReceivedFile(int index) {
    setState(() {
      _receivedFiles.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Removed from list',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  void _deleteReceivedFile(ReceivedFileInfo file, int index) {
    app_dialog.showAppDialog(
      context: context,
      builder: (context) => AppConfirmDialog(
        title: 'Delete File?',
        content: Text(
          'Permanently delete "${file.filename}" from device storage?\n\nThis cannot be undone.',
        ),
        cancelLabel: 'Cancel',
        confirmLabel: 'Delete',
        destructive: true,
        onConfirm: () async {
          try {
            final fileToDelete = File(file.path);
            if (fileToDelete.existsSync()) {
              await fileToDelete.delete();
            }
            setState(() {
              _receivedFiles.removeAt(index);
            });
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Deleted "${file.filename}"',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Failed to delete file: $e',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _clearReceivedFiles() {
    app_dialog.showAppDialog(
      context: context,
      builder: (context) => const AppConfirmDialog(
        title: 'Clear All History?',
        content: Text(
          'Remove all received files from the list?\n\nThe actual files will not be deleted from storage.',
        ),
        cancelLabel: 'Cancel',
        confirmLabel: 'Clear',
      ),
    );
  }

  void _showFileOptions(String path) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'File location: $path',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
