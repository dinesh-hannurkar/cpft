import 'dart:convert';
import 'dart:io'
    if (dart.library.html) 'package:cpft/features/webshare/services/io_stub.dart';
import 'package:flutter/foundation.dart';
import 'package:cpft/core/logging/app_logger.dart';

class LocalWebSocketSignalingServer {
  static final LocalWebSocketSignalingServer _instance =
      LocalWebSocketSignalingServer._internal();
  factory LocalWebSocketSignalingServer() => _instance;
  LocalWebSocketSignalingServer._internal();
  HttpServer? _server;
  final Map<String, Map<String, WebSocket>> _rooms =
      {}; // roomId -> peerId->socket
  final Map<String, String> _roomHosts = {}; // roomId -> hostIP:port
  bool get isRunning => _server != null;
  int? _port;
  String? _hostIp;

  int? get port => _port;
  String? get hostIp => _hostIp;

  Future<void> start({int port = 8080}) async {
    if (kIsWeb) {
      AppLogger.e(
        'Local WebSocket signaling server cannot run on web platform',
        tag: 'LocalWS',
      );
      throw UnsupportedError(
        'Local signaling server is not supported on web. Use remote signaling instead.',
      );
    }

    if (isRunning) return;

    _hostIp = await _detectLocalIp();

    // Try to bind to the requested port, with automatic fallback
    HttpServer? server;
    int attemptedPort = port;
    const maxAttempts = 10;

    for (int i = 0; i < maxAttempts; i++) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, attemptedPort);
        _server = server;
        _port = attemptedPort;
        AppLogger.i(
          'Local WS signaling server listening on port $attemptedPort',
          tag: 'LocalWS',
        );
        if (attemptedPort != port) {
          AppLogger.i(
            'Note: Port $port was in use, using $attemptedPort instead',
            tag: 'LocalWS',
          );
        }
        break;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 98 || e.osError?.errorCode == 48) {
          // Address already in use (Linux: 98, macOS: 48)
          AppLogger.w(
            'Port $attemptedPort already in use, trying ${attemptedPort + 1}',
            tag: 'LocalWS',
          );
          attemptedPort++;
        } else {
          rethrow;
        }
      }
    }

    if (_server == null) {
      throw Exception(
        'Failed to start server after trying ports $port-${port + maxAttempts - 1}',
      );
    }

    _server!.listen((request) async {
      if (request.uri.path == '/ws' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        try {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleSocket(socket);
        } catch (e) {
          AppLogger.e('Failed WS upgrade: $e', tag: 'LocalWS');
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
  }

  void _handleSocket(WebSocket socket) {
    final peerId = _generatePeerId();
    AppLogger.i('Peer connected: $peerId', tag: 'LocalWS');
    socket.add(jsonEncode({'type': 'welcome', 'id': peerId}));
    String? joinedRoom;
    bool isRoomHost = false;

    socket.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          switch (msg['type']) {
            case 'join':
              final roomId = msg['roomId'] as String?;
              final isHost = msg['isHost'] as bool? ?? false;
              if (roomId == null || roomId.isEmpty) return;
              joinedRoom = roomId;
              isRoomHost = isHost;
              final room = _rooms.putIfAbsent(roomId, () => {});

              // If this is the host, register the room
              if (isHost && _hostIp != null && _port != null) {
                _roomHosts[roomId] = '$_hostIp:$_port';
                AppLogger.i(
                  'Registered room $roomId with host $_hostIp:$_port',
                  tag: 'LocalWS',
                );
              }

              // existing peers
              final peers = room.keys
                  .where((k) => k != peerId)
                  .map((k) => {'id': k})
                  .toList();

              // Send host info to joining peer
              final response = {
                'type': 'existing-peers',
                'peers': peers,
                'hostInfo': _roomHosts[roomId],
              };
              socket.add(jsonEncode(response));
              room[peerId] = socket;
              // notify others
              for (final entry in room.entries) {
                if (entry.key != peerId) {
                  entry.value.add(
                    jsonEncode({'type': 'peer-joined', 'id': peerId}),
                  );
                }
              }
              AppLogger.i(
                'Peer $peerId joined room $roomId (existing=${peers.length})',
                tag: 'LocalWS',
              );
              break;
            case 'offer':
            case 'answer':
            case 'ice-candidate':
              final to = msg['to'] as String?;
              final roomId2 = msg['roomId'] as String?;
              if (to == null || roomId2 == null) return;
              final room = _rooms[roomId2];
              final target = room?[to];
              if (target != null) {
                target.add(raw);
              }
              break;
            case 'leave':
              _handleLeave(peerId, joinedRoom, isRoomHost);
              break;
          }
        } catch (e) {
          AppLogger.e('Bad message: $e', tag: 'LocalWS');
        }
      },
      onDone: () {
        _handleLeave(peerId, joinedRoom, isRoomHost);
      },
      onError: (e) {
        AppLogger.e('Socket error: $e', tag: 'LocalWS');
        _handleLeave(peerId, joinedRoom, isRoomHost);
      },
    );
  }

  void _handleLeave(String peerId, String? roomId, bool isRoomHost) {
    if (roomId == null) return;
    final room = _rooms[roomId];
    if (room == null) return;
    final socket = room.remove(peerId);
    socket?.close();

    // If host is leaving, remove room registration
    if (isRoomHost) {
      _roomHosts.remove(roomId);
      AppLogger.i('Room $roomId unregistered (host left)', tag: 'LocalWS');
    }

    for (final entry in room.entries) {
      entry.value.add(jsonEncode({'type': 'peer-left', 'id': peerId}));
    }
    if (room.isEmpty) {
      _rooms.remove(roomId);
    }
    AppLogger.i('Peer $peerId left room $roomId', tag: 'LocalWS');
  }

  Future<String?> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!_isLoopback(addr.address) && _isPrivateIp(addr.address)) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      AppLogger.e('IP detection failed: $e', tag: 'LocalWS');
    }
    return null;
  }

  bool _isLoopback(String ip) => ip.startsWith('127.') || ip == '::1';

  bool _isPrivateIp(String ip) {
    return ip.startsWith('10.') ||
        ip.startsWith('192.168.') ||
        _startsWith172Private(ip) ||
        ip.startsWith('169.254.');
  }

  bool _startsWith172Private(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }

  Future<void> stop() async {
    if (!isRunning) return;
    for (final room in _rooms.values) {
      for (final ws in room.values) {
        ws.add(jsonEncode({'type': 'shutdown'}));
        ws.close();
      }
    }
    _rooms.clear();
    _roomHosts.clear();
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _hostIp = null;
    AppLogger.i('Local WS signaling server stopped', tag: 'LocalWS');
  }

  String _generatePeerId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(16);
}
