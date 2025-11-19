import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'web_server.dart';
import '../../../utils/network_utils.dart';

/// Service to manage web share functionality
class WebShareService {
  WebServer? _webServer;
  final String deviceName;

  // State notifiers
  final ValueNotifier<int> connectedClients = ValueNotifier<int>(0);
  final ValueNotifier<List<SharedFile>> sharedFiles = ValueNotifier<List<SharedFile>>([]);
  final ValueNotifier<List<ReceivedFile>> receivedFiles = ValueNotifier<List<ReceivedFile>>([]);

  // Callbacks for integration with app
  final Function(String filename, int bytesReceived, int totalBytes)? onFileUploadProgress;
  final Function(String filename, String savedPath)? onFileUploadComplete;

  WebShareService({
    required this.deviceName,
    this.onFileUploadProgress,
    this.onFileUploadComplete,
  });

  bool get isRunning => _webServer?.isRunning ?? false;
  int get port => _webServer?.port ?? 8080;

  /// Start the web server
  Future<bool> startWebServer({int port = 8080}) async {
    if (_webServer != null && _webServer!.isRunning) {
      debugPrint('[WebShareService] Web server already running');
      return true;
    }

    _webServer = WebServer(
      deviceName: deviceName,
      onFileUploadProgress: (filename, received, total) {
        debugPrint('[WebShareService] Upload progress: $filename - $received/$total bytes');
        onFileUploadProgress?.call(filename, received, total);
      },
      onFileUploadComplete: (filename, savedPath) {
        debugPrint('[WebShareService] ✅ File upload complete: $filename -> $savedPath');
        onFileUploadComplete?.call(filename, savedPath);
        // Track received file
        receivedFiles.value = [
          ReceivedFile(
            filename: filename,
            path: savedPath,
            sizeBytes: File(savedPath).lengthSync(),
            receivedAt: DateTime.now(),
          ),
          ...receivedFiles.value,
        ];
      },
      onClientConnected: (_) {
        connectedClients.value = _webServer!.connectedClientsCount;
      },
      onClientDisconnected: (_) {
        connectedClients.value = _webServer!.connectedClientsCount;
      },
    );

    final success = await _webServer!.start(port: port);

    if (success) {
      debugPrint('[WebShareService] ✅ Web server started on port $port');
      await _refreshSharedFiles();
      connectedClients.value = _webServer!.connectedClientsCount;
    } else {
      debugPrint('[WebShareService] ❌ Failed to start web server');
    }

    return success;
  }

  /// Stop the web server
  Future<void> stopWebServer() async {
    if (_webServer != null) {
      await _webServer!.stop();
      _webServer = null;
      debugPrint('[WebShareService] Web server stopped');
    }
  }

  /// Get server URL for sharing
  Future<String?> getServerUrl() async {
    if (!isRunning) return null;
    
    // Get the network IP address that other devices can access
    final networkIp = await NetworkUtils.getLanIPv4();
    final ip = networkIp ?? 'localhost'; // Fallback to localhost if network IP not found
    
    return 'http://$ip:$port';
  }

  /// Share a local file (register for browser download)
  Future<String?> shareFile(File file) async {
    if (!isRunning) return null;
    if (!file.existsSync()) return null;
    final id = _webServer!.addFileForDownload(file.path, p.basename(file.path));
    await _refreshSharedFiles();
    return id;
  }

  /// Remove a shared file by id
  Future<void> removeSharedFile(String id) async {
    if (!isRunning) return;
    _webServer!.removeFileFromDownload(id);
    await _refreshSharedFiles();
  }

  Future<void> _refreshSharedFiles() async {
    if (!isRunning) {
      sharedFiles.value = [];
      return;
    }
    final list = _webServer!.getSharedFiles();
    sharedFiles.value = list.map((m) => SharedFile(
      id: m['id'] as String,
      filename: m['filename'] as String,
      sizeBytes: m['size'] as int,
      sharedAt: DateTime.tryParse(m['sharedAt'] as String? ?? '') ?? DateTime.now(),
    )).toList();
  }

  /// Dispose the service
  void dispose() {
    stopWebServer();
  }
}

class SharedFile {
  final String id;
  final String filename;
  final int sizeBytes;
  final DateTime sharedAt;
  SharedFile({
    required this.id,
    required this.filename,
    required this.sizeBytes,
    required this.sharedAt,
  });

  String get humanSize {
    const units = ['B','KB','MB','GB','TB'];
    double size = sizeBytes.toDouble();
    int i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed( (i==0)?0:1)} ${units[i]}';
  }
}

class ReceivedFile {
  final String filename;
  final String path;
  final int sizeBytes;
  final DateTime receivedAt;
  ReceivedFile({
    required this.filename,
    required this.path,
    required this.sizeBytes,
    required this.receivedAt,
  });

  String get humanSize {
    const units = ['B','KB','MB','GB','TB'];
    double size = sizeBytes.toDouble();
    int i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed((i==0)?0:1)} ${units[i]}';
  }
}