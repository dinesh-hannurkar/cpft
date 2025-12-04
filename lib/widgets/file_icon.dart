import 'package:flutter/material.dart';

class FileIcon extends StatelessWidget {
  final String filename;
  final double size;

  const FileIcon({
    super.key,
    required this.filename,
    this.size = 68,
  });

  @override
  Widget build(BuildContext context) {
    final lower = filename.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    IconData icon;
    Color fg;
    Color bg;

    const imageExt = {
      'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic', 'heif',
    };
    const videoExt = {'mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'};
    const audioExt = {'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'opus'};
    const pdfExt = {'pdf'};
    const archiveExt = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2'};
    const docExt = {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'csv', 'txt'};

    if (imageExt.contains(ext)) {
      icon = Icons.image;
      fg = const Color(0xFF1E88E5);
      bg = const Color(0xFFE3F2FD);
    } else if (videoExt.contains(ext)) {
      icon = Icons.videocam;
      fg = const Color(0xFF6A1B9A);
      bg = const Color(0xFFF3E5F5);
    } else if (audioExt.contains(ext)) {
      icon = Icons.audiotrack;
      fg = const Color(0xFF00897B);
      bg = const Color(0xFFE0F2F1);
    } else if (pdfExt.contains(ext)) {
      icon = Icons.picture_as_pdf;
      fg = const Color(0xFFD32F2F);
      bg = const Color(0xFFFDECEA);
    } else if (archiveExt.contains(ext)) {
      icon = Icons.archive;
      fg = const Color(0xFF5D4037);
      bg = const Color(0xFFEFEBE9);
    } else if (docExt.contains(ext)) {
      icon = Icons.description;
      fg = const Color(0xFF1565C0);
      bg = const Color(0xFFE3F2FD);
    } else if (ext == 'apk') {
      icon = Icons.android;
      fg = const Color(0xFF2E7D32);
      bg = const Color(0xFFE8F5E9);
    } else {
      icon = Icons.insert_drive_file;
      fg = const Color(0xFF455A64);
      bg = const Color(0xFFECEFF1);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: fg, size: size * 0.55),
    );
  }
}
