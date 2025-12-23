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
  static Future<void> handleDeviceTap({
    required BuildContext context,
    required DeviceInfo device,
    required ConnectionManager connectionManager,
    required DiscoveryService discoveryService,
    required String myDeviceName,
    List<XFile>? droppedFiles,
    VoidCallback? onFilesSent,
  }) async {
    debugPrint('[ConnectionHandler] 🔍 Tapped device: ${device.name} (IP: ${device.ip})');
    debugPrint('[ConnectionHandler] 🔍 Active connections keys: ${connectionManager.activeConnections.keys.join(", ")}');

    // Try to find connection by name first, then by IP
    var existingConnection = connectionManager.getConnection(device.name);
    if (existingConnection == null) {
      debugPrint('[ConnectionHandler] 🔍 No connection found by name, trying by IP: ${device.ip}');
      existingConnection = connectionManager.getConnection(device.ip);
    }

    debugPrint('[ConnectionHandler] 🔍 Connection found: ${existingConnection != null}, isConnected: ${existingConnection?.isConnected}, status: ${existingConnection?.currentConnection?.status}');

    if (existingConnection != null) {
      final status = existingConnection.currentConnection?.status;
      final connectionDeviceName = existingConnection.currentConnection?.deviceName ?? device.name;

      // If connected or connecting, navigate directly
      if (status == ConnectionStatus.connected || status == ConnectionStatus.connecting) {
        debugPrint('[ConnectionHandler] ✅ Already connected/connecting to $connectionDeviceName, navigating to chat');
        _navigateToChat(
          context: context,
          deviceName: connectionDeviceName,
          ipAddress: device.ip,
          myDeviceName: myDeviceName,
          connectionManager: connectionManager,
          droppedFiles: droppedFiles,
          onFilesSent: onFilesSent,
        );
        return;
      } else if (status == ConnectionStatus.disconnected) {
        // Connection exists but is disconnected - navigate to chat to allow reconnect
        debugPrint('[ConnectionHandler] 📡 Connection to $connectionDeviceName is disconnected, navigating to chat for reconnect');
        _navigateToChat(
          context: context,
          deviceName: connectionDeviceName,
          ipAddress: device.ip,
          myDeviceName: myDeviceName,
          connectionManager: connectionManager,
          droppedFiles: droppedFiles,
          onFilesSent: onFilesSent,
        );
        return;
      }
    }

    // Not connected - show confirmation dialog
    debugPrint('[ConnectionHandler] Showing connection dialog for ${device.name}');
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
        droppedFiles: droppedFiles,
        onFilesSent: onFilesSent,
      );
    }
  }

  static void _navigateToChat({
    required BuildContext context,
    required String deviceName,
    required String ipAddress,
    required String myDeviceName,
    required ConnectionManager connectionManager,
    List<XFile>? droppedFiles,
    VoidCallback? onFilesSent,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          deviceName: deviceName,
          ipAddress: ipAddress,
          port: DiscoveryService.p2pPort,
          myDeviceName: myDeviceName,
          connectionManager: connectionManager,
          initialDeviceId: deviceName,
          droppedFiles: droppedFiles,
          onFilesSent: onFilesSent,
        ),
      ),
    );
  }
}
