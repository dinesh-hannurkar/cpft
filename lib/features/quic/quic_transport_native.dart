import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'quic_transport.dart';

/// Native Implementation of QuicTransport using Platform Channels.
/// Delegates actual QUIC operations to Cronet (Android) or Network.framework (iOS).
class QuicTransportNative implements QuicTransport {
  static const MethodChannel _channel = MethodChannel('com.cpft.quic');

  final int localPort;
  final _dataStreamController = StreamController<QuicStreamEvent>.broadcast();

  QuicTransportNative({required this.localPort});

  @override
  Stream<QuicStreamEvent> get dataStream => _dataStreamController.stream;

  @override
  Future<void> start() async {
    debugPrint('[QUIC-Native] Starting on port $localPort');
    // Initialize Native Transport
    // We pass the MethodChannel handler to receive callbacks
    _channel.setMethodCallHandler(_handleMethodCall);

    try {
      await _channel.invokeMethod('start', {'port': localPort});
    } on PlatformException catch (e) {
      debugPrint('[QUIC-Native] Failed to start: ${e.message}');
      rethrow;
    }
  }

  @override
  Future<void> sendStreamData(
    String ip,
    int port,
    int streamId,
    Uint8List data,
  ) async {
    try {
      // Native optimization: We can pass the raw bytes directly.
      // The native side handles framing, flow control, and reliability.
      await _channel.invokeMethod('sendStreamData', {
        'ip': ip,
        'port': port,
        'streamId': streamId,
        'data': data,
      });
    } on PlatformException catch (e) {
      debugPrint('[QUIC-Native] Send failed: ${e.message}');
    }
  }

  /// Handle incoming calls from Native (Data received, Errors, etc.)
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDataReceived':
        _handleIncomingData(call.arguments);
        break;
      case 'onError':
        debugPrint('[QUIC-Native] Error callback: ${call.arguments}');
        break;
      default:
        debugPrint('[QUIC-Native] Unknown method: ${call.method}');
    }
  }

  void _handleIncomingData(dynamic arguments) {
    if (arguments is Map) {
      final streamId = arguments['streamId'] as int;
      final data = arguments['data'] as Uint8List;
      final remoteIp = arguments['remoteIp'] as String;
      final offset = (arguments['offset'] as num)
          .toInt(); // Native might send long/int

      _dataStreamController.add(
        QuicStreamEvent(streamId, data, remoteIp, offset),
      );
    }
  }

  @override
  bool sendRaw(InternetAddress address, int port, Uint8List data) {
    // Native implementations don't usually expose raw packet sending
    // unless strictly necessary. If we need "Datagram" support inside QUIC,
    // we would map it to DATAGRAM frames.
    // For now, this might be unused if we purely use sendStreamData.
    debugPrint(
      '[QUIC-Native] sendRaw not fully implemented/needed for Native QUIC',
    );
    return true; // Assume success for now
  }

  @override
  void closeConnection(InternetAddress address, int port) {
    _channel.invokeMethod('closeConnection', {
      'ip': address.address,
      'port': port,
    });
  }

  @override
  void stop() {
    _channel.invokeMethod('stop');
    _channel.setMethodCallHandler(null);
  }

  @override
  Object? getConnectionState(InternetAddress address, int port) {
    // Native handles reliability constraints internally.
    // No exposed state needed for the Dart side to "wait" on.
    return null;
  }
}
