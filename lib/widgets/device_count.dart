import 'package:flutter/material.dart';

class DeviceCount extends StatelessWidget {
  const DeviceCount({
    super.key,
    required Map<String, String> discoveredDevices,
    required bool isRefreshing,
  }) : _discoveredDevices = discoveredDevices, _isRefreshing = isRefreshing;

  final Map<String, String> _discoveredDevices;
  final bool _isRefreshing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Text(
            'Found ${_discoveredDevices.length} device${_discoveredDevices.length != 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          if (_isRefreshing) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}
