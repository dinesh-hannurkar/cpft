import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'quic_progress.dart';
import 'quic_transport.dart';
import 'quic_sender.dart';
import 'quic_receiver.dart';

/// Service facade for QUIC-based file transfer.
/// This implementation is completely separate from DpftpService.
class QuicService {
  // Singleton
  static final QuicService _instance = QuicService._internal();
  factory QuicService() => _instance;
  QuicService._internal();

  final _progressController = StreamController<QuicProgress>.broadcast();

  /// Stream of file transfer progress events
  Stream<QuicProgress> get progress => _progressController.stream;

  // QUIC Port (Different from DPFTP to avoid conflict)
  static const int quicPort = 61235;

  bool _isRunning = false;

  QuicTransport? _transport;
  QuicReceiver? _receiver;
  // Keep track of active senders if we want to cancel them
  final List<QuicSender> _activeSenders = [];

  /// Start listening for incoming QUIC connections
  Future<void> startReceiver({required String saveDirectory}) async {
    if (_isRunning) return;
    _isRunning = true;

    debugPrint('[QUIC] Starting Receiver Service on port $quicPort');

    _transport = QuicTransportDart(localPort: quicPort);
    await _transport!.start();

    _receiver = QuicReceiver(
      transport: _transport!,
      saveDirectory: saveDirectory,
      onProgress: (p) => _progressController.add(p),
    );
    _receiver!.start();
  }

  /// Send a file using QUIC protocol
  Future<void> sendFile({
    required String ip,
    required File file,
    required String transferId,
  }) async {
    debugPrint('[QUIC] Sending file $transferId to $ip');

    // Note: If we are only a client, we might need ephemeral port binding.
    // But for P2P, we often bind to the same port or rely on QuicTransport
    // to handle it.
    // If startReceiver() was called, _transport is already bound.
    // If not, we should bind it.
    if (_transport == null) {
      // Bind to ephemeral for client-only, or fixed if we want symmetry?
      // Let's bind to 0 (any ephemeral) if not acting as receiver
      _transport = QuicTransportDart(localPort: 0);
      await _transport!.start();
    }

    final sender = QuicSender(
      transport: _transport!,
      ip: ip,
      port: quicPort, // Target port
      file: file,
      transferId: transferId,
      onProgress: (p) => _progressController.add(p),
    );

    _activeSenders.add(sender);
    try {
      await sender.start();
    } finally {
      _activeSenders.remove(sender);
      // Note: Don't close transport if we are also a receiver
    }
  }

  void stop() {
    _isRunning = false;
    _receiver?.stop();
    _receiver = null;
    _transport?.stop();
    _transport = null;
    _activeSenders.clear();
  }

  void dispose() {
    _progressController.close();
    stop();
  }
}
