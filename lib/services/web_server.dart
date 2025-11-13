import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:mime/mime.dart';

/// Web server for browser-based file transfers
class WebServer {
  HttpServer? _server;
  int _port = 8080;
  final String deviceName;
  final List<WebSocket> _connectedClients = [];
  
  // Files available for download
  final Map<String, _AvailableFile> _availableFiles = {};
  
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

  bool get isRunning => _server != null;
  int get port => _port;
  
  /// Start the web server
  Future<bool> start({int port = 8080}) async {
    if (_server != null) {
      print('[WebServer] Already running');
      return true;
    }

    _port = port;
    
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      print('[WebServer] ✅ Started on port $_port');
      
      _server!.listen(_handleRequest);
      return true;
    } catch (e) {
      print('[WebServer] ❌ Failed to start: $e');
      return false;
    }
  }

  /// Stop the web server
  Future<void> stop() async {
    if (_server == null) return;
    
    // Close all WebSocket connections
    for (var ws in _connectedClients) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _connectedClients.clear();
    
    await _server?.close();
    _server = null;
    print('[WebServer] Stopped');
  }

  /// Handle HTTP requests
  void _handleRequest(HttpRequest request) async {
    final uri = request.uri;
    
    // CORS headers for browser requests
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
    
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    try {
      if (uri.path == '/' || uri.path == '/index.html') {
        _serveWebPage(request);
      } else if (uri.path == '/ws') {
        _handleWebSocket(request);
      } else if (uri.path == '/upload') {
        await _handleFileUpload(request);
      } else if (uri.path == '/files') {
        _serveFileList(request);
      } else if (uri.path.startsWith('/download/')) {
        await _handleFileDownload(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e) {
      print('[WebServer] Error handling request: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Internal Server Error');
      await request.response.close();
    }
  }

  /// Serve the HTML web page
  void _serveWebPage(HttpRequest request) {
    request.response.headers.contentType = ContentType.html;
    request.response.write(_getHtmlPage());
    request.response.close();
  }

  /// Handle WebSocket connections for real-time updates
  void _handleWebSocket(HttpRequest request) async {
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _connectedClients.add(socket);
      print('[WebServer] WebSocket client connected (${_connectedClients.length} total)');
      
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
          print('[WebServer] WebSocket client disconnected');
        },
        onError: (error) {
          print('[WebServer] WebSocket error: $error');
          _connectedClients.remove(socket);
        },
      );
    } catch (e) {
      print('[WebServer] Failed to upgrade to WebSocket: $e');
    }
  }

  /// Handle WebSocket messages
  void _handleWebSocketMessage(WebSocket socket, dynamic data) {
    try {
      final message = json.decode(data as String);
      print('[WebServer] Received WebSocket message: ${message['type']}');
      
      // Handle different message types
      if (message['type'] == 'ping') {
        socket.add(json.encode({'type': 'pong'}));
      }
    } catch (e) {
      print('[WebServer] Error handling WebSocket message: $e');
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
      if (contentType?.mimeType != 'multipart/form-data') {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(json.encode({'error': 'Expected multipart/form-data'}));
        await request.response.close();
        return;
      }

      final boundary = contentType!.parameters['boundary']!;
      final transformer = MimeMultipartTransformer(boundary);
      final parts = await transformer.bind(request).toList();

      for (var part in parts) {
        final contentDisposition = part.headers['content-disposition'];
        if (contentDisposition == null) continue;

        final filename = _extractFilename(contentDisposition);
        if (filename == null) continue;

        // Read file data with progress tracking
        final fileData = await part.toList();
        final bytes = Uint8List.fromList(fileData.expand((x) => x).toList());
        final totalSize = bytes.length;

        // Notify upload progress
        if (onFileUploadProgress != null) {
          onFileUploadProgress!(filename, totalSize, totalSize);
        }

        // Save to downloads directory
        final downloadsDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        final filePath = '${downloadsDir.path}/$filename';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        print('[WebServer] ✅ Received file: $filename (${bytes.length} bytes) -> $filePath');

        // Notify upload complete
        if (onFileUploadComplete != null) {
          onFileUploadComplete!(filename, filePath);
        }

        // Notify via WebSocket
        _broadcastToClients({
          'type': 'file_received',
          'filename': filename,
          'size': bytes.length,
          'path': filePath,
          'timestamp': DateTime.now().toIso8601String(),
        });

        // Call callback if set
        if (onFileReceived != null) {
          onFileReceived!(filename, bytes);
        }
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'success': true, 'message': 'File uploaded successfully'}));
      await request.response.close();
    } catch (e) {
      print('[WebServer] Error handling file upload: $e');
      request.response.statusCode = HttpStatus.internalServerError;
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

  /// Broadcast message to all connected WebSocket clients
  void _broadcastToClients(Map<String, dynamic> message) {
    final data = json.encode(message);
    for (var client in _connectedClients.toList()) {
      try {
        client.add(data);
      } catch (e) {
        print('[WebServer] Failed to send to client: $e');
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

    print('[WebServer] File available for download: $filename (ID: $fileId)');
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
        print('[WebServer] Error getting file info for ${file.filename}: $e');
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

      final bytes = await ioFile.readAsBytes();
      request.response.headers.contentType = ContentType.binary;
      request.response.headers.add('Content-Disposition', 'attachment; filename="${file.filename}"');
      request.response.headers.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();

      print('[WebServer] ✅ File downloaded: ${file.filename}');

      // Notify clients
      _broadcastToClients({
        'type': 'file_downloaded',
        'fileId': fileId,
        'filename': file.filename,
      });
    } catch (e) {
      print('[WebServer] Error serving file: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(json.encode({'error': e.toString()}));
      await request.response.close();
    }
  }

  /// Get the shareable web link
  String getWebLink(String ipAddress) {
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
    <title>CPFT - $deviceName</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            padding: 40px;
            max-width: 600px;
            width: 100%;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 14px;
        }
        .status {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 15px;
            background: #f0f9ff;
            border-radius: 10px;
            margin-bottom: 30px;
        }
        .status-dot {
            width: 10px;
            height: 10px;
            background: #22c55e;
            border-radius: 50%;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        .upload-area {
            border: 2px dashed #cbd5e1;
            border-radius: 12px;
            padding: 40px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s;
            margin-bottom: 20px;
        }
        .upload-area:hover {
            border-color: #667eea;
            background: #f8fafc;
        }
        .upload-area.dragover {
            border-color: #667eea;
            background: #f0f9ff;
        }
        .upload-icon {
            font-size: 48px;
            margin-bottom: 15px;
        }
        .upload-text {
            color: #64748b;
            font-size: 16px;
        }
        .upload-hint {
            color: #94a3b8;
            font-size: 12px;
            margin-top: 8px;
        }
        #fileInput {
            display: none;
        }
        .btn {
            background: #667eea;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 16px;
            cursor: pointer;
            transition: all 0.3s;
            width: 100%;
        }
        .btn:hover {
            background: #5568d3;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
        }
        .btn:disabled {
            background: #cbd5e1;
            cursor: not-allowed;
            transform: none;
        }
        .progress {
            margin-top: 20px;
            display: none;
        }
        .progress-bar {
            height: 8px;
            background: #e2e8f0;
            border-radius: 4px;
            overflow: hidden;
            margin-bottom: 8px;
        }
        .progress-fill {
            height: 100%;
            background: #667eea;
            width: 0%;
            transition: width 0.3s;
        }
        .progress-text {
            font-size: 14px;
            color: #64748b;
            text-align: center;
        }
        .files-list {
            margin-top: 30px;
        }
        .file-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 12px;
            background: #f8fafc;
            border-radius: 8px;
            margin-bottom: 8px;
        }
        .file-info {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .file-icon {
            font-size: 24px;
        }
        .file-name {
            font-weight: 500;
            color: #334155;
        }
        .file-size {
            font-size: 12px;
            color: #94a3b8;
        }
        .success-icon {
            color: #22c55e;
            font-size: 20px;
        }
        .tabs {
            display: flex;
            gap: 8px;
            margin-bottom: 20px;
        }
        .tab {
            flex: 1;
            padding: 12px;
            background: #f8fafc;
            border: 2px solid #e2e8f0;
            border-radius: 8px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            transition: all 0.3s;
        }
        .tab:hover {
            background: #f0f9ff;
            border-color: #667eea;
        }
        .tab.active {
            background: #667eea;
            color: white;
            border-color: #667eea;
        }
        .tab-content {
            display: none;
        }
        .tab-content.active {
            display: block;
        }
        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: #64748b;
        }
        .download-btn {
            background: #22c55e;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 6px;
            font-size: 14px;
            cursor: pointer;
            transition: all 0.3s;
        }
        .download-btn:hover {
            background: #16a34a;
            transform: translateY(-1px);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>📁 CPFT File Transfer</h1>
        <div class="subtitle">Connected to: <strong>$deviceName</strong></div>
        
        <div class="status">
            <div class="status-dot"></div>
            <span>Connected and ready to transfer files</span>
        </div>

        <!-- Tabs for Send/Receive -->
        <div class="tabs">
            <button class="tab active" onclick="switchTab('send')">� Send to $deviceName</button>
            <button class="tab" onclick="switchTab('receive')">� Receive from $deviceName</button>
        </div>

        <!-- Send Tab (Upload to device) -->
        <div id="sendTab" class="tab-content active">
            <div class="upload-area" id="uploadArea">
                <div class="upload-icon">📤</div>
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
                <div style="font-size: 48px; margin-bottom: 16px;">📂</div>
                <div>No files available to receive</div>
                <div style="font-size: 12px; color: #94a3b8; margin-top: 8px;">Files shared from $deviceName will appear here</div>
            </div>
        </div>
    </div>

    <script>
        let currentTab = 'send';
        
        function switchTab(tab) {
            currentTab = tab;
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
            
            if (tab === 'send') {
                document.querySelectorAll('.tab')[0].classList.add('active');
                document.getElementById('sendTab').classList.add('active');
            } else {
                document.querySelectorAll('.tab')[1].classList.add('active');
                document.getElementById('receiveTab').classList.add('active');
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
                await uploadFile(files[i]);
            }
        }

        async function uploadFile(file) {
            const formData = new FormData();
            formData.append('file', file);

            progress.style.display = 'block';
            progressText.textContent = 'Uploading ' + file.name + '...';

            try {
                const response = await fetch('/upload', {
                    method: 'POST',
                    body: formData
                });

                if (response.ok) {
                    progressFill.style.width = '100%';
                    progressText.textContent = 'Upload complete!';
                    addUploadedFile(file.name, file.size, true);
                    setTimeout(() => {
                        progress.style.display = 'none';
                        progressFill.style.width = '0%';
                    }, 2000);
                } else {
                    throw new Error('Upload failed');
                }
            } catch (error) {
                progressText.textContent = 'Upload failed: ' + error.message;
                progressFill.style.width = '0%';
            }

            fileInput.value = '';
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
                        addAvailableFile(file.id, file.filename, file.size);
                    });
                }
            } catch (error) {
                console.error('Error loading files:', error);
            }
        }

        function addAvailableFile(fileId, filename, size) {
            const item = document.createElement('div');
            item.className = 'file-item';
            item.innerHTML = \`
                <div class="file-info">
                    <div class="file-icon">📄</div>
                    <div>
                        <div class="file-name">\${filename}</div>
                        <div class="file-size">\${formatBytes(size)}</div>
                    </div>
                </div>
                <button class="download-btn" onclick="downloadFile('\${fileId}', '\${filename}')">
                    ⬇️ Download
                </button>
            \`;
            availableFilesList.appendChild(item);
        }

        async function downloadFile(fileId, filename) {
            try {
                const response = await fetch('/download/' + fileId);
                if (!response.ok) throw new Error('Download failed');
                
                const blob = await response.blob();
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = filename;
                document.body.appendChild(a);
                a.click();
                window.URL.revokeObjectURL(url);
                document.body.removeChild(a);
                
                console.log('Downloaded:', filename);
            } catch (error) {
                alert('Download failed: ' + error.message);
            }
        }

        function addUploadedFile(filename, size, success) {
            const item = document.createElement('div');
            item.className = 'file-item';
            item.innerHTML = \`
                <div class="file-info">
                    <div class="file-icon">📄</div>
                    <div>
                        <div class="file-name">\${filename}</div>
                        <div class="file-size">\${formatBytes(size)}</div>
                    </div>
                </div>
                \${success ? '<div class="success-icon">✅</div>' : ''}
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
    </script>
</body>
</html>
''';
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
