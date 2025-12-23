import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:fylooo/shared/showcase/showcase_helper.dart';
import '../../utils/file_utils.dart';
import 'file_type_icon.dart';
import '../../models/connection_state.dart';

class CompletedFileCard extends StatelessWidget {
  final DeviceMessage message;
  final bool isMine;
  final String? savedPath;
  final void Function(String path, String name)? onOpen;
  final void Function(String path, String name)? onSaveAs;
  final bool showShowcase;
  const CompletedFileCard({
    super.key, 
    required this.message, 
    required this.isMine, 
    required this.savedPath, 
    this.onOpen, 
    this.onSaveAs,
    this.showShowcase = false,
  });

  @override
  Widget build(BuildContext context) {
    final name = message.content;
    final size = message.metadata?['size'] as int?;
    final mime = message.metadata?['mime'] as String?;
    
    final cardWidget = Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: savedPath != null ? () => onOpen?.call(savedPath!, name) : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 6),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 4 : 16),
                bottomRight: Radius.circular(isMine ? 16 : 4),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
              ],
              border: Border.all(color: Colors.blue.shade50),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                FileTypeIcon(name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                          name.contains('.') ? extensionTrim(name.split('.').last) : 'FILE',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF1565C0), letterSpacing: .5),
                        ),
                      ),
                      Expanded(
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    if (mime != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(readableMime(mime), style: const TextStyle(color: Colors.black45, fontSize: 12)),
                      ),
                    if (size != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Row(children: [
                          Text(formatBytes(size), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                          const Spacer(),
                          Text(formatTime(message.timestamp), style: const TextStyle(color: Colors.black38, fontSize: 10)),
                        ]),
                      ),
                  ]),
                ),
                // Show Save label for received files (not sent files)
                if (!isMine && savedPath != null)
                  Showcase(
                    key: ShowcaseHelper.saveButtonKey,
                    disableBarrierInteraction: false,
                    targetPadding: const EdgeInsets.all(8),
                    title: 'Save File',
                    description: 'Tap to save this file to your device storage',
                    tooltipBackgroundColor: Colors.white,
                    textColor: Colors.black,
                    descTextStyle: const TextStyle(fontSize: 12, color: Colors.black87),
                    titleTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16),
                    tooltipBorderRadius: BorderRadius.circular(12),
                    targetBorderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      onTap: () => onSaveAs?.call(savedPath!, name),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
            ]),
          ),
        ),
      ),
    );
    
    // Wrap with showcase for received files only
    if (showShowcase && !isMine) {
      return Showcase(
        key: ShowcaseHelper.receivedFileCardKey,
        disableBarrierInteraction: false,
        targetPadding: const EdgeInsets.all(8),
        title: 'Received File',
        description: 'Tap on the file to open it, or use the Save button to permanently save it to your device',
        tooltipBackgroundColor: Colors.white,
        textColor: Colors.black,
        descTextStyle: const TextStyle(fontSize: 12, color: Colors.black87),
        titleTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16),
        tooltipBorderRadius: BorderRadius.circular(12),
        targetBorderRadius: BorderRadius.circular(16),
        child: cardWidget,
      );
    }
    
    return cardWidget;
  }
}
