import 'package:cpft/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

class NetworkBanner extends StatelessWidget {
  final String? networkName;
  const NetworkBanner({super.key, this.networkName});

  @override
  Widget build(BuildContext context) {
    final isConnected = networkName != null && networkName != 'Not Connected';
    final color = isConnected ? const Color(0xFF00C853) : AppColors.red;
    final icon = isConnected ? Icons.wifi : Icons.wifi_off;
    final text = isConnected ? 'Connected to $networkName' : 'Not connected';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
