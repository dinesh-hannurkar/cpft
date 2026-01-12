import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'netcat_receiver.dart';
import 'netcat_sender.dart';

class NetcatService {
  // Singleton
  static final NetcatService _instance = NetcatService._internal();
  factory NetcatService() => _instance;
  NetcatService._internal();

  NetcatReceiver? _receiver;
  final StreamController<Map<String, dynamic>> _incomingProgressController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _outgoingProgressController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get incomingProgress =>
      _incomingProgressController.stream;
  Stream<Map<String, dynamic>> get outgoingProgress =>
      _outgoingProgressController.stream;

  final StreamController<Map<String, dynamic>> _completionController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get completion => _completionController.stream;

  // Configuration
  static const int dataPort = 61235; // Different port from DPFTP

  Future<void> startReceiver({required String saveDirectory}) async {
    debugPrint('[Netcat] Starting Receiver Service on port $dataPort');
    _receiver = NetcatReceiver(
      port: dataPort,
      saveDirectory: saveDirectory,
    );
    _receiver!.progress.listen((progressData) {
      _incomingProgressController.add(progressData);
    });
    _receiver!.completion.listen((completionData) {
      _completionController.add(completionData);
    });
    await _receiver!.start();
  }

  void acceptFile(String transferId, String filePath, int fileSize) {
    _receiver?.acceptFile(transferId, filePath, fileSize);
  }

  Future<void> sendFile({
    required String ip,
    required File file,
    required String transferId,
  }) async {
    debugPrint('[Netcat] Sending ${file.path} to $ip:$dataPort');
    final filename = file.path.split('/').last;
    final fileSize = await file.length();
    final sender = NetcatSender(
      ip: ip,
      port: dataPort,
      file: file,
      filename: filename,
      fileSize: fileSize,
      transferId: transferId,
    );

    sender.progress.listen((progress) {
      _outgoingProgressController.add({
        'transferId': transferId,
        'totalSize': fileSize,
        'progress': progress,
      });
    });

    await sender.start();
  }

  void stop() {
    _receiver?.stop();
    _receiver = null;
    _incomingProgressController.close();
    _outgoingProgressController.close();
    _completionController.close();
  }
}
