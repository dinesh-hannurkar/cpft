import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

class MessageInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool enabled;
  const MessageInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.enabled = true,
  });

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
    widget.controller.addListener(_handleTextChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    widget.controller.removeListener(_handleTextChange);
    super.dispose();
  }

  void _handleFocus() => setState(() {});
  void _handleTextChange() => setState(() {});

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  widget.focusNode.requestFocus();
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.focusNode.hasFocus
                          ? [const Color(0xFF64B5F6), const Color(0xFF81D4FA)]
                          : [const Color(0xFFCAE6FF), const Color(0xFFE3F2FD)],
                    ),
                  ),
                  padding: const EdgeInsets.all(1.2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(27),
                    ),
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (Platform.isAndroid || Platform.isIOS) {
                          return KeyEventResult.ignored;
                        }

                        if (event is KeyDownEvent &&
                            (event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey ==
                                    LogicalKeyboardKey.numpadEnter)) {
                          final isShiftPressed =
                              HardwareKeyboard.instance.logicalKeysPressed
                                  .contains(LogicalKeyboardKey.shiftLeft) ||
                              HardwareKeyboard.instance.logicalKeysPressed
                                  .contains(LogicalKeyboardKey.shiftRight);

                          if (!isShiftPressed) {
                            if (_hasText) {
                              _trySend();
                            }
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          border: InputBorder.none,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                          ),
                          focusedBorder: InputBorder.none,
                        ),
                        style: const TextStyle(color: Colors.black87),
                        cursorColor: Colors.blue,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _hasText ? _trySend : null,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _hasText
                      ? const LinearGradient(
                          colors: [Color(0xFF2F80ED), Color(0xFF56CCF2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: _hasText ? null : const Color(0xFFE9EEF3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.send,
                  size: 22,
                  color: _hasText ? Colors.white : Colors.blueGrey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _trySend() {
    if (_hasText) {
      widget.onSend();
    }
  }
}
