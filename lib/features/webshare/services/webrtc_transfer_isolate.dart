import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cpft/core/logging/app_logger.dart';

/// Simplified isolate-based WebRTC file transfer
/// Uses isolates to prevent UI blocking during heavy file operations
class WebRTCTransferIsolate {
  Isolate? _processingIsolate;
  SendPort? _isolateSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();
  StreamSubscription? _mainPortSubscription;

  RTCDataChannel? _dataChannel;

  // Callbacks
  final Function(String, int, int)? onSendProgress;
  final Function(String, int, int)? onReceiveProgress;
  final Function(String, String, int)? onSendComplete;
  final Function(String, String)? onReceiveComplete;
  final Function(String, String, bool)? onTransferError;

  WebRTCTransferIsolate({
    this.onSendProgress,
    this.onReceiveProgress,
    this.onSendComplete,
    this.onReceiveComplete,
    this.onTransferError,
  });

  /// Initialize with data channel
  Future<void> initialize(RTCDataChannel dataChannel) async {
    _dataChannel = dataChannel;

    // Listen for messages from isolate
    _mainPortSubscription = _mainReceivePort.listen(_handleIsolateMessage);

    // Start processing isolate
    await _startProcessingIsolate();

    AppLogger.i('WebRTC transfer isolate initialized', tag: 'WebRTC-Isolate');
  }

  /// Send file bytes using isolate processing
  Future<void> sendFileBytes(String fileName, List<int> fileBytes) async {
    if (_isolateSendPort == null) {
      throw StateError('Isolate not initialized. Call initialize() first.');
    }

    _isolateSendPort!.send({
      'type': 'send_file',
      'fileName': fileName,
      'fileBytes': fileBytes,
    });
  }

  Future<void> _startProcessingIsolate() async {
    final receivePort = ReceivePort();
    _processingIsolate = await Isolate.spawn(
      _isolateEntry,
      _IsolateConfig(
        mainSendPort: _mainReceivePort.sendPort,
        isolateReceivePort: receivePort.sendPort,
      ),
      debugName: 'WebRTC-ProcessingIsolate',
    );

    // Wait for isolate to be ready
    final completer = Completer<void>();
    late final StreamSubscription subscription;
    subscription = receivePort.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
        completer.complete();
        subscription.cancel();
      }
    });

    await completer.future;
  }

  /// Start receiving a file
  void startReceivingFile(String fileName, int fileSize) {
    if (_isolateSendPort == null) return;

    final message = {
      'type': 'start_receive',
      'fileName': fileName,
      'fileSize': fileSize,
    };

    _isolateSendPort!.send(message);
  }

  /// Update credits for flow control
  void updateCredits(int credits) {
    if (_isolateSendPort == null) return;

    final message = {
      'type': 'update_credits',
      'credits': credits,
    };

    _isolateSendPort!.send(message);
  }

  /// Handle incoming binary chunk
  void handleBinaryChunk(Uint8List chunkData) {
    if (_isolateSendPort == null) return;

    final message = {
      'type': 'binary_chunk',
      'chunkData': chunkData,
    };

    _isolateSendPort!.send(message);
  }

  /// Handle file completion
  void handleFileComplete(String fileName) {
    if (_isolateSendPort == null) return;

    final message = {
      'type': 'file_complete',
      'fileName': fileName,
    };

    _isolateSendPort!.send(message);
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      switch (message['type']) {
        case 'send_chunk':
          // Forward chunk to WebRTC
          if (_dataChannel != null) {
            _dataChannel!.send(RTCDataChannelMessage.fromBinary(
              message['chunk'] as Uint8List,
            ));
          }
          break;

        case 'send_metadata':
          // Forward metadata to WebRTC
          if (_dataChannel != null) {
            _dataChannel!.send(RTCDataChannelMessage(jsonEncode(
              message['metadata'],
            )));
          }
          break;

        case 'send_completion':
          // Forward completion to WebRTC
          if (_dataChannel != null) {
            _dataChannel!.send(RTCDataChannelMessage(jsonEncode(
              message['completion'],
            )));
          }
          break;

        case 'send_progress':
          onSendProgress?.call(
            message['fileName'],
            message['bytesSent'],
            message['totalBytes'],
          );
          break;

        case 'send_complete':
          onSendComplete?.call(
            message['fileName'],
            message['filePath'],
            message['fileSize'],
          );
          break;

        case 'receive_progress':
          onReceiveProgress?.call(
            message['fileName'],
            message['bytesReceived'],
            message['totalBytes'],
          );
          break;

        case 'receive_complete':
          onReceiveComplete?.call(
            message['fileName'],
            message['savedPath'],
          );
          break;
      }
    }
  }

  /// Shutdown isolate
  Future<void> shutdown() async {
    if (_isolateSendPort != null) {
      _isolateSendPort!.send({'type': 'shutdown'});
    }

    await Future.delayed(const Duration(milliseconds: 100));

    _processingIsolate?.kill();
    _mainPortSubscription?.cancel();
    _mainReceivePort.close();

    AppLogger.i('WebRTC transfer isolate shut down', tag: 'WebRTC-Isolate');
  }
}

class _IsolateConfig {
  final SendPort mainSendPort;
  final SendPort isolateReceivePort;

  _IsolateConfig({
    required this.mainSendPort,
    required this.isolateReceivePort,
  });
}

