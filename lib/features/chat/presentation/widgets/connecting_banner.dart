import 'package:flutter/material.dart';

class ConnectingBanner extends StatelessWidget {
  final String deviceName;
  const ConnectingBanner({super.key, required this.deviceName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.blue.shade100,
      child: Row(children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Connecting to $deviceName...',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}
