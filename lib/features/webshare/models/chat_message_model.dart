import 'package:fylooo/features/webshare/presentation/webrtc_chat_screen.dart';

class ChatMessage {
  final String id;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final int? fileSize;

  ChatMessage({
    required this.id,
    required this.content,
    required this.type,
    required this.timestamp,
    this.fileSize,
  });
}