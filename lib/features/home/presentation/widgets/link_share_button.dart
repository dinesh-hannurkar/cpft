import 'package:flutter/material.dart';

class LinkShareButton extends StatelessWidget {
  final VoidCallback onPressed;
  const LinkShareButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(color: Color(0x15000000), blurRadius: 20, offset: Offset(0, 6)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Link Share',
              style: TextStyle(
                color: Color(0xFF1976D2),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(width: 12),
            Icon(Icons.open_in_new, color: Color(0xFF1976D2), size: 20),
          ],
        ),
      ),
    );
  }
}
