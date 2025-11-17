import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import '../models/multicast_dto.dart';

/// HTTP server for device registration and info (LocalSend approach)
class HttpServerService {
  final int port;
  final String alias;
  final String fingerprint;
  final String deviceModel;
  final Function(String deviceName, String ipAddress, int port) onDeviceRegistered;

  HttpServer? _server;
  bool _isRunning = false;

  HttpServerService({
    required this.port,
    required this.alias,
    required this.fingerprint,
    required this.deviceModel,
    required this.onDeviceRegistered,
  });

  /// Start the HTTP server
  Future<void> start() async {
    if (_isRunning) {
      print('[HttpServer] Server already running');
      return;
    }

    int currentPort = port;
    const int maxPortAttempts = 10;

    for (int attempt = 0; attempt < maxPortAttempts; attempt++) {
      try {
        final handler = const Pipeline()
            .addMiddleware(logRequests())
            .addHandler(_handleRequest);

        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          currentPort,
        );

        _isRunning = true;
        print('[HttpServer] Server started on port $currentPort');
        return;
      } catch (e) {
        print('[HttpServer] Error starting server on port $currentPort: $e');
        
        if (e is SocketException && attempt < maxPortAttempts - 1) {
          // Try next port
          currentPort++;
          print('[HttpServer] Trying port $currentPort...');
          continue;
        }
        
        // Re-throw if we've exhausted all attempts or it's not a socket error
        rethrow;
      }
    }
  }

  /// Handle incoming HTTP requests
  Future<Response> _handleRequest(Request request) async {
    final path = request.url.path;
    print('[HttpServer] ${request.method} /$path from ${request.requestedUri.host}');

    try {
      if (path == 'info' && request.method == 'GET') {
        return _handleInfo(request);
      } else if (path == 'register' && request.method == 'POST') {
        return await _handleRegister(request);
      } else {
        return Response.notFound('Not found');
      }
    } catch (e) {
      print('[HttpServer] Error handling request: $e');
      return Response.internalServerError(body: 'Internal server error');
    }
  }

  /// Handle /info endpoint - returns device information
  Response _handleInfo(Request request) {
    // Check if it's self-discovery
    final senderFingerprint = request.url.queryParameters['fingerprint'];
    if (senderFingerprint == fingerprint) {
      return Response(412, body: jsonEncode({'message': 'Self-discovered'}));
    }

    final dto = InfoDto(
      alias: alias,
      fingerprint: fingerprint,
      port: port,
      deviceModel: deviceModel,
    );

    print('[HttpServer] Responding to /info request');
    return Response.ok(
      dto.toJsonString(),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Handle /register endpoint - called when another device announces
  Future<Response> _handleRegister(Request request) async {
    try {
      final body = await request.readAsString();
      final dto = RegisterDto.fromJsonString(body);

      // Check if it's self-discovery
      if (dto.fingerprint == fingerprint) {
        return Response(412, body: jsonEncode({'message': 'Self-discovered'}));
      }

      // Extract IP from request
      final clientIp = _extractClientIp(request);
      
      print('[HttpServer] Registered device: ${dto.alias} ($clientIp:${dto.port})');

      // Notify discovery listeners
      onDeviceRegistered(dto.alias, clientIp, dto.port);

      // Respond with our info
      final responseDto = InfoDto(
        alias: alias,
        fingerprint: fingerprint,
        port: port,
        deviceModel: deviceModel,
      );

      return Response.ok(
        responseDto.toJsonString(),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('[HttpServer] Error in /register: $e');
      return Response.badRequest(body: jsonEncode({'message': 'Bad request'}));
    }
  }

  /// Extract client IP from request
  String _extractClientIp(Request request) {
    // Try X-Forwarded-For header first
    final forwardedFor = request.headers['x-forwarded-for'];
    if (forwardedFor != null && forwardedFor.isNotEmpty) {
      return forwardedFor.split(',').first.trim();
    }

    // Fall back to connection info
    final connectionInfo = request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    return connectionInfo?.remoteAddress.address ?? 'unknown';
  }

  /// Get the actual port the server is running on
  int get actualPort => _server?.port ?? port;

  /// Check if server is running
  bool get isRunning => _isRunning;

  /// Stop the server
  Future<void> dispose() async {
    print('[HttpServer] Stopping server...');
    await _server?.close(force: true);
    _isRunning = false;
  }
}
