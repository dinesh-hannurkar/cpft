import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dpftp_receiver.dart';
import 'dart:async';
import 'dpftp_types.dart';
import 'dpftp_sender.dart';

/// Service facade for DPFTP (Dart Parallel File Transfer Protocol).
/// Replaces ConnectionService for file transfer responsibilities.
class DpftpService {
  // Singleton
  static final DpftpService _instance = DpftpService._internal();
  factory DpftpService() => _instance;
  DpftpService._internal();

  DpftpReceiver? _receiver;
  DpftpSender? _sender;
  final _progressController = StreamController<DpftpProgress>.broadcast();

  // Configuration
  static const int dataPort =
      61234; // Avoid AirPlay (5000) and other common ports

  Stream<DpftpProgress> get progress => _progressController.stream;

  /// Start listening for incoming files
  Future<void> startReceiver({required String saveDirectory}) async {
    stop(); // Ensure clean slate
    debugPrint('[DPFTP] Starting Receiver Service on port $dataPort');
    _receiver = DpftpReceiver(
      port: dataPort,
      saveDirectory: saveDirectory,
      onProgress: (p) => _progressController.add(p),
    );
    await _receiver!.start();
  }

  /// Restart receiver with a new save directory (e.g., when user changes download location)
  Future<void> restartReceiver({required String saveDirectory}) async {
    debugPrint(
      '[DPFTP] Restarting receiver with new save directory: $saveDirectory',
    );
    await startReceiver(saveDirectory: saveDirectory);
  }

  // Queue for handling multiple files sequentially
  final List<_TransferRequest> _transferQueue = [];
  bool _isProcessing = false;

  /// Send a file to a remote device
  Future<void> sendFile({
    required String ip,
    required File file,
    required String transferId,
    int? parallelConnections,
    int? chunkSize,
    int? maxInFlightBytes,
  }) async {
    // Add to queue
    _transferQueue.add(
      _TransferRequest(
        ip: ip,
        file: file,
        transferId: transferId,
        parallelConnections: parallelConnections,
        chunkSize: chunkSize,
        maxInFlightBytes: maxInFlightBytes,
      ),
    );

    // Process queue if not running
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_transferQueue.isNotEmpty) {
      final req = _transferQueue.removeAt(0);
      debugPrint(
        '[DPFTP] Processing queue item: ${req.transferId} (${req.file.path})',
      );

      final completer = Completer<void>();

      try {
        _sender?.stop(); // Ensure previous CLEANUP
        _sender = DpftpSender(
          ip: req.ip,
          port: dataPort,
          file: req.file,
          transferId: req.transferId,
          parallelConnections: req.parallelConnections ?? 4,
          chunkSize: req.chunkSize,
          maxInFlightBytes: req.maxInFlightBytes,
          onProgress: (p) {
            _progressController.add(p);

            // Completion Signal
            if (p.isComplete) {
              if (!completer.isCompleted) completer.complete();
            }
            // Error Signal (Need to handle if sender emits it)
            if (p.error != null) {
              if (!completer.isCompleted) completer.completeError(p.error!);
            }
          },
        );

        await _sender!.start();

        // Wait for transfer to actually finish (or error)
        try {
          // Add a safety timeout of 2 minutes? Or just wait?
          // For now, simple wait with 5 min timeout just in case.
          await completer.future.timeout(const Duration(minutes: 5));
        } catch (e) {
          debugPrint(
            '[DPFTP] Transfer ${req.transferId} timed out or failed: $e',
          );
          // Emit error progress so UI knows?
          if (!_progressController.isClosed) {
            _progressController.add(
              DpftpProgress(
                transferId: req.transferId,
                bytesTransferred: 0,
                totalBytes: 0,
                isOutgoing: true,
                error: 'Transfer timed out or failed: $e',
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('[DPFTP] Failed to start sender for ${req.transferId}: $e');
      } finally {
        // Cleanup this transfer explicitly
        // This closes socket, making it ready for next fresh connection
        _sender?.stop();
        _sender = null;

        // Small delay to allow receiver to reset?
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    _isProcessing = false;
  }

  void stop() {
    _receiver?.stop();
    _receiver = null;
    _sender?.stop();
    _sender = null;
    _transferQueue.clear();
    _isProcessing = false;
  }
}

class _TransferRequest {
  final String ip;
  final File file;
  final String transferId;
  final int? parallelConnections;
  final int? chunkSize;
  final int? maxInFlightBytes;

  _TransferRequest({
    required this.ip,
    required this.file,
    required this.transferId,
    this.parallelConnections,
    this.chunkSize,
    this.maxInFlightBytes,
  });
}
