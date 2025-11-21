import 'package:flutter/material.dart';
import '../../models/connection_state.dart';
import '../../utils/file_utils.dart';

class MessageBubble extends StatelessWidget {
  final DeviceMessage message;
  final bool isMine;
  const MessageBubble({super.key, required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final isHandshake = message.type == 'handshake';
    final isGoodbye = message.type == 'goodbye';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: isMine ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (isHandshake || isGoodbye)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isHandshake ? Icons.handshake : Icons.waving_hand, size: 16, color: isMine ? Colors.white70 : Colors.black54),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  message.content,
                  style: TextStyle(
                    color: isMine ? Colors.white : Colors.black87,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ])
          else
            Text(message.content, style: TextStyle(color: isMine ? Colors.white : Colors.black87, fontSize: 15)),
          const SizedBox(height: 4),
          Text(formatTime(message.timestamp), style: TextStyle(color: isMine ? Colors.white70 : Colors.black54, fontSize: 10)),
        ]),
      ),
    );
  }
}
