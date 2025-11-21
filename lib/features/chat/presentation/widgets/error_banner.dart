import 'package:flutter/material.dart';

class ErrorBanner extends StatelessWidget {
  final String? error;
  final VoidCallback onRetry;
  const ErrorBanner({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.red.shade100,
      child: Row(children: [
        Icon(Icons.error_outline, color: Colors.red.shade900),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            error ?? 'Connection failed',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}