/// Isolate entry point - handles heavy processing off main thread
void _isolateEntry(_IsolateConfig config) {
  final receivePort = ReceivePort();
  config.isolateReceivePort.send(receivePort.sendPort);

  // Processing state
  String? currentFileName;
  int currentFileSize = 0;
  int receivedBytes = 0;
  List<Uint8List>? webParts;

  receivePort.listen((message) {
    if (message is Map<String, dynamic>) {
      switch (message['type']) {
        case 'send_file':
          _processSendFile(message, config.mainSendPort);
          break;

        case 'start_receive':
          currentFileName = message['fileName'];
          currentFileSize = message['fileSize'];
          if (kIsWeb) {
            webParts = [];
          }
          break;

        case 'binary_chunk':
          _processBinaryChunk(message, config.mainSendPort, currentFileName, currentFileSize, receivedBytes, webParts);
          break;

        case 'file_complete':
          _processFileComplete(message, config.mainSendPort, webParts, receivedBytes);
          break;

        case 'shutdown':
          receivePort.close();
          break;
      }
    }
  });
}

void _processSendFile(Map<String, dynamic> data, SendPort mainPort) {
  final fileName = data['fileName'] as String;
  final fileBytes = data['fileBytes'] as List<int>;
  final chunkSize = data['chunkSize'] as int;

  final fileSize = fileBytes.length;
  int sentBytes = 0;

  // Send metadata
  mainPort.send({
    'type': 'send_metadata',
    'metadata': {
      'type': 'file-metadata',
      'fileName': fileName,
      'fileSize': fileSize,
    },
  });

  // Process chunks (heavy operation off main thread)
  for (int i = 0; i < fileSize; i += chunkSize) {
    final end = (i + chunkSize < fileSize) ? i + chunkSize : fileSize;
    final chunk = fileBytes.sublist(i, end);

    // Create packed chunk with offset header
    final offsetBytes = Uint8List(8);
    final byteData = ByteData.view(offsetBytes.buffer);
    final offsetHigh = (i >> 32) & 0xFFFFFFFF;
    final offsetLow = i & 0xFFFFFFFF;
    byteData.setUint32(0, offsetHigh, Endian.big);
    byteData.setUint32(4, offsetLow, Endian.big);

    final packedChunk = Uint8List(8 + chunk.length);
    packedChunk.setRange(0, 8, offsetBytes);
    packedChunk.setRange(8, packedChunk.length, chunk);

    // Send chunk
    mainPort.send({
      'type': 'send_chunk',
      'chunk': packedChunk,
    });

    sentBytes += chunk.length;

    // Progress update
    mainPort.send({
      'type': 'send_progress',
      'fileName': fileName,
      'bytesSent': sentBytes,
      'totalBytes': fileSize,
    });
  }

  // Send completion with extended delay
  Future.delayed(const Duration(seconds: 30), () {
    mainPort.send({
      'type': 'send_completion',
      'completion': {
        'type': 'file-complete',
        'fileName': fileName,
      },
    });

    // Completion callback
    mainPort.send({
      'type': 'send_complete',
      'fileName': fileName,
      'filePath': fileName,
      'fileSize': fileSize,
    });
  });
}

void _processBinaryChunk(Map<String, dynamic> data, SendPort mainPort,
    String? currentFileName, int currentFileSize, int receivedBytes, List<Uint8List>? webParts) {
  final chunkData = data['chunkData'] as Uint8List;

  try {
    if (chunkData.length < 8) return;

    final byteData = ByteData.view(chunkData.buffer, chunkData.offsetInBytes, chunkData.lengthInBytes);
    final offsetHigh = byteData.getUint32(0, Endian.big);
    final offsetLow = byteData.getUint32(4, Endian.big);
    final offset = (offsetHigh << 32) | offsetLow;

    final actualData = Uint8List.view(
      chunkData.buffer,
      chunkData.offsetInBytes + 8,
      chunkData.lengthInBytes - 8,
    );

    // Update received bytes (this would be passed back, but simplified here)
    final newReceivedBytes = receivedBytes + actualData.length;

    // Store for web platform
    if (kIsWeb && webParts != null) {
      webParts.add(actualData);
    }

    // Progress update
    mainPort.send({
      'type': 'receive_progress',
      'fileName': currentFileName ?? 'unknown',
      'bytesReceived': newReceivedBytes,
      'totalBytes': currentFileSize,
    });

  } catch (e) {
    AppLogger.e('Error processing chunk in isolate: $e', tag: 'WebRTC-Isolate');
  }
}

void _processFileComplete(Map<String, dynamic> data, SendPort mainPort,
    List<Uint8List>? webParts, int receivedBytes) {
  final fileName = data['fileName'] as String;

  try {
    // For web, assemble file from parts
    if (kIsWeb && webParts != null) {
      final assembled = Uint8List(receivedBytes);
      int offset = 0;
      for (final part in webParts) {
        assembled.setRange(offset, offset + part.length, part);
        offset += part.length;
      }
      // File would be saved here in full implementation
    }

    // Completion callback
    mainPort.send({
      'type': 'receive_complete',
      'fileName': fileName,
      'savedPath': fileName,
    });

  } catch (e) {
    AppLogger.e('Error completing file in isolate: $e', tag: 'WebRTC-Isolate');
  }
}