import 'package:cpft/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

class NetworkIndicator extends StatelessWidget {
  const NetworkIndicator({
    super.key,
    required String? networkName,
  }) : _networkName = networkName;

  final String? _networkName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          (_networkName != null && _networkName != 'Not Connected')
              ? Icons.wifi
              : Icons.wifi_off,
          color: (_networkName != null && _networkName != 'Not Connected')
              ? const Color(0xFF00C853)
              : AppColors.red,
          size: 22,
        ),
        const SizedBox(width: 8),
        Text(
          (_networkName != null && _networkName != 'Not Connected')
              ? 'Connected to $_networkName'
              : 'Not connected',
          style: TextStyle(
            color: (_networkName != null && _networkName != 'Not Connected')
                ? const Color(0xFF00C853)
                : AppColors.red,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
