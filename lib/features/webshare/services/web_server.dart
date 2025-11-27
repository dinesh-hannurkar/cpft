import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:mime/mime.dart';

/// Web server for browser-based file transfers
class WebServer {
  HttpServer? _server;
  int _port = 80;
  final String deviceName;
  final List<WebSocket> _connectedClients = [];
  
  // Static registry of running instances for force stopping
  static final Set<WebServer> _runningInstances = {};
  
  // Files available for download
  final Map<String, _AvailableFile> _availableFiles = {};
  
  // Uploaded files for deletion
  final Map<String, String> _uploadedFiles = {}; // filename -> path
  
  bool _isRunning = false;
  
  // Callbacks for integration with app
  final Function(String filename, Uint8List data)? onFileReceived;
  final Function(String clientId)? onClientConnected;
  final Function(String clientId)? onClientDisconnected;
  final Function(String filename, int bytesReceived, int totalBytes)? onFileUploadProgress;
  final Function(String filename, String savedPath)? onFileUploadComplete;
  
  WebServer({
    required this.deviceName,
    this.onFileReceived,
    this.onClientConnected,
    this.onClientDisconnected,
    this.onFileUploadProgress,
    this.onFileUploadComplete,
  });

  /// Check if the web server port is already in use
  static Future<bool> isPortInUse({int port = 80}) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 500));
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Force stop any web server running on the specified port
  static Future<bool> forceStop({int port = 80}) async {
    debugPrint('[WebServer] Attempting to force stop servers on port $port');
    
    bool stoppedAny = false;
    final instancesToStop = _runningInstances.where((server) => server._port == port).toList();
    
    for (final server in instancesToStop) {
      debugPrint('[WebServer] Force stopping instance on port ${server._port}');
      await server.stop();
      stoppedAny = true;
    }
    
    if (!stoppedAny) {
      debugPrint('[WebServer] No running instances found on port $port');
    }
    
    return stoppedAny;
  }

  bool get isRunning => _isRunning;
  int get port => _port;
  int get connectedClientsCount => _connectedClients.length;
  
  /// Start the web server
  Future<bool> start({int port = 80}) async {
    if (_server != null) {
      debugPrint('[WebServer] Already running');
      return true;
    }

    _port = port;
    
    try {
      // Prefer dual-stack (IPv6 with IPv4-mapped) when available
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv6, _port, v6Only: false);
        
        debugPrint('[WebServer] ✅ Started (dual-stack) on port $_port');
      } catch (e) {
        // Fallback to IPv4 only
        debugPrint('[WebServer] Dual-stack bind failed: $e. Falling back to IPv4...');
        _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
        debugPrint('[WebServer] ✅ Started (IPv4) on port $_port');
      }

      _server!.listen(_handleRequest);
      _isRunning = true;
      _runningInstances.add(this); // Register this instance
      return true;
    } catch (e) {
      if (e is SocketException && e.message.contains('Address already in use')) {
        debugPrint('[WebServer] Port already in use, assuming server is running externally');
        _isRunning = true;
        return true;
      }
      debugPrint('[WebServer] ❌ Failed to start: $e');
      return false;
    }
  }

  /// Stop the web server
  Future<void> stop() async {
    debugPrint('[WebServer] Stopping web server...');
    // Always reset the running flag, even for external servers
    _isRunning = false;
    
    if (_server == null) {
      debugPrint('[WebServer] No server instance to stop (external server)');
      return;
    }
    
    // Close all WebSocket connections
    for (var ws in _connectedClients) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _connectedClients.clear();
    
    await _server?.close();
    _server = null;
    _runningInstances.remove(this); // Unregister this instance
    debugPrint('[WebServer] Stopped');
  }

  /// Handle HTTP requests
  void _handleRequest(HttpRequest request) async {
    final uri = request.uri;
    
    // CORS headers for browser requests
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    // Handle CORS preflight
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      if (uri.path == '/' || uri.path == '/index.html') {
        _serveWebPage(request);
      } else if (uri.path == '/ws') {
        await _handleWebSocket(request);
      } else if (uri.path == '/upload') {
        await _handleFileUpload(request);
      } else if (uri.path == '/files') {
        _serveFileList(request);
      } else if (uri.path.startsWith('/files/') && request.method == 'DELETE') {
        // Delete a shared file
        final fileId = uri.pathSegments.last;
        if (_availableFiles.containsKey(fileId)) {
          removeFileFromDownload(fileId);
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(json.encode({'deleted': fileId}));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.headers.contentType = ContentType.json;
          request.response.write(json.encode({'error': 'File not found'}));
        }
        await request.response.close();
      } else if (uri.path.startsWith('/uploaded/') && request.method == 'DELETE') {
        // Delete an uploaded file
        final filename = uri.pathSegments.last;
        if (_uploadedFiles.containsKey(filename)) {
          final path = _uploadedFiles[filename]!;
          final file = File(path);
          try {
            if (await file.exists()) {
              await file.delete();
            }
            _uploadedFiles.remove(filename);
            request.response.statusCode = HttpStatus.ok;
            request.response.write('Deleted');
          } catch (e) {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('Delete failed');
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('File not found');
        }
        await request.response.close();
      } else if (uri.path.startsWith('/download/')) {
        await _handleFileDownload(request);
      } else if (uri.path == '/health') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode({'status': 'ok'}));
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e) {
      debugPrint('[WebServer] Error handling request: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error');
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Serve the HTML web page
  void _serveWebPage(HttpRequest request) {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_getHtmlPage());
    request.response.close();
  }

  /// Handle WebSocket connections for real-time updates
  Future<void> _handleWebSocket(HttpRequest request) async {
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _connectedClients.add(socket);
      debugPrint('[WebServer] WebSocket client connected (${_connectedClients.length} total)');
      // Fire app-layer callback
      if (onClientConnected != null) {
        try {
          onClientConnected!.call('client_${DateTime.now().microsecondsSinceEpoch}');
        } catch (_) {}
      }
      
      // Send welcome message
      socket.add(json.encode({
        'type': 'connected',
        'deviceName': deviceName,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      
      socket.listen(
        (data) => _handleWebSocketMessage(socket, data),
        onDone: () {
          _connectedClients.remove(socket);
          debugPrint('[WebServer] WebSocket client disconnected');
          if (onClientDisconnected != null) {
            try {
              onClientDisconnected!.call('disconnected');
            } catch (_) {}
          }
        },
        onError: (error) {
          debugPrint('[WebServer] WebSocket error: $error');
          _connectedClients.remove(socket);
        },
      );
    } catch (e) {
      debugPrint('[WebServer] Failed to upgrade to WebSocket: $e');
    }
  }

  /// Handle WebSocket messages
  void _handleWebSocketMessage(WebSocket socket, dynamic data) {
    try {
      final message = json.decode(data as String);
      debugPrint('[WebServer] Received WebSocket message: ${message['type']}');
      
      // Handle different message types
      if (message['type'] == 'ping') {
        socket.add(json.encode({'type': 'pong'}));
      }
    } catch (e) {
      debugPrint('[WebServer] Error handling WebSocket message: $e');
    }
  }

  /// Handle file uploads from web browser
  Future<void> _handleFileUpload(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    try {
      final contentType = request.headers.contentType;
      if (contentType == null || contentType.mimeType != 'multipart/form-data') {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode({'error': 'Expected multipart/form-data', 'got': contentType?.toString()}));
        await request.response.close();
        return;
      }

      final boundary = contentType.parameters['boundary'];
      if (boundary == null || boundary.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode({'error': 'Missing multipart boundary'}));
        await request.response.close();
        return;
      }

      final transformer = MimeMultipartTransformer(boundary);
      final downloadsDir = await _getPreferredSaveDirectory();
      try {
        // Ensure directory exists
        await downloadsDir.create(recursive: true);
      } catch (_) {}
      int processedFiles = 0;

      await for (final part in transformer.bind(request)) {
        final contentDisposition = part.headers['content-disposition'];
        if (contentDisposition == null) {
          continue;
        }

        final filename = _extractFilename(contentDisposition);
        if (filename == null || filename.isEmpty) {
          continue;
        }

        processedFiles += 1;
  final savePath = await _uniqueFilePath(downloadsDir.path, filename);
        final sink = File(savePath).openWrite();
        int received = 0;

        final completer = Completer<void>();
        part.listen(
          (chunk) {
            received += chunk.length;
            sink.add(chunk);
            if (onFileUploadProgress != null) {
              // For multipart uploads, total size is unknown until complete
              // Report -1 as total to indicate indeterminate progress
              onFileUploadProgress!(filename, received, -1);
            }
          },
          onError: (e) async {
            await sink.close();
            if (!completer.isCompleted) completer.completeError(e);
          },
          onDone: () async {
            await sink.close();
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

        await completer.future;

        debugPrint('[WebServer] ✅ Received file: $filename ($received bytes) -> $savePath');

        if (onFileUploadComplete != null) {
          onFileUploadComplete!(filename, savePath);
        }
        _uploadedFiles[filename] = savePath;
        _broadcastToClients({
          'type': 'file_received',
          'filename': filename,
          'size': received,
          'path': savePath,
          'timestamp': DateTime.now().toIso8601String(),
        });
        if (onFileReceived != null) {
          // No need to send bytes payload; large. We skip for streaming path.
          // onFileReceived!(filename, await File(savePath).readAsBytes());
        }
      }

      if (processedFiles == 0) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode({'error': 'No file parts found'}));
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'success': true, 'message': 'File uploaded successfully'}));
      await request.response.close();
    } catch (e) {
      debugPrint('[WebServer] Error handling file upload: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'error': e.toString()}));
      await request.response.close();
    }
  }

  /// Extract filename from Content-Disposition header
  String? _extractFilename(String? contentDisposition) {
    if (contentDisposition == null) return null;
    
    final regex = RegExp(r'filename="?([^";\r\n]+)"?', caseSensitive: false);
    final match = regex.firstMatch(contentDisposition);
    return match?.group(1);
  }

  /// Generate a unique file path by appending (1), (2), ... if needed
  Future<String> _uniqueFilePath(String dir, String filename) async {
    final base = filename;
    final dot = base.lastIndexOf('.');
    final name = dot > 0 ? base.substring(0, dot) : base;
    final ext = dot > 0 ? base.substring(dot) : '';

    var attempt = 0;
    while (true) {
      final suffix = attempt == 0 ? '' : ' ($attempt)';
      final path = '$dir/$name$suffix$ext';
      final f = File(path);
      if (!await f.exists()) return path;
      attempt++;
    }
  }

  /// Choose a writable directory for saving uploaded files across platforms
  Future<Directory> _getPreferredSaveDirectory() async {
    // On Apple platforms, prefer Documents inside sandbox (safe without extra entitlements)
    if (Platform.isIOS || Platform.isMacOS) {
      return await getApplicationDocumentsDirectory();
    }
    // Else, try Downloads, then fallback to Documents
    final d = await getDownloadsDirectory();
    if (d != null) return d;
    return await getApplicationDocumentsDirectory();
  }

  /// Broadcast message to all connected WebSocket clients
  void _broadcastToClients(Map<String, dynamic> message) {
    final data = json.encode(message);
    for (var client in _connectedClients.toList()) {
      try {
        client.add(data);
      } catch (e) {
        debugPrint('[WebServer] Failed to send to client: $e');
        _connectedClients.remove(client);
      }
    }
  }

  /// Add a file to be available for download
  String addFileForDownload(String filePath, String filename) {
    final fileId = DateTime.now().millisecondsSinceEpoch.toString();
    _availableFiles[fileId] = _AvailableFile(
      id: fileId,
      path: filePath,
      filename: filename,
      addedAt: DateTime.now(),
    );

    // Notify web clients
    _broadcastToClients({
      'type': 'file_available',
      'fileId': fileId,
      'filename': filename,
      'size': File(filePath).lengthSync(),
    });

    debugPrint('[WebServer] File available for download: $filename (ID: $fileId)');
    return fileId;
  }

  /// Remove a file from available downloads
  void removeFileFromDownload(String fileId) {
    _availableFiles.remove(fileId);
    _broadcastToClients({
      'type': 'file_removed',
      'fileId': fileId,
    });
  }

  /// Get list of all files currently shared for download
  List<Map<String, dynamic>> getSharedFiles() {
    return _availableFiles.values.map((file) {
      try {
        final fileObj = File(file.path);
        return {
          'id': file.id,
          'filename': file.filename,
          'path': file.path,
          'size': fileObj.existsSync() ? fileObj.lengthSync() : 0,
          'sharedAt': file.addedAt.toIso8601String(),
        };
      } catch (e) {
        debugPrint('[WebServer] Error getting file info for ${file.filename}: $e');
        return null;
      }
    }).whereType<Map<String, dynamic>>().toList();
  }

  /// Serve list of available files as JSON
  void _serveFileList(HttpRequest request) {
    final files = _availableFiles.values.map((file) {
      try {
        return {
          'id': file.id,
          'filename': file.filename,
          'size': File(file.path).lengthSync(),
          'addedAt': file.addedAt.toIso8601String(),
        };
      } catch (e) {
        return null;
      }
    }).whereType<Map<String, dynamic>>().toList();

    request.response.headers.contentType = ContentType.json;
    request.response.write(json.encode({'files': files}));
    request.response.close();
  }

  /// Handle file download requests
  Future<void> _handleFileDownload(HttpRequest request) async {
    final fileId = request.uri.pathSegments.last;
    final file = _availableFiles[fileId];

    if (file == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(json.encode({'error': 'File not found'}));
      await request.response.close();
      return;
    }

    try {
      final ioFile = File(file.path);
      if (!await ioFile.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(json.encode({'error': 'File no longer exists'}));
        await request.response.close();
        return;
      }

      final fileLength = await ioFile.length();
      request.response.headers.contentType = ContentType.binary;
      request.response.headers.add('Content-Disposition', 'attachment; filename="${file.filename}"');
      request.response.headers.contentLength = fileLength;
      request.response.headers.add('Accept-Ranges', 'bytes');

      debugPrint('[WebServer] 📤 Starting file download: ${file.filename} (${_fmtBytes(fileLength)})');

      // Stream the file instead of loading it entirely into memory
      final stream = ioFile.openRead();
      int totalSent = 0;

      await stream.listen(
        (chunk) {
          request.response.add(chunk);
          totalSent += chunk.length;
        },
        onDone: () async {
          await request.response.close();
          debugPrint('[WebServer] ✅ File download completed: ${file.filename} (${_fmtBytes(totalSent)})');

          // Notify clients
          _broadcastToClients({
            'type': 'file_downloaded',
            'fileId': fileId,
            'filename': file.filename,
          });
        },
        onError: (error) async {
          debugPrint('[WebServer] Error streaming file: $error');
          try {
            await request.response.close();
          } catch (e) {
            debugPrint('[WebServer] Error closing response after stream error: $e');
          }
        },
        cancelOnError: true,
      );

    } catch (e) {
      debugPrint('[WebServer] Error serving file: $e');
      try {
        await request.response.close();
      } catch (closeError) {
        debugPrint('[WebServer] Error closing response: $closeError');
      }
    }
  }

  /// Get the shareable web link
  String getWebLink(String ipAddress) {
    // Wrap IPv6 addresses in brackets per URL spec
    if (ipAddress.contains(':')) {
      return 'http://[' + ipAddress + ']:$_port';
    }
    return 'http://$ipAddress:$_port';
  }

  /// HTML page served to browser clients
  String _getHtmlPage() {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Link Share - $deviceName</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        background: linear-gradient(180deg, #E9F5FA 0%, #FFFFFF 60%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 16px;
            color: #212121;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .container {
        background: #FFFFFF;
        border-radius: 16px;
        box-shadow: 0 6px 24px rgba(16, 99, 172, 0.08);
        padding: 24px;
        max-width: 420px;
        width: 100%;
        min-height: 550px;
        }
      h1 {
        color: #1063AC;
        margin-bottom: 16px;
        font-size: 18px;
        font-weight: 700;
        text-align: center;
        letter-spacing: 0.5px;
      }
        .subtitle {
        color: #4A73A0;
        margin-bottom: 12px;
        font-size: 13px;
        text-align: center;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
        }
      .divider {
        height: 1px;
        background: linear-gradient(90deg, rgba(16,99,172,0.10), rgba(16,99,172,0.05), rgba(16,99,172,0.10));
        margin: 8px 0 12px 0;
      }
      /* Mode toggle */
      .tabs {
        display: flex;
        justify-content: center;
        gap: 8px;
        margin: 8px auto 12px auto;
        padding: 4px;
      }
      .tab {
        padding: 8px 14px;
        background: transparent;
        border: 1px solid transparent;
        border-radius: 999px;
        cursor: pointer;
        font-size: 13px;
        font-weight: 600;
        transition: all 0.25s ease;
        color: #1063AC;
        width: 100px;
      }
      .tab:hover { background: #EAF6FD; }
      .tab.active {
        background: #F0F6F7;
        border: 3px solid #FFFFFF;
        box-shadow: 0 1px 4px #F0F6F7;
        color: #1063AC;
      }
      .tab-content { display: none; min-height: 350px; }
      .tab-content.active { display: block; }
        .upload-area {
            border: 2px dashed #B1B1B1;
            border-radius: 12px;
            padding: 32px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s ease;
            margin-bottom: 16px;
            background: #F0F6F7;
        }
        .upload-area:hover {
            border-color: #1063AC;
            background: #E2F6FB;
        }
        .upload-area.dragover {
            border-color: #1063AC;
            background: #E2F6FB;
            transform: scale(1.02);
        }
        .upload-icon {
            font-size: 48px;
            margin-bottom: 16px;
            color: #1063AC;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .upload-text {
            color: #4A4A4A;
            font-size: 16px;
            font-weight: 500;
            margin-bottom: 8px;
        }
        .upload-hint {
            color: #878787;
            font-size: 14px;
        }
        #fileInput {
            display: none;
        }
        .progress {
        margin-bottom: 16px;
            display: none;
        }
        .progress-bar {
            height: 8px;
            background: #E2F6FB;
            border-radius: 4px;
            overflow: hidden;
            margin-bottom: 8px;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #1063AC 0%, #16A5D5 100%);
            width: 0%;
            transition: width 0.3s ease;
            border-radius: 4px;
        }
        .progress-text {
            font-size: 14px;
            color: #4A4A4A;
            text-align: center;
            font-weight: 500;
        }
        .files-list {
        margin-top: 16px;
        }
        .file-item {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 14px 16px;
        background: #FFFFFF;
        border-radius: 12px;
        margin-bottom: 10px;
        border: 1px solid #EAF4FA;
        box-shadow: 0 2px 10px rgba(16,99,172,0.06);
        transition: all 0.2s ease;
        }
        .file-item:hover {
        transform: translateY(-1px);
        box-shadow: 0 4px 12px rgba(16,99,172,0.1);
        }
        .file-info {
            display: flex;
        align-items: center;
        gap: 12px;
        }
      .file-icon { font-size: 22px; color: #1063AC; }
        .file-name {
        font-weight: 600;
        color: #4A4A4A;
        font-size: 14px;
        }
        .file-size {
        font-size: 12px;
        color: #94A3B8;
        }
        .success-icon {
            color: #28C76F;
            font-size: 20px;
        }
      .empty-state { text-align: center; padding: 48px 20px; color: #878787; }
        .empty-state-icon {
            font-size: 48px;
            margin-bottom: 16px;
            color: #B1B1B1;
        }
        .download-btn {
            background: #28C76F;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.3s ease;
        }
        .download-btn:hover {
            background: #1F9D57;
            transform: translateY(-1px);
            box-shadow: 0 2px 8px rgba(40, 199, 111, 0.3);
        }
        .download-btn:disabled {
            background: #B1B1B1;
            cursor: not-allowed;
            transform: none;
        }

      /* Bottom callout */
      .bottom-banner {
        margin-top: 14px;
        background: #FFFFFF;
        border: 1px solid #EAF4FA;
        border-radius: 999px;
        padding: 8px 14px;
        display: flex;
        align-items: center;
        gap: 10px;
        box-shadow: 0 2px 10px rgba(16,99,172,0.06);
      }
      .bottom-icon {
        width: 28px; height: 28px; border-radius: 50%;
        background: linear-gradient(135deg, #B3E5FC, #81D4FA);
        display: grid; place-items: center; color: white;
      }
      .gradient-text {
        font-weight: 700; font-size: 13px;
        background: linear-gradient(90deg, #1063AC, #16A5D5);
        -webkit-background-clip: text; background-clip: text; color: transparent;
      }
    </style>
</head>
<body>
    <div class="container">
      <h1>CPFT</h1>
      <div class="divider"></div>
      <div class="subtitle"><span style="color:#28C76F; font-size:12px;">●</span> Connected to <strong>$deviceName</strong></div>

        <!-- Tabs for Send/Receive -->
      <div class="tabs">
        <button class="tab active" onclick="switchTab('send')">Send ↗</button>
        <button class="tab" onclick="switchTab('receive')">Receive ↙</button>
      </div>

        <!-- Send Tab (Upload to device) -->
        <div id="sendTab" class="tab-content active">
            <div class="upload-area" id="uploadArea">
                <div class="upload-icon"><svg width="48" height="48" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M7 16L12 21L17 16M12 3V21" stroke="#1063AC" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
                <div class="upload-text">Click to select files or drag & drop here</div>
                <div class="upload-hint">Send files to $deviceName</div>
            </div>

            <input type="file" id="fileInput" multiple>

            <div class="progress" id="progress">
                <div class="progress-bar">
                    <div class="progress-fill" id="progressFill"></div>
                </div>
                <div class="progress-text" id="progressText">Uploading...</div>
            </div>

            <div class="files-list" id="uploadedFiles"></div>

           
        </div>

        <!-- Receive Tab (Download from device) -->
        <div id="receiveTab" class="tab-content">
            <div id="availableFiles" class="files-list"></div>
            <div id="noFiles" class="empty-state">
                <div style="font-size: 48px; margin-bottom: 16px;"><svg width="48" height="48" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3 7V17C3 18.1046 3.89543 19 5 19H19C20.1046 19 21 18.1046 21 17V9C21 7.89543 20.1046 7 19 7H13L11 5H5C3.89543 5 3 5.89543 3 7Z" stroke="#B1B1B1" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
                <div>No files available to receive</div>
                <div style="font-size: 12px; color: #94a3b8; margin-top: 8px;">Files shared from $deviceName will appear here</div>
            </div>
        </div>
    </div>

    <script>
        let currentTab = 'send';
        const recentlyUploaded = new Set(); // suppress duplicate WS echoes
        const upKey = (name, size) => `\${name}|\${size}`;
        
        function switchTab(tab) {
            currentTab = tab;
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
            
            if (tab === 'send') {
                document.querySelectorAll('.tab')[0].classList.add('active');
            document.getElementById('sendTab').classList.add('active');
            document.getElementById('sendTab').style.display = 'block';
            document.getElementById('receiveTab').style.display = 'none';
            } else {
                document.querySelectorAll('.tab')[1].classList.add('active');
            document.getElementById('receiveTab').classList.add('active');
            document.getElementById('receiveTab').style.display = 'block';
            document.getElementById('sendTab').style.display = 'none';
                loadAvailableFiles();
            }
        }

        const uploadArea = document.getElementById('uploadArea');
        const fileInput = document.getElementById('fileInput');
        const progress = document.getElementById('progress');
        const progressFill = document.getElementById('progressFill');
        const progressText = document.getElementById('progressText');
        const uploadedFilesList = document.getElementById('uploadedFiles');
        const availableFilesList = document.getElementById('availableFiles');
        const noFilesDiv = document.getElementById('noFiles');

        // WebSocket connection for real-time updates
        let ws;
        try {
            ws = new WebSocket('ws://' + window.location.host + '/ws');
            ws.onmessage = (event) => {
                const data = JSON.parse(event.data);
                console.log('WebSocket message:', data);
                
                if (data.type === 'file_received') {
                  // If this browser initiated the upload, skip echo using name+size key
                  const k = upKey(data.filename, data.size ?? -1);
                  if (recentlyUploaded.has(k)) {
                    // clear the marker once seen
                    recentlyUploaded.delete(k);
                    return;
                  }
                  addUploadedFile(data.filename, data.size, true);
                } else if (data.type === 'file_available') {
                    if (currentTab === 'receive') {
                        loadAvailableFiles();
                    }
                } else if (data.type === 'file_removed') {
                    if (currentTab === 'receive') {
                        loadAvailableFiles();
                    }
                }
            };
        } catch (e) {
            console.log('WebSocket not available:', e);
        }

        uploadArea.addEventListener('click', () => fileInput.click());

        uploadArea.addEventListener('dragover', (e) => {
            e.preventDefault();
            uploadArea.classList.add('dragover');
        });

        uploadArea.addEventListener('dragleave', () => {
            uploadArea.classList.remove('dragover');
        });

        uploadArea.addEventListener('drop', (e) => {
            e.preventDefault();
            uploadArea.classList.remove('dragover');
            const files = e.dataTransfer.files;
            if (files.length > 0) {
                uploadFiles(files);
            }
        });

        fileInput.addEventListener('change', (e) => {
            const files = e.target.files;
            if (files.length > 0) {
                uploadFiles(files);
            }
        });

        async function uploadFiles(files) {
            for (let i = 0; i < files.length; i++) {
                try {
                    await uploadFile(files[i]);
                } catch (error) {
                    console.error('Failed to upload file:', files[i].name, error);
                    // Continue with next file even if one fails
                }
            }
            fileInput.value = '';
        }

        async function uploadFile(file) {
            const formData = new FormData();
            formData.append('file', file);

            progress.style.display = 'block';
            progressText.textContent = 'Preparing upload...';
            progressFill.style.width = '0%';

            return new Promise((resolve, reject) => {
                const xhr = new XMLHttpRequest();
                
                xhr.upload.addEventListener('progress', (e) => {
                    if (e.lengthComputable) {
                        const percentComplete = Math.round((e.loaded / e.total) * 100);
                        progressFill.style.width = percentComplete + '%';
                        progressText.textContent = \`Uploading \${file.name}... \${percentComplete}%\`;
                    }
                });
                
                xhr.addEventListener('load', () => {
                    if (xhr.status >= 200 && xhr.status < 300) {
                        progressFill.style.width = '100%';
                        progressText.textContent = 'Upload complete!';
                    addUploadedFile(file.name, file.size, true);
                    // mark as recently uploaded to avoid WS duplicate
                    const k = upKey(file.name, file.size ?? -1);
                    recentlyUploaded.add(k);
                    setTimeout(()=>recentlyUploaded.delete(k), 15000);
                        setTimeout(() => {
                            progress.style.display = 'none';
                            progressFill.style.width = '0%';
                        }, 2000);
                        resolve();
                    } else {
                        reject(new Error(\`Upload failed: \${xhr.status} \${xhr.statusText}\`));
                    }
                });
                
                xhr.addEventListener('error', () => {
                    reject(new Error('Network error during upload'));
                });
                
                xhr.addEventListener('abort', () => {
                    reject(new Error('Upload aborted'));
                });
                
                xhr.open('POST', '/upload');
                // pre-mark to cover race where WS arrives before load
                try { recentlyUploaded.add(upKey(file.name, file.size ?? -1)); } catch (e) {}
                xhr.send(formData);
            }).catch((error) => {
                progressText.textContent = 'Upload failed: ' + error.message;
                progressFill.style.width = '0%';
                setTimeout(() => {
                    progress.style.display = 'none';
                }, 3000);
                throw error;
            });
        }

        async function loadAvailableFiles() {
            try {
                const response = await fetch('/files');
                const data = await response.json();
                const files = data.files || [];
                
                if (files.length === 0) {
                    availableFilesList.style.display = 'none';
                    noFilesDiv.style.display = 'block';
                } else {
                    availableFilesList.style.display = 'block';
                    noFilesDiv.style.display = 'none';
                    availableFilesList.innerHTML = '';
                    
                    files.forEach(file => {
                      try {
                        const key = upKey(file.filename, file.size ?? -1);
                        if (recentlyUploaded.has(key)) return; // don't show our own uploads in Receive
                      } catch (e) {}
                      addAvailableFile(file.id, file.filename, file.size, file.addedAt);
                    });
                }
            } catch (error) {
                console.error('Error loading files:', error);
            }
        }

        function addAvailableFile(fileId, filename, size, addedAt) {
            const item = document.createElement('div');
            item.className = 'file-item';
          item.style.animation = 'fadeIn 0.3s ease';
          const time = formatTime(addedAt);
          item.innerHTML = `
            <div class="file-info" style="flex:1;">
              <div class="file-icon"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M14 2H6C4.9 2 4 2.9 4 4V20C4 21.1 4.9 22 6 22H18C19.1 22 20 21.1 20 20V8L14 2ZM18 20H6V4H13V9H18V20Z" fill="#1063AC"/></svg></div>
              <div>
                <div class="file-name" title="\${filename}">\${filename}</div>
                <div class="file-size">\${formatBytes(size)} · \${time}</div>
              </div>
            </div>
            <div style="display:flex;align-items:center;gap:8px;">
              <button class="download-btn" style="min-width:80px" onclick="downloadFile('\${fileId}', '\${filename}', this)"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M21 15V19C21 19.5304 20.7893 20.0391 20.4142 20.4142C20.0391 20.7893 19.5304 21 19 21H5C4.46957 21 3.96086 20.7893 3.58579 20.4142C3.21071 20.0391 3 19.5304 3 19V15" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M7 10L12 15L17 10" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 15V3" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></button>
            </div>
          `;
            availableFilesList.appendChild(item);
        }

        async function downloadFile(fileId, filename, button) {
            const originalHTML = button.innerHTML;
            
            try {
                // Show progress
                button.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" stroke="#FFFFFF" stroke-width="2"/><path d="M12 6V12L16 14" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
                button.disabled = true;
                
                const response = await fetch('/download/' + fileId);
                if (!response.ok) throw new Error('Download failed');
                
                // Get total size if available
                const contentLength = response.headers.get('content-length');
                const total = contentLength ? parseInt(contentLength, 10) : 0;
                
                button.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M21 15V19C21 19.5304 20.7893 20.0391 20.4142 20.4142C20.0391 20.7893 19.5304 21 19 21H5C4.46957 21 3.96086 20.7893 3.58579 20.4142C3.21071 20.0391 3 19.5304 3 19V15" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M7 10L12 15L17 10" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 15V3" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
                
                if (!total) {
                    // No content-length, download as blob
                    const blob = await response.blob();
                    const url = window.URL.createObjectURL(blob);
                    const a = document.createElement('a');
                    a.href = url;
                    a.download = filename;
                    document.body.appendChild(a);
                    a.click();
                    window.URL.revokeObjectURL(url);
                    document.body.removeChild(a);
                } else {
                    // Stream download with progress
                    const reader = response.body.getReader();
                    const chunks = [];
                    let received = 0;
                    
                    while (true) {
                        const { done, value } = await reader.read();
                        if (done) break;
                        
                        chunks.push(value);
                        received += value.length;
                        
                        // Update progress
                        const percent = Math.round((received / total) * 100);
                        button.innerHTML = \`<svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M21 15V19C21 19.5304 20.7893 20.0391 20.4142 20.4142C20.0391 20.7893 19.5304 21 19 21H5C4.46957 21 3.96086 20.7893 3.58579 20.4142C3.21071 20.0391 3 19.5304 3 19V15" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M7 10L12 15L17 10" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M12 15V3" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg> \${percent}%\`;
                    }
                    
                    // Create blob from chunks
                    const blob = new Blob(chunks);
                    const url = window.URL.createObjectURL(blob);
                    const a = document.createElement('a');
                    a.href = url;
                    a.download = filename;
                    document.body.appendChild(a);
                    a.click();
                    window.URL.revokeObjectURL(url);
                    document.body.removeChild(a);
                }
                
                button.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M22 11.08V12C21.9988 14.1564 21.3005 16.2547 20.0093 17.9818C18.7182 19.7089 16.9033 20.9725 14.8354 21.5839C12.7674 22.1953 10.5573 22.1219 8.53447 21.3746C6.51168 20.6273 4.78465 19.2461 3.61096 17.4371C2.43727 15.628 1.87979 13.4881 2.02168 11.3363C2.16356 9.18455 2.99721 7.13631 4.39828 5.49706C5.79935 3.85781 7.69279 2.71537 9.79619 2.24013C11.8996 1.7649 14.1003 1.98232 16.07 2.85999" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M22 4L12 14.01L9 11.01" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
                setTimeout(() => {
                    button.innerHTML = originalHTML;
                    button.disabled = false;
                }, 2000);
                
                console.log('Downloaded:', filename);
            } catch (error) {
                button.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M18 6L6 18M6 6L18 18" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
                button.disabled = false;
                setTimeout(() => {
                    button.innerHTML = originalHTML;
                }, 3000);
                alert('Download failed: ' + error.message);
            }
        }

        function addUploadedFile(filename, size, success) {
            const item = document.createElement('div');
            item.className = 'file-item';
            item.style.animation = 'fadeIn 0.3s ease';
            item.innerHTML = \`
                <div class="file-info">
                    <div class="file-icon"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M14 2H6C4.9 2 4 2.9 4 4V20C4 21.1 4.9 22 6 22H18C19.1 22 20 21.1 20 20V8L14 2ZM18 20H6V4H13V9H18V20Z" fill="#1063AC"/></svg></div>
                    <div>
                        <div class="file-name">\${filename}</div>
                        <div class="file-size">\${formatBytes(size)}</div>
                    </div>
                </div>
                <div style="display:flex;align-items:center;gap:8px;">
                   
                    <button class="download-btn" style="background:#FDF1F1;color:#EA5455;min-width:40px" onclick="deleteUploadedFile('\${filename}', this)" title="Delete file"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3 6H5H21" stroke="#EA5455" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M19 6V20C19 20.5304 18.7893 21.0391 18.4142 21.4142C18.0391 21.7893 17.5304 22 17 22H7C6.46957 22 5.96086 21.7893 5.58579 21.4142C5.21071 21.0391 5 20.5304 5 20V6M8 6V4C8 3.46957 8.21071 2.58579C8.96086 2.21071 9.46957 2 10 2H14C14.5304 2 15.0391 2.21071 15.4142 2.58579C15.7893 2.96086 16 3.46957 16 4V6" stroke="#EA5455" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M10 11V17" stroke="#EA5455" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M14 11V17" stroke="#EA5455" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></button>
                </div>
            \`;
            uploadedFilesList.insertBefore(item, uploadedFilesList.firstChild);
        }

        function formatBytes(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
        }
        function formatTime(iso) {
          try {
            const d = new Date(iso);
            let h = d.getHours();
            const m = d.getMinutes().toString().padStart(2,'0');
            const ampm = h >= 12 ? 'PM' : 'AM';
            h = h % 12; if (h === 0) h = 12;
            return h + ':' + m + ' ' + ampm;
          } catch { return ''; }
        }
        async function deleteFile(fileId, btn) {
          const original = btn.textContent;
          btn.textContent = '…';
          btn.disabled = true;
          try {
            const res = await fetch('/files/' + fileId, { method: 'DELETE' });
            if (!res.ok) throw new Error('Failed');
            btn.textContent = '✓';
            setTimeout(()=>{ loadAvailableFiles(); }, 300);
          } catch (e) {
            btn.textContent = 'Err';
            setTimeout(()=>{ btn.textContent = original; btn.disabled = false; }, 1200);
          }
        }
        async function deleteUploadedFile(filename, btn) {
          const original = btn.innerHTML;
          btn.innerHTML = '…';
          btn.disabled = true;
          try {
            const res = await fetch('/uploaded/' + encodeURIComponent(filename), { method: 'DELETE' });
            if (!res.ok) throw new Error('Failed');
            btn.closest('.file-item').remove();
          } catch (e) {
            btn.innerHTML = 'Err';
            setTimeout(()=>{ btn.innerHTML = original; btn.disabled = false; }, 1200);
          }
        }
      // Ensure initial view is Send tab
      document.addEventListener('DOMContentLoaded', ()=>switchTab('send'));
    </script>
</body>
</html>
''';
  }

  String _fmtBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
  }
}

/// Represents a file available for download by web clients
class _AvailableFile {
  final String id;
  final String path;
  final String filename;
  final DateTime addedAt;

  _AvailableFile({
    required this.id,
    required this.path,
    required this.filename,
    required this.addedAt,
  });
}
