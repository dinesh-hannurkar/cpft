import 'package:flutter/material.dart';

class NetworkBanner extends StatelessWidget {
  final String? networkName;
  const NetworkBanner({super.key, this.networkName});

  @override
  Widget build(BuildContext context) {
    final green = const Color(0xFF00C853);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi, color: green, size: 22),
          const SizedBox(width: 8),
          Text(
            networkName != null ? 'Connected to $networkName network' : 'Not connected',
            style: TextStyle(color: green, fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
