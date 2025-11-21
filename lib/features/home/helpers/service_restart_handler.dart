import 'package:flutter/material.dart';
import 'package:cpft/services/discovery_service.dart';
import 'package:cpft/features/webshare/services/web_server.dart';

/// Helper class for managing service restarts
class ServiceRestartHandler {
  /// Restart all discovery services with user feedback
  static Future<void> restartServices({
    required BuildContext context,
    required DiscoveryService discoveryService,
    required Function(bool) setRestartingState,
  }) async {
    setRestartingState(true);

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Restarting all services...',
          style: TextStyle(color: Colors.white),
        ),
        duration: Duration(seconds: 3),
      ),
    );

    try {
      // Check web server status
      final portInUse = await WebServer.isPortInUse();
      if (portInUse) {
        debugPrint(
          '[ServiceRestart] Web server detected on port 8080, stopping it...',
        );
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Stopping web server...',
              style: TextStyle(color: Colors.white),
            ),
            duration: Duration(seconds: 1),
          ),
        );

        final stopped = await WebServer.forceStop();
        if (stopped) {
          debugPrint('[ServiceRestart] Web server force stopped successfully');
        } else {
          debugPrint('[ServiceRestart] Failed to force stop web server');
        }

        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Web server stopped',
              style: TextStyle(color: Colors.white),
            ),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Restart device discovery
      await discoveryService.restartDiscovery();

      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Services restarted successfully',
            style: TextStyle(color: Colors.white),
          ),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to restart services: $e',
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setRestartingState(false);
    }
  }
}
