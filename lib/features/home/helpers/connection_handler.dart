import 'package:flutter/material.dart';
import 'package:fylooo/features/chat/models/connection_state.dart';
import 'package:fylooo/features/chat/services/connection_manager.dart';
import 'package:fylooo/features/chat/presentation/chat_screen.dart';
import 'package:fylooo/features/home/presentation/widgets/sheets/connection_flow_dialog.dart';
import 'package:fylooo/services/discovery_service.dart';
import 'package:fylooo/shared/widgets/dialog_helpers.dart' as app_dialog;
import 'package:share_plus/share_plus.dart';

/// Helper class for handling device connection logic
class ConnectionHandler {
  /// Handle device tap with connection state awareness
  static Future<bool> handleDeviceTap({
    required BuildContext context,
    required DeviceInfo device,
    required ConnectionManager connectionManager,
    required DiscoveryService discoveryService,
    required String myDeviceName,
    List<XFile>? droppedFiles,
    VoidCallback? onFilesSent,
    bool replace = false,
    bool silent = false,
  }) async {
    debugPrint(
      '[ConnectionHandler] 🔍 Tapped device: ${device.name} (IP: ${device.ip})',
    );
    debugPrint(
      '[ConnectionHandler] 🔍 Active connections keys: ${connectionManager.activeConnections.keys.join(", ")}',
    );

    // Try to find connection by name first, then by IP
    var existingConnection = connectionManager.getConnection(device.name);
    if (existingConnection == null) {
      debugPrint(
        '[ConnectionHandler] 🔍 No connection found by name, trying by IP: ${device.ip}',
      );
      existingConnection = connectionManager.getConnection(device.ip);
    }

    debugPrint(
      '[ConnectionHandler] 🔍 Connection found: ${existingConnection != null}, isConnected: ${existingConnection?.isConnected}, status: ${existingConnection?.currentConnection?.status}',
    );

    if (existingConnection != null) {
      final status = existingConnection.currentConnection?.status;
      final connectionDeviceName =
          existingConnection.currentConnection?.deviceName ?? device.name;

      // If connected or connecting to the EXACT same IP, navigate directly
      if ((status == ConnectionStatus.connected ||
              status == ConnectionStatus.connecting) &&
          existingConnection.currentConnection?.ipAddress == device.ip) {
        debugPrint(
          '[ConnectionHandler] ✅ Already connected/connecting to $connectionDeviceName exactly at ${device.ip}, navigating to chat',
        );
        _navigateToChat(
          context: context,
          deviceName: connectionDeviceName,
          ipAddress: device.ip,
          myDeviceName: myDeviceName,
          connectionManager: connectionManager,
          discoveryService: discoveryService,
          droppedFiles: droppedFiles,
          onFilesSent: onFilesSent,
          replace: replace,
        );
        return true;
      } else if (status == ConnectionStatus.connected ||
          status == ConnectionStatus.connecting) {
        // We are "connected" according to the old socket, but the IP we are
        // trying to reach now (e.g. 192.168.49.1) is DIFFERENT.
        // This happens during Hotspot Handover — the old WiFi socket hasn't
        // timed out yet, but we need to force a reconnection on the new IP.
        debugPrint(
          '[ConnectionHandler] 🔄 IP changed during handover (Old: ${existingConnection.currentConnection?.ipAddress}, New: ${device.ip}). Forcing disconnect to allow reconnect.',
        );
        existingConnection.disconnect(); // Force kill the stale socket
        _navigateToChat(
          context: context,
          deviceName: connectionDeviceName,
          ipAddress: device.ip,
          myDeviceName: myDeviceName,
          connectionManager: connectionManager,
          discoveryService: discoveryService,
          droppedFiles: droppedFiles,
          onFilesSent: onFilesSent,
          replace: replace,
        );
        return true;
      } else if (status == ConnectionStatus.disconnected) {
        // Connection exists but is disconnected - navigate to chat to allow reconnect
        debugPrint(
          '[ConnectionHandler] 📡 Connection to $connectionDeviceName is disconnected, navigating to chat for reconnect',
        );
        _navigateToChat(
          context: context,
          deviceName: connectionDeviceName,
          ipAddress: device.ip,
          myDeviceName: myDeviceName,
          connectionManager: connectionManager,
          discoveryService: discoveryService,
          droppedFiles: droppedFiles,
          onFilesSent: onFilesSent,
          replace: replace,
        );
        return true;
      }
    }

    if (silent) {
      debugPrint(
        '[ConnectionHandler] Silent mode: Connecting directly to ${device.ip}',
      );
      final service = connectionManager.getOrCreateConnection(device.name);
      final success = await service.connect(
        device.name,
        device.ip,
        DiscoveryService.p2pPort,
      );

      if (success && context.mounted) {
        _navigateToChat(
          context: context,
          deviceName: device.name,
          ipAddress: device.ip,
          myDeviceName: myDeviceName,
          connectionManager: connectionManager,
          discoveryService: discoveryService,
          droppedFiles: droppedFiles,
          onFilesSent: onFilesSent,
          replace: replace,
        );
      }
      return success;
    }

    // Not connected - show confirmation dialog
    debugPrint(
      '[ConnectionHandler] Showing connection dialog for ${device.name}',
    );
    final result = await app_dialog.showAppDialog(
      context: context,
      builder: (_) => ConnectionFlowDialog(
        myDeviceName: myDeviceName,
        peerDeviceName: device.name,
        peerIp: device.ip,
        p2pPort: DiscoveryService.p2pPort,
        connectionManager: connectionManager,
        discoveryService: discoveryService,
      ),
    );

    if (result == 'connected' && context.mounted) {
      _navigateToChat(
        context: context,
        deviceName: device.name,
        ipAddress: device.ip,
        myDeviceName: myDeviceName,
        connectionManager: connectionManager,
        discoveryService: discoveryService,
        droppedFiles: droppedFiles,
        onFilesSent: onFilesSent,
        replace: replace,
      );
      return true;
    }
    return false;
  }

  static void _navigateToChat({
    required BuildContext context,
    required String deviceName,
    required String ipAddress,
    required String myDeviceName,
    required ConnectionManager connectionManager,
    required DiscoveryService discoveryService,
    List<XFile>? droppedFiles,
    VoidCallback? onFilesSent,
    bool replace = false,
  }) {
    if (replace) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/chat'),
          builder: (_) => ChatScreen(
            deviceName: deviceName,
            ipAddress: ipAddress,
            port: DiscoveryService.p2pPort,
            myDeviceName: myDeviceName,
            connectionManager: connectionManager,
            discoveryService: discoveryService,
            initialDeviceId: deviceName,
            droppedFiles: droppedFiles,
            onFilesSent: onFilesSent,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/chat'),
          builder: (_) => ChatScreen(
            deviceName: deviceName,
            ipAddress: ipAddress,
            port: DiscoveryService.p2pPort,
            myDeviceName: myDeviceName,
            connectionManager: connectionManager,
            discoveryService: discoveryService,
            initialDeviceId: deviceName,
            droppedFiles: droppedFiles,
            onFilesSent: onFilesSent,
          ),
        ),
      );
    }
  }
}
