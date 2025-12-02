// ignore_for_file: unused_field
import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) 'package:cpft/features/webshare/services/io_stub.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:firebase_core/firebase_core.dart';
import 'package:cpft/services/firebase_initializer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cpft/features/webshare/services/firestore_signaling_service.dart';
import 'package:cpft/features/webshare/services/local_websocket_signaling_server.dart';
import 'package:cpft/core/logging/app_logger.dart';
import 'package:cpft/services/notification_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:cpft/features/webshare/services/websocket_compat.dart';
import 'package:cpft/features/webshare/services/web_received_cache.dart';

/// WebRTC-based peer-to-peer file transfer service
class WebRTCFileTransferService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  IO.Socket? _socket;
  WsClient? _ws; // Local WebSocket signaling connection (cross-platform)
  // Firestore signaling state
  FirestoreSession? _firestoreSession;
  StreamSubscription<Map<String, dynamic>?>? _fsOfferSub;
  StreamSubscription<Map<String, dynamic>?>? _fsAnswerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _fsIceSub;
  bool _fsOfferHandled = false;
  bool _fsAnswerHandled = false;
  bool _fsRemoteDescriptionSet = false; // Track when remote SDP applied (Firestore path)
  final List<RTCIceCandidate> _fsPendingRemoteCandidates = <RTCIceCandidate>[]; // Buffer ICE until remote SDP
  String? _fsSessionId; // Session token to distinguish fresh rounds for reused room IDs
  // FirestoreSession? _firestoreSession; // Firestore signaling session for cleanup
  String? _roomId;
  String? _mySocketId;
  String? _peerId; // Local WebSocket assigned id
  String? _connectedPeerSocketId; // Track which peer we're connected to
  bool _isInitialized = false;
  bool _isConnected = false;
  bool _makingOffer = false; // Track if we're currently making an offer
  bool _ignoreOffer = false; // Flag to ignore offers during collision

  // Use hosted signaling server (Vercel)
  final String signalingServerUrl = 'https://webrtc-yesc.onrender.com';
  bool useLocalWebSocket = kIsWeb ? false : true; // Default true for native, false for web
  bool useFirestoreSignaling = kIsWeb ? true : true; // Prefer Firestore on web
  bool _isLocalHost = false; // True when this device hosts the local WS server

  // File transfer state
  final ValueNotifier<bool> isTransferring = ValueNotifier<bool>(false);
  final ValueNotifier<double> transferProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<String?> currentFileName = ValueNotifier<String?>(null);
  final ValueNotifier<bool> connectionEstablished = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLocalMode = ValueNotifier<bool>(kIsWeb ? false : true); // Track signaling mode for UI
  final ValueNotifier<bool> isHostMode = ValueNotifier<bool>(false); // Track if hosting

  // Callbacks
  final Function()? onConnectionEstablished;
  final Function()? onConnectionLost;
  final Function(String filename, int bytesReceived, int totalBytes)?
  onFileReceiveProgress;
  final Function(String filename, String savedPath)? onFileReceiveComplete;
  final Function(String filename, int bytesSent, int totalBytes)?
  onFileSendProgress;
  final Function(String filename, String filePath, int fileSize)?
  onFileSendComplete;
  // New: error callback to signal stalled/failed transfers
  final Function(String filename, String reason, bool duringSend)?
      onFileTransferError;

  // File transfer data
  Uint8List? _receiveBuffer; // Pre-allocated receive buffer
  int _expectedFileSize = 0;
  int _receivedBytes = 0; // Number of bytes written into buffer
  String? _expectedFileName;
  bool _isCompleting = false; // Guard to prevent duplicate completion
  // Receiver stall detection
  Timer? _receiveInactivityTimer;
  DateTime? _lastReceiveAt;
  // Web-only: store received parts to avoid huge contiguous buffers
  List<Uint8List>? _webReceivedParts;
  
  // Transfer speed tracking (both send and receive)
  DateTime? _transferStartTime;
  int _totalBytesTransferred = 0;
  final ValueNotifier<double> transferSpeed = ValueNotifier<double>(0.0); // bytes per second

  // Current send file info (for callback)
  String? _currentSendFilePath;
  int _currentSendFileSize = 0;

  // Simple credit-based flow control (receiver-driven)
  int _sendCredits = 0; // decremented on each chunk sent, incremented by receiver acks
  int _creditWindow = 64; // initial credits; adapt within bounds
  static const int _minCreditWindow = 32;
  static const int _maxCreditWindow = 256;
  // Track ACK timing to estimate simple RTT and adapt credits
  DateTime? _lastAckSentTime; // receiver side
  DateTime? _lastAckReceivedTime; // sender side
  double _smoothedRttMs = 0; // simple EWMA
  static const double _rttAlpha = 0.2; // smoothing factor
  // Chunk sizing (adaptive)
  int _currentChunkSize = 32 * 1024; // start at 32KB
  static const int _minChunkSize = 8 * 1024;
  static const int _maxChunkSize = 64 * 1024;
  int _chunksSinceAck = 0; // receiver-side: send an ack every N chunks

  WebRTCFileTransferService({
    this.onConnectionEstablished,
    this.onConnectionLost,
    this.onFileReceiveProgress,
    this.onFileReceiveComplete,
    this.onFileSendProgress,
    this.onFileSendComplete,
    this.onFileTransferError,
  });

  bool get isInitialized => _isInitialized;
  bool get isConnected => _isConnected;
  String? get mySocketId => _mySocketId;
  String? get roomId => _roomId;
  
  /// Create a new Firestore room with an auto-generated ID (default 4 digits)
  /// and immediately connect to signaling using that room. Returns the room ID.
  Future<String> createAutoRoomAndConnect({int length = 4, bool alphanumeric = false}) async {
    await FirebaseInitializer.ensure();
    final fs = FirestoreSignalingService(db: FirebaseFirestore.instance);
    final newId = await fs.createAutoRoomId(length: length, alphanumeric: alphanumeric);
    await _connectViaFirestore(newId);
    return newId;
  }
  
  /// Get received file bytes (useful for web platform downloads)
  List<int> get receivedFileBytes {
    final buf = _receiveBuffer;
    if (buf == null) return const <int>[];
    final len = _receivedBytes > 0 ? _receivedBytes : buf.length;
    return Uint8List.view(buf.buffer, 0, len);
  }
  String? get receivedFileName => _expectedFileName;

  /// Generate a room ID with embedded IP and port: <random>-<lastIPoctet>-p<port>
  /// Example: 1234-192-p8081 (where 192 is the last octet of 192.168.1.192)
  static String generateRoomIdWithPort(int port, String hostIp) {
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    final shortId = random.substring(random.length - 4); // Last 4 digits
    final lastOctet = hostIp.split('.').last;
    return '$shortId-$lastOctet-p$port';
  }

  /// Extract port from room ID. Returns null if no port encoded.
  /// Example: "1234-192-p8081" -> 8081
  static int? extractPortFromRoomId(String roomId) {
    final match = RegExp(r'-p(\d+)$').firstMatch(roomId);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Extract host IP last octet from room ID. Returns null if not encoded.
  /// Example: "1234-192-p8081" -> 192
  static int? extractHostOctetFromRoomId(String roomId) {
    final match = RegExp(r'-(\d+)-p\d+$').firstMatch(roomId);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Get the base room name without IP and port suffix
  /// Example: "1234-192-p8081" -> "1234"
  static String getBaseRoomId(String roomId) {
    return roomId.replaceAll(RegExp(r'-\d+-p\d+$'), '');
  }

  /// Toggle between local and remote signaling
  void setSignalingMode({required bool useLocal}) {
    // Allow local mode on web for JOINER only (host not supported on web)
    useLocalWebSocket = useLocal;
    isLocalMode.value = useLocal;
    if (kIsWeb && useLocal && isHostMode.value) {
      AppLogger.w('Host mode for local signaling is not supported on web. Switch to Join.', tag: 'WebRTC');
    }
    AppLogger.i('Signaling mode set to: ${useLocal ? "Local" : "Remote"}', tag: 'WebRTC');
  }

  /// Set host mode (for local signaling)
  void setHostMode(bool isHost) {
    _isLocalHost = isHost;
    isHostMode.value = isHost;
    AppLogger.i('Host mode: $isHost', tag: 'WebRTC');
  }

  /// Connect to signaling server: Firestore (preferred on web) or Socket.IO/local WS
  Future<void> connectToSignalingServer(String roomId) async {
    if (useFirestoreSignaling) {
      await _connectViaFirestore(roomId);
      return;
    }
    // Firestore signaling path
    if (useFirestoreSignaling) {
      await _connectViaFirestore(roomId);
      return;
    }
    if (useLocalWebSocket) {
      _roomId = roomId;
      // For local mode: Both host and joiner connect to the same server
      // The server is always running on the host device
      // Joiner needs to discover or know the host IP
      if (_isLocalHost) {
        // Host: start server and connect to own IP
        await _connectLocalWebSocket(roomId);
      } else {
        // Joiner: Try multicast discovery or broadcast to find host
        AppLogger.w('Join mode in local signaling requires host IP. Use connectToLocalHost() instead.', tag: 'WebRTC');
        // Attempt to connect to gateway/broadcast to find host
        await _discoverAndConnectToHost(roomId);
      }
      return;
    }
    if (_socket?.connected ?? false) {
      AppLogger.i('Already connected to signaling server', tag: 'WebRTC');
      return;
    }

    _roomId = roomId;
    AppLogger.i(
      'Connecting to signaling server: $signalingServerUrl',
      tag: 'WebRTC',
    );

    try {
      _socket = IO.io(
        signalingServerUrl,
        IO.OptionBuilder()
        // Prefer WebSocket on Render; fall back to polling if needed
        .setTransports(['websocket', 'polling'])
        // If your server uses a custom path like /socket.io specify it here
        // .setPath('/socket.io')
        .disableAutoConnect()
        .build(),
      );

      // Set up event handlers
      _socket!.on('connect', (_) {
        _mySocketId = _socket!.id;
        AppLogger.i(
          'Connected to signaling server with socket ID: $_mySocketId',
          tag: 'WebRTC',
        );

        // Join the room with full payload matching server expectations
        AppLogger.i('Joining room: "$_roomId"', tag: 'WebRTC');
        if (_roomId != null && _roomId!.isNotEmpty) {
          _socket!.emit('join-room', {
            'roomId': _roomId,
            'role': 'peer',
            'deviceInfo': {
              'platform': Platform.operatingSystem,
              'version': Platform.operatingSystemVersion,
            },
          });
          AppLogger.i(
            'Emitted join-room event with full payload',
            tag: 'WebRTC',
          );
        } else {
          AppLogger.e(
            'Cannot join room: roomId is null or empty',
            tag: 'WebRTC',
          );
        }
      });

      _socket!.on('existing-peers', (data) {
        AppLogger.i('Received existing-peers: $data', tag: 'WebRTC');
        final Map<String, dynamic> response = Map<String, dynamic>.from(
          data as Map,
        );
        final List<dynamic> peers = response['peers'] as List<dynamic>;
        if (peers.isNotEmpty) {
          // Create offer for the first existing peer
          final firstPeer = peers.first as Map<String, dynamic>;
          final peerSocketId = firstPeer['socketId'] as String;
          AppLogger.i(
            'Creating offer for existing peer: $peerSocketId',
            tag: 'WebRTC',
          );
          // Always create offer when we receive existing-peers
          // The peer who joined later creates the offer
          _createOffer(peerSocketId);
        }
      });

      _socket!.on('peer-joined', (data) async {
        final Map<String, dynamic> peerInfo = Map<String, dynamic>.from(
          data as Map,
        );
        final peerSocketId = peerInfo['socketId'] as String;
        AppLogger.i('Peer joined room: $peerSocketId', tag: 'WebRTC');
        // Don't create offer when peer-joined is received
        // The new peer will create the offer when they get existing-peers
        AppLogger.i('Waiting for new peer to create offer', tag: 'WebRTC');
      });

      _socket!.on('offer', (data) async {
        AppLogger.i('Received offer from peer', tag: 'WebRTC');
        final Map<String, dynamic> offerData = Map<String, dynamic>.from(
          data as Map,
        );
        final fromSocketId = offerData['from'] as String;
        final sdp = offerData['sdp'] as Map<String, dynamic>;
        await _handleOffer(fromSocketId, sdp);
      });

      _socket!.on('answer', (data) async {
        AppLogger.i('Received answer from peer', tag: 'WebRTC');
        final Map<String, dynamic> answerData = Map<String, dynamic>.from(
          data as Map,
        );
        final sdp = answerData['sdp'] as Map<String, dynamic>;
        await _handleAnswer(sdp);
      });

      _socket!.on('ice-candidate', (data) async {
        AppLogger.i('Received ICE candidate from peer', tag: 'WebRTC');
        final Map<String, dynamic> candidateData = Map<String, dynamic>.from(
          data as Map,
        );
        final candidate = candidateData['candidate'] as Map<String, dynamic>;
        await _handleIceCandidate(candidate);
      });

      _socket!.on('peer-left', (data) {
        final Map<String, dynamic> peerInfo = Map<String, dynamic>.from(
          data as Map,
        );
        final peerSocketId = peerInfo['socketId'] as String;
        AppLogger.i('Peer left room: $peerSocketId', tag: 'WebRTC');
        // Clean up connection
        disconnect();
      });

      _socket!.on('disconnect', (_) {
        AppLogger.i('Disconnected from signaling server', tag: 'WebRTC');
        _mySocketId = null;
      });

      _socket!.on('connect_error', (error) {
        AppLogger.e('Connection error: $error', tag: 'WebRTC');
      });

      _socket!.on('error', (error) {
        AppLogger.e(
          'Socket error: $error (type: ${error.runtimeType})',
          tag: 'WebRTC',
        );
        if (error is Map) {
          AppLogger.e('Error details: ${error.toString()}', tag: 'WebRTC');
        }
      });

      // Connect
      _socket!.connect();

      // Wait for connection with timeout
      final startTime = DateTime.now();
      while (_mySocketId == null) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (DateTime.now().difference(startTime).inSeconds > 10) {
          throw Exception(
            'Connection timeout: Could not connect to signaling server at $signalingServerUrl. Please check:\n1. Server is running\n2. URL and Socket.IO path are correct\n3. CORS and transport settings allow connections',
          );
        }
      }

      AppLogger.i('Successfully connected to signaling server', tag: 'WebRTC');
    } catch (e) {
      AppLogger.e('Failed to connect to signaling server: $e', tag: 'WebRTC');
      _socket?.disconnect();
      _socket = null;
      _mySocketId = null;
      rethrow;
    }
  }

  // (Removed duplicate _connectViaFirestore definition above)

  Future<void> _connectViaFirestore(String roomId) async {
    _roomId = roomId;
    // Ensure Firebase is initialized (web-safe) before touching Firestore
    await FirebaseInitializer.ensure();

    final fs = FirestoreSignalingService(db: FirebaseFirestore.instance);
    final session = await fs.createSession(roomId);
    _firestoreSession = session;
    _fsOfferHandled = false;
    _fsAnswerHandled = false;
    _fsRemoteDescriptionSet = false;
    _fsPendingRemoteCandidates.clear();
    _fsSessionId = null;

    // Decide role based on Firestore doc state: if no offer exists, we act as offerer
    final snap = await session.doc.get();
    final existing = snap.data();
    // Determine/assign sessionId, resetting stale rooms
    final now = DateTime.now();
    final createdAt = existing?['createdAt'];
    final updatedAt = existing?['updatedAt'];
    DateTime? lastActivity;
    if (updatedAt is Timestamp) {
      lastActivity = updatedAt.toDate();
    } else if (createdAt is Timestamp) {
      lastActivity = createdAt.toDate();
    }
    final isStale = lastActivity != null && now.difference(lastActivity) > const Duration(minutes: 2);
    final existingSessionId = existing?['sessionId'] as String?;
    final hasOffer = existing != null && existing['offer'] != null;
    final hasAnswer = existing != null && existing['answer'] != null;

    // Generate a new sessionId proposal
    final proposedSessionId = DateTime.now().microsecondsSinceEpoch.toString();

    if (existingSessionId == null || isStale || (hasOffer && isStale) || (hasAnswer && isStale)) {
      // Reset the room for a fresh round and claim the sessionId
      await session.resetForNewSession(proposedSessionId);
      _fsSessionId = proposedSessionId;
    } else {
      // Adopt existing active sessionId
      _fsSessionId = existingSessionId;
    }

    // Re-fetch after potential reset to compute role
    final snap2 = await session.doc.get();
    final existing2 = snap2.data();
    final hasOffer2 = existing2 != null && existing2['offer'] != null;
    final isOfferer = !hasOffer2;

    // Create connection; offerer creates data channel
    await _createPeerConnectionForPeer('firestore-peer', createDataChannel: isOfferer);

    // ICE exchange
    _peerConnection!.onIceCandidate = (c) {
      if (c.candidate != null) {
        session.addIce({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
          // Mark role to avoid consuming our own candidates
          'role': isOfferer ? 'offerer' : 'answerer',
          'sessionId': _fsSessionId,
        });
      }
    };
    _fsIceSub = session.onIce().listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          final cand = data?['candidate'] as Map<String, dynamic>?;
          final role = data?['role'] as String?; // who produced this candidate
          final sid = data?['sessionId'] as String?;
          if (cand != null) {
            // Ignore ICE from different session rounds
            if (_fsSessionId != null && sid != null && sid != _fsSessionId) {
              continue;
            }
            // Ignore our own ICE candidates
            final producedByOfferer = role == 'offerer';
            final amOfferer = isOfferer;
            if (role != null && producedByOfferer == amOfferer) {
              continue;
            }
            final remoteCand = RTCIceCandidate(
              cand['candidate'] as String?,
              cand['sdpMid'] as String?,
              (cand['sdpMLineIndex'] as num?)?.toInt(),
            );
            if (_fsRemoteDescriptionSet) {
              try {
                await _peerConnection?.addCandidate(remoteCand);
              } catch (e) {
                AppLogger.e('Failed to add ICE candidate (post-remote SDP): $e', tag: 'WebRTC');
              }
            } else {
              _fsPendingRemoteCandidates.add(remoteCand);
            }
          }
        }
      }
    });

    if (isOfferer) {
      // Write offer and wait for answer
      final pcOfferer = _peerConnection;
      if (pcOfferer == null) {
        AppLogger.w('PeerConnection is null before creating offer (offerer path). Aborting.', tag: 'WebRTC');
        return;
      }
      final offer = await pcOfferer.createOffer();
      await pcOfferer.setLocalDescription(offer);
      final offerMap = offer.toMap();
      offerMap['sessionId'] = _fsSessionId;
      await session.writeOffer(offerMap);
      _fsAnswerSub = session.onAnswer().listen((ans) async {
        if (ans != null && _peerConnection != null && !_fsAnswerHandled) {
          // Enforce session filter
          final sid = ans['sessionId'];
          if (_fsSessionId != null && sid != null && sid != _fsSessionId) {
            return;
          }
          final pc = _peerConnection;
          if (pc == null) {
            AppLogger.w('PeerConnection became null before processing remote answer (offerer path). Aborting.', tag: 'WebRTC');
            return;
          }
          final state = pc.signalingState;
          if (state != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            AppLogger.w('Ignoring remote answer: signalingState=$state (expected have-local-offer)', tag: 'WebRTC');
            return; // Prevent setRemoteDescription in wrong state
          }
          await pc.setRemoteDescription(RTCSessionDescription(ans['sdp'], ans['type']));
          _fsRemoteDescriptionSet = true;
          // Drain any buffered remote ICE now that remote SDP is set
          for (final cand in List<RTCIceCandidate>.from(_fsPendingRemoteCandidates)) {
            try {
              await pc.addCandidate(cand);
            } catch (e) {
              AppLogger.e('Failed to add buffered ICE candidate: $e', tag: 'WebRTC');
            }
          }
          _fsPendingRemoteCandidates.clear();
          // Clean up signaling once connected and schedule deletion
          unawaited(_firestoreSession?.cleanup());
          unawaited(Future.delayed(const Duration(minutes: 5), () => _firestoreSession?.deleteRoom()));
          _fsAnswerHandled = true;
          await _fsAnswerSub?.cancel();
        }
      });
    } else {
      // Wait for offer and respond with answer
      _fsOfferSub = session.onOffer().listen((off) async {
        if (off != null && _peerConnection != null && !_fsOfferHandled) {
          // Enforce session filter
          final sid = off['sessionId'];
          if (_fsSessionId != null && sid != null && sid != _fsSessionId) {
            return;
          }
          var state = _peerConnection!.signalingState;

          // If not stable, handle glare by resetting the connection to accept remote offer
          if (state != RTCSignalingState.RTCSignalingStateStable) {
            AppLogger.w(
              'Remote offer arrived in non-stable state ($state). Resetting to accept remote offer.',
              tag: 'WebRTC',
            );

            try {
              await _peerConnection?.close();
              await _dataChannel?.close();
            } catch (_) {}
            _peerConnection = null;
            _dataChannel = null;
            _isConnected = false;
            connectionEstablished.value = false;

            // Recreate a fresh peer connection (as answerer, do NOT create data channel)
            await _createPeerConnectionForPeer('firestore-peer', createDataChannel: false);

            // Reattach Firestore ICE emission for the new connection (role: answerer)
            _peerConnection!.onIceCandidate = (c) {
              if (c.candidate != null) {
                session.addIce({
                  'candidate': c.candidate,
                  'sdpMid': c.sdpMid,
                  'sdpMLineIndex': c.sdpMLineIndex,
                  'role': 'answerer',
                  'sessionId': _fsSessionId,
                });
              }
            };

            state = _peerConnection!.signalingState;
          }

          // Apply remote offer and generate answer (guard against races)
          final pc = _peerConnection;
          if (pc == null) {
            AppLogger.w('PeerConnection became null before applying remote offer (answerer path). Aborting.', tag: 'WebRTC');
            return;
          }
          await pc.setRemoteDescription(
            RTCSessionDescription(off['sdp'], off['type']),
          );
          _fsRemoteDescriptionSet = true;
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          final ansMap = answer.toMap();
          ansMap['sessionId'] = _fsSessionId;
          await session.writeAnswer(ansMap);

          // Drain any buffered remote ICE now that remote SDP is set
          for (final cand in List<RTCIceCandidate>.from(_fsPendingRemoteCandidates)) {
            try {
              await _peerConnection?.addCandidate(cand);
            } catch (e) {
              AppLogger.e('Failed to add buffered ICE candidate: $e', tag: 'WebRTC');
            }
          }
          _fsPendingRemoteCandidates.clear();

          // Clean up signaling once connected and schedule deletion
          unawaited(_firestoreSession?.cleanup());
          unawaited(Future.delayed(const Duration(minutes: 5), () => _firestoreSession?.deleteRoom()));
          _fsOfferHandled = true;
          await _fsOfferSub?.cancel();
        }
      });
    }
  }

  // ===== Local WebSocket signaling support =====
  Future<int> enableLocalWebSocketMode({required bool host, int port = 8080}) async {
    if (kIsWeb) {
      if (host) {
        AppLogger.w('Local WebSocket host mode is not supported on web. Acting as Joiner only.', tag: 'WebRTC');
        useLocalWebSocket = false; // cannot host, default to remote unless user explicitly connects to host IP
        isLocalMode.value = false;
        _isLocalHost = false;
        isHostMode.value = false;
        return port;
      } else {
        // Allow local-joiner mode on web; user must provide/encode host IP
        useLocalWebSocket = true;
        isLocalMode.value = true;
        _isLocalHost = false;
        isHostMode.value = false;
        return port;
      }
    }

    useLocalWebSocket = true;
    isLocalMode.value = true;
    _isLocalHost = host;
    isHostMode.value = host;
    if (host) {
      await LocalWebSocketSignalingServer().start(port: port);
      final actualPort = LocalWebSocketSignalingServer().port ?? port;
      AppLogger.i('Local WebSocket signaling server started on port $actualPort', tag: 'WebRTC');
      return actualPort;
    }
    return port;
  }

  Future<void> _connectLocalWebSocket(String roomId, {String? hostIp, int port = 8080}) async {
    final ip = hostIp ?? await _detectLocalIp();
    if (ip == null) {
      AppLogger.e('❌ Unable to determine local IP for WebSocket signaling', tag: 'WebRTC');
      return;
    }
    // Use secure WebSocket when page is served over HTTPS to avoid mixed content blocking
    String scheme = (kIsWeb && Uri.base.scheme == 'https') ? 'wss://' : 'ws://';
    final uri = '${scheme}$ip:$port/ws';
    AppLogger.i('Connecting to local signaling WS: $uri', tag: 'WebRTC');
    try {
      // If we are supposed to be host but server not started (e.g. missed enable call), start it now.
      if (!kIsWeb && _isLocalHost && !LocalWebSocketSignalingServer().isRunning) {
        AppLogger.i('⚠️  Local WS server not running; starting automatically', tag: 'WebRTC');
        await LocalWebSocketSignalingServer().start(port: port);
      }
      _ws = await WsClient.connect(uri);
      _ws!.listen(_handleWsMessage, onDone: () {
        AppLogger.i('Local WS connection closed', tag: 'WebRTC');
      }, onError: (error) {
        AppLogger.e('Local WS error: $error', tag: 'WebRTC');
      });
      // Await welcome handshake assigning _peerId
      await _awaitLocalWsHandshake();
      AppLogger.i('✅ Connected successfully to local signaling server', tag: 'WebRTC');
    } on SocketException catch (e) {
      AppLogger.e('═══════════════════════════════════════', tag: 'WebRTC');
      AppLogger.e('❌ Socket connection FAILED', tag: 'WebRTC');
      AppLogger.e('URI: $uri', tag: 'WebRTC');
      AppLogger.e('Error: ${e.message}', tag: 'WebRTC');
      AppLogger.e('OS Error: ${e.osError?.errorCode} - ${e.osError?.message}', tag: 'WebRTC');
      if (_isLocalHost) {
        AppLogger.e('', tag: 'WebRTC');
        AppLogger.e('Host mode connection failed:', tag: 'WebRTC');
        AppLogger.e('• Check if port $port is available', tag: 'WebRTC');
        AppLogger.e('• Try restarting the app', tag: 'WebRTC');
        AppLogger.e('• Check firewall settings', tag: 'WebRTC');
      } else {
        AppLogger.e('', tag: 'WebRTC');
        AppLogger.e('Join mode connection failed:', tag: 'WebRTC');
        AppLogger.e('• Ensure host device is on same WiFi network', tag: 'WebRTC');
        AppLogger.e('• Verify host app is running with server started', tag: 'WebRTC');
        AppLogger.e('• Check if IP $ip is correct and reachable', tag: 'WebRTC');
        AppLogger.e('• Try pinging $ip from your device', tag: 'WebRTC');
      }
      AppLogger.e('═══════════════════════════════════════', tag: 'WebRTC');
    } catch (e) {
      AppLogger.e('❌ Local WS connect failed: $e', tag: 'WebRTC');
      if (_isLocalHost) {
        AppLogger.e('Host mode connection failed. Verify no other service is using port $port and retry.', tag: 'WebRTC');
      } else {
        AppLogger.e('Join mode failed. Ensure host app started local signaling and that IP $ip is reachable.', tag: 'WebRTC');
      }
    }
  }

  /// Explicit connect for a non-host peer using provided host IP
  Future<void> connectToLocalHost(String roomId, {String? hostIp, int port = 8080}) async {
    useLocalWebSocket = true;
    isLocalMode.value = true;
    _isLocalHost = false;
    isHostMode.value = false;
    _roomId = roomId;
    
    // If no host IP provided, try to discover from local server
    if (kIsWeb && Uri.base.scheme == 'https') {
      AppLogger.w('HTTPS origin detected: attempting secure WebSocket (wss). Ensure local WS has TLS.', tag: 'WebRTC');
    }
    final ip = hostIp ?? await _detectLocalIp();
    await _connectLocalWebSocket(roomId, hostIp: ip, port: port);
  }

  /// Attempt to discover host on local network by trying subnet IPs
  Future<void> _discoverAndConnectToHost(String roomId, {int startPort = 8080}) async {
    // Web-specific discovery: try common subnets using roomId-encoded hints
    if (kIsWeb) {
      await _discoverAndConnectToHostOnWeb(roomId, startPort: startPort);
      return;
    }
    // Try to extract port and host IP octet from room ID if encoded
    final extractedPort = extractPortFromRoomId(roomId);
    final extractedHostOctet = extractHostOctetFromRoomId(roomId);
    final actualStartPort = extractedPort ?? startPort;
    final baseRoomId = getBaseRoomId(roomId);
    
      if (kIsWeb && Uri.base.scheme == 'https') {
        AppLogger.e('Failed secure WS (wss). In HTTPS, ws:// is blocked. Options:\n- Use hosted signaling: $signalingServerUrl\n- Configure TLS (valid cert) for local WS\n- Develop over http:// to allow ws:// (not for production).', tag: 'WebRTC');
      }
    AppLogger.i('═══════════════════════════════════════', tag: 'WebRTC');
    AppLogger.i('Starting host discovery on local network', tag: 'WebRTC');
    AppLogger.i('Room ID: $roomId', tag: 'WebRTC');
    if (extractedHostOctet != null) {
      AppLogger.i('✓ Host IP octet extracted from Room ID: $extractedHostOctet', tag: 'WebRTC');
    }
    if (extractedPort != null) {
      AppLogger.i('✓ Port extracted from Room ID: $extractedPort', tag: 'WebRTC');
      if (extractedHostOctet != null) {
        AppLogger.i('🚀 Direct connection mode: Will try only .$extractedHostOctet:$extractedPort', tag: 'WebRTC');
      } else {
        AppLogger.i('Will connect directly to port $extractedPort', tag: 'WebRTC');
      }
    } else {
      AppLogger.i('No port in Room ID, will try ports: $actualStartPort-${actualStartPort + 9}', tag: 'WebRTC');
    }
    AppLogger.i('═══════════════════════════════════════', tag: 'WebRTC');
    
    // Get our own IP to determine subnet
    final myIp = await _detectLocalIp();
    if (myIp == null) {
      AppLogger.e('❌ Cannot discover host: unable to detect own IP', tag: 'WebRTC');
      AppLogger.e('Possible causes: Not connected to WiFi, VPN active, or network permission denied', tag: 'WebRTC');
      return;
    }
    
    AppLogger.i('✓ My IP: $myIp', tag: 'WebRTC');
    
    // Parse subnet (e.g., 192.168.1.x)
    final parts = myIp.split('.');
    if (parts.length != 4) {
      AppLogger.e('❌ Invalid IP format: $myIp', tag: 'WebRTC');
      return;
    }
    
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
    final myHost = int.parse(parts[3]);
    
    AppLogger.i('📡 Scanning subnet: $subnet.x (will skip $subnet.$myHost which is me)', tag: 'WebRTC');
    
    // If we have both IP octet and port from room ID, try direct connection first!
    if (extractedHostOctet != null && extractedPort != null) {
      final directIp = '$subnet.$extractedHostOctet';
      AppLogger.i('⚡ Attempting direct connection to $directIp:$extractedPort...', tag: 'WebRTC');
      if (await _tryConnectToHost(directIp, baseRoomId, extractedPort)) {
        AppLogger.i('✅ SUCCESS! Connected directly to $directIp:$extractedPort', tag: 'WebRTC');
        return;
      } else {
        AppLogger.w('Direct connection failed. Falling back to subnet scan...', tag: 'WebRTC');
      }
    }
    
    AppLogger.i('🔍 Starting with priority IPs: .1, .100, .101, .10, .20, .50', tag: 'WebRTC');
    
    // Try common IPs first (router, gateway, common static IPs)
    final priorityHosts = [1, 100, 101, 10, 20, 50];
    
    AppLogger.i('--- Testing priority IPs ---', tag: 'WebRTC');
    for (final host in priorityHosts) {
      if (host == myHost) continue; // Skip our own IP
      final testIp = '$subnet.$host';
      AppLogger.i('Trying: $testIp...', tag: 'WebRTC');
      
      if (extractedPort != null) {
        // Port known from room ID - try only that port
        if (await _tryConnectToHost(testIp, baseRoomId, extractedPort)) {
          AppLogger.i('✅ SUCCESS! Found host at $testIp:$extractedPort', tag: 'WebRTC');
          return;
        }
      } else {
        // Try multiple ports (8080-8089) since host may be on any of them
        for (int port = actualStartPort; port < actualStartPort + 10; port++) {
          if (await _tryConnectToHost(testIp, baseRoomId, port)) {
            AppLogger.i('✅ SUCCESS! Found host at $testIp:$port', tag: 'WebRTC');
            return;
          }
        }
      }
    }
    AppLogger.i('Priority IPs exhausted, scanning full range...', tag: 'WebRTC');
    
    // Scan broader range (this might take a while)
    final scanMessage = extractedPort != null 
        ? '--- Scanning full subnet (fast - using known port $extractedPort) ---'
        : '--- Scanning full subnet range (this may take several minutes) ---';
    AppLogger.i(scanMessage, tag: 'WebRTC');
    int scanned = 0;
    for (int host = 2; host < 255; host++) {
      if (host == myHost || priorityHosts.contains(host)) continue;
      final testIp = '$subnet.$host';
      scanned++;
      // Log progress every 50 IPs
      if (scanned % 50 == 0) {
        AppLogger.i('Progress: Scanned $scanned IPs...', tag: 'WebRTC');
      }
      
      if (extractedPort != null) {
        // Port known - only try that port (much faster!)
        if (await _tryConnectToHost(testIp, baseRoomId, extractedPort)) {
          AppLogger.i('✅ SUCCESS! Found host at $testIp:$extractedPort after scanning $scanned IPs', tag: 'WebRTC');
          return;
        }
      } else {
        // Try multiple ports on each IP
        for (int port = actualStartPort; port < actualStartPort + 10; port++) {
          if (await _tryConnectToHost(testIp, baseRoomId, port)) {
            AppLogger.i('✅ SUCCESS! Found host at $testIp:$port after scanning $scanned IPs', tag: 'WebRTC');
            return;
          }
        }
      }
    }
    
    AppLogger.e('═══════════════════════════════════════', tag: 'WebRTC');
    AppLogger.e('❌ Host discovery FAILED', tag: 'WebRTC');
    AppLogger.e('Scanned $scanned IPs on subnet $subnet.x', tag: 'WebRTC');
    if (extractedHostOctet != null && extractedPort != null) {
      AppLogger.e('Tried direct connection to .$extractedHostOctet:$extractedPort', tag: 'WebRTC');
    }
    if (extractedPort != null) {
      AppLogger.e('Tried port $extractedPort (from Room ID)', tag: 'WebRTC');
    } else {
      AppLogger.e('Tried ports $actualStartPort-${actualStartPort + 9} on each IP', tag: 'WebRTC');
    }
    AppLogger.e('No WebRTC server found on network', tag: 'WebRTC');
    AppLogger.e('═══════════════════════════════════════', tag: 'WebRTC');
    AppLogger.e('', tag: 'WebRTC');
    AppLogger.e('🔧 Troubleshooting checklist:', tag: 'WebRTC');
    AppLogger.e('1. Is host device connected to SAME WiFi network?', tag: 'WebRTC');
    AppLogger.e('2. Did host successfully start the server (check host logs)?', tag: 'WebRTC');
    if (extractedHostOctet != null) {
      AppLogger.e('3. Verify host IP ends with .$extractedHostOctet', tag: 'WebRTC');
    }
    if (extractedPort != null) {
      AppLogger.e('${extractedHostOctet != null ? "4" : "3"}. Is firewall blocking port $extractedPort on host device?', tag: 'WebRTC');
      AppLogger.e('${extractedHostOctet != null ? "5" : "4"}. Verify Room ID is correct: $roomId', tag: 'WebRTC');
    } else {
      AppLogger.e('3. Is firewall blocking ports $actualStartPort-${actualStartPort + 9} on host device?', tag: 'WebRTC');
    }
    AppLogger.e('${extractedPort != null ? (extractedHostOctet != null ? "6" : "5") : "4"}. Are you on a mobile hotspot with client isolation enabled?', tag: 'WebRTC');
    AppLogger.e('${extractedPort != null ? (extractedHostOctet != null ? "7" : "6") : "5"}. Are both devices on the same subnet (check IP ranges)?', tag: 'WebRTC');
    AppLogger.e('═══════════════════════════════════════', tag: 'WebRTC');
  }

  /// Try connecting to a specific IP and port, return true if successful
  Future<bool> _tryConnectToHost(String ip, String roomId, int port) async {
    try {
      String scheme = (kIsWeb && Uri.base.scheme == 'https') ? 'wss://' : 'ws://';
      final uri = '${scheme}$ip:$port/ws';
      final ws = await WsClient.connect(
        uri,
        timeout: const Duration(milliseconds: 500),
      );
      
      // Successfully connected
      AppLogger.i('✓ Connected to potential host at $ip:$port', tag: 'WebRTC');
      _ws = ws;
      _ws!.listen(_handleWsMessage, onDone: () {
        AppLogger.i('Local WS connection closed', tag: 'WebRTC');
      }, onError: (error) {
        AppLogger.e('Local WS error: $error', tag: 'WebRTC');
      });
      await _awaitLocalWsHandshake();
      AppLogger.i('✅ Handshake successful with $ip:$port', tag: 'WebRTC');
      return true;
    } on TimeoutException catch (_) {
      // Timeout is expected for most IPs, don't log
      return false;
    } on SocketException catch (e) {
      // Connection refused/unreachable - expected, don't spam logs
      if (e.osError?.errorCode == 61 || e.osError?.errorCode == 111) {
        // ECONNREFUSED - service not running on this IP
        return false;
      }
      // Unexpected socket error
      AppLogger.w('Unexpected socket error on $ip: ${e.osError?.errorCode} - ${e.message}', tag: 'WebRTC');
      return false;
    } catch (e) {
      // Other errors might be worth logging
      AppLogger.w('Connection attempt to $ip failed: $e', tag: 'WebRTC');
      return false;
    }
  }

  /// Web-only: attempt to connect using roomId-derived last octet across common subnets
  Future<void> _discoverAndConnectToHostOnWeb(String roomId, {int startPort = 8080}) async {
    final extractedPort = extractPortFromRoomId(roomId);
    final extractedHostOctet = extractHostOctetFromRoomId(roomId);
    final actualStartPort = extractedPort ?? startPort;
    final baseRoomId = getBaseRoomId(roomId);

    AppLogger.i('Web discovery for local host using Room ID: $roomId', tag: 'WebRTC');
    if (extractedHostOctet == null) {
      AppLogger.e('Room ID does not include host IP octet. Cannot discover host from web. Please provide full host IP.', tag: 'WebRTC');
      return;
    }

    final candidates = <String>[
      // Common home/office subnets
      '192.168.0.$extractedHostOctet',
      '192.168.1.$extractedHostOctet',
      '10.0.0.$extractedHostOctet',
      '10.1.1.$extractedHostOctet',
      // Mobile hotspots
      '172.20.10.$extractedHostOctet', // iOS hotspot
      '192.168.43.$extractedHostOctet', // Android hotspot
      '192.168.137.$extractedHostOctet', // Windows ICS
    ];

    // Try direct candidates
    for (final ip in candidates) {
      if (extractedPort != null) {
        if (await _tryConnectToHost(ip, baseRoomId, extractedPort)) return;
      } else {
        for (int port = actualStartPort; port < actualStartPort + 10; port++) {
          if (await _tryConnectToHost(ip, baseRoomId, port)) return;
        }
      }
    }

    AppLogger.e('Web discovery failed. Provide host IP explicitly or ensure Room ID includes correct IP octet and try different common subnets.', tag: 'WebRTC');
  }

  /// Convenience: start local host server (if not running) and connect, returning room ID with port.
  /// Returns the generated room ID with embedded IP and port (e.g., "ROOM1234-192-p8081")
  Future<String?> startLocalHostAndConnect({int port = 8080}) async {
    AppLogger.i('═══════════════════════════════════════', tag: 'WebRTC');
    AppLogger.i('Starting as HOST', tag: 'WebRTC');
    AppLogger.i('═══════════════════════════════════════', tag: 'WebRTC');
    
    useLocalWebSocket = true;
    isLocalMode.value = true;
    _isLocalHost = true;
    isHostMode.value = true;
    final actualPort = await enableLocalWebSocketMode(host: true, port: port); // ensures server start
    
    final ip = await _detectLocalIp();
    
    if (ip == null) {
      AppLogger.e('❌ Failed to detect local IP address', tag: 'WebRTC');
      AppLogger.e('Cannot start as host without valid IP', tag: 'WebRTC');
      return null;
    }
    
    // Generate room ID with embedded IP and port
    final roomIdWithPort = generateRoomIdWithPort(actualPort, ip);
    _roomId = roomIdWithPort;
    
    AppLogger.i('✓ Host IP: $ip', tag: 'WebRTC');
    AppLogger.i('✓ Port: $actualPort', tag: 'WebRTC');
    AppLogger.i('✓ Generated Room ID: $roomIdWithPort', tag: 'WebRTC');
    AppLogger.i('📡 Server running at ws://$ip:$actualPort/ws', tag: 'WebRTC');
    AppLogger.i('Other devices can join using Room ID: $roomIdWithPort', tag: 'WebRTC');
    AppLogger.i('═══════════════════════════════════════', tag: 'WebRTC');
    
    await _connectLocalWebSocket(roomIdWithPort, hostIp: ip, port: actualPort);
    return roomIdWithPort;
  }

  void _handleWsMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'welcome':
          _peerId = msg['id'] as String?;
          AppLogger.i('Local WS assigned peerId: $_peerId', tag: 'WebRTC');
          if (_roomId != null) {
            _ws?.add(jsonEncode({
              'type': 'join',
              'roomId': _roomId,
              'isHost': _isLocalHost,
            }));
          }
          break;
        case 'existing-peers':
          // Check if host info is provided (for join mode)
          final hostInfo = msg['hostInfo'] as String?;
          if (hostInfo != null && !_isLocalHost) {
            AppLogger.i('Received host info: $hostInfo', tag: 'WebRTC');
          }
          
          final peers = (msg['peers'] as List<dynamic>).cast<Map<String, dynamic>>();
          if (peers.isNotEmpty) {
            final targetId = peers.first['id'] as String;
            _createOffer(targetId);
          }
          break;
        case 'peer-joined':
          AppLogger.i('Local WS peer joined: ${msg['id']}', tag: 'WebRTC');
          break; // Offer will be created by the joining peer
        case 'offer':
          _handleOffer(msg['from'] as String, Map<String, dynamic>.from(msg['sdp'] as Map));
          break;
        case 'answer':
          _handleAnswer(Map<String, dynamic>.from(msg['sdp'] as Map));
          break;
        case 'ice-candidate':
          _handleIceCandidate(Map<String, dynamic>.from(msg['candidate'] as Map));
          break;
        case 'peer-left':
          AppLogger.i('Local WS peer left: ${msg['id']}', tag: 'WebRTC');
          disconnect();
          break;
      }
    } catch (e) {
      AppLogger.e('Failed to handle WS message: $e', tag: 'WebRTC');
    }
  }

  Future<void> _awaitLocalWsHandshake({Duration timeout = const Duration(seconds: 5)}) async {
    final start = DateTime.now();
    while (_peerId == null && DateTime.now().difference(start) < timeout) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_peerId == null) {
      AppLogger.e('Local WS handshake (welcome) not received within ${timeout.inSeconds}s. Verify host started server or port blocked.', tag: 'WebRTC');
    } else {
      AppLogger.i('Local WS handshake complete (peerId=$_peerId)', tag: 'WebRTC');
    }
  }

  Future<String?> _detectLocalIp() async {
    // On web, we cannot detect local IP using NetworkInterface
    if (kIsWeb) {
      AppLogger.w('Local IP detection not available on web platform', tag: 'WebRTC');
      return null;
    }
    
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!_isLoopback(addr.address) && _isPrivateIp(addr.address)) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      AppLogger.e('IP detection failed: $e', tag: 'WebRTC');
    }
    return null;
  }

  bool _isLoopback(String ip) => ip.startsWith('127.') || ip == '::1';


  /// Check if this is the polite peer (backs off during collisions)
  bool _isPolite(String peerSocketId) {
    if (_mySocketId == null) return true; // Default to polite
    return _mySocketId!.compareTo(peerSocketId) < 0;
  }

  /// Initialize WebRTC (alias for connectToSignalingServer for backward compatibility)
  Future<void> initialize(String roomId) async {
    await connectToSignalingServer(roomId);
  }

  /// Create offer for initiating connection
  Future<void> _createOffer(String targetSocketId) async {
    // Close any existing peer connection to ensure clean state
    if (_peerConnection != null) {
      AppLogger.i(
        'Closing existing peer connection before creating new offer',
        tag: 'WebRTC',
      );
      await _peerConnection?.close();
      await _dataChannel?.close();
      _peerConnection = null;
      _dataChannel = null;
      _isConnected = false;
      connectionEstablished.value = false;
    }

    // Always create a fresh peer connection
    await _createPeerConnectionForPeer(targetSocketId, createDataChannel: true);

    try {
      // Set making offer flag
      _makingOffer = true;

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send offer via Socket.IO with 'to' parameter
      AppLogger.i(
        'Sending offer to peer: $targetSocketId in room: $_roomId',
        tag: 'WebRTC',
      );
      if (useLocalWebSocket) {
        _ws?.add(jsonEncode({
          'type': 'offer',
          'roomId': _roomId,
          'to': targetSocketId,
          'from': _peerId,
          'sdp': offer.toMap(),
        }));
      } else {
        _socket?.emit('offer', {
          'roomId': _roomId,
          'to': targetSocketId,
          'from': _mySocketId,
          'sdp': offer.toMap(),
        });
      }

      _makingOffer = false;
    } catch (e) {
      AppLogger.e('Failed to create offer: $e', tag: 'WebRTC');
      _makingOffer = false;
      rethrow;
    }
  }

  /// Create and configure a new peer connection for the given peer
  Future<void> _createPeerConnectionForPeer(
    String peerSocketId, {
    bool createDataChannel = false,
  }) async {
    _connectedPeerSocketId = peerSocketId;
    // LAN-only: gather host candidates only (no STUN/TURN)
    final configuration = <String, dynamic>{
      'iceServers': <Map<String, dynamic>>[],
      'iceCandidatePoolSize': 2,
      // 'iceTransportPolicy': 'all', // default; host only since no servers provided
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      AppLogger.i('WebRTC connection state: $state', tag: 'WebRTC');
      final wasConnected = _isConnected;
      _isConnected =
          state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      connectionEstablished.value = _isConnected;

      if (_isConnected && !wasConnected) {
        AppLogger.i('🎉 WebRTC connection ESTABLISHED!', tag: 'WebRTC');
        onConnectionEstablished?.call();
      } else if (!_isConnected && wasConnected) {
        AppLogger.i('❌ WebRTC connection LOST!', tag: 'WebRTC');
        onConnectionLost?.call();
      }
    };

    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      AppLogger.i('Data channel received: ${channel.label}', tag: 'WebRTC');
      _setupDataChannel(channel);
    };

    if (createDataChannel) {
      // Create data channel (for offerer)
      // Use RELIABLE + UNORDERED to avoid head-of-line blocking.
      // Reliability is ensured by leaving maxRetransmits/maxPacketLifeTime unset.
      _dataChannel = await _peerConnection!.createDataChannel(
        'file-transfer',
        RTCDataChannelInit()
          ..ordered = true,
      );
      AppLogger.i('Created data channel (reliable unordered)', tag: 'WebRTC');
      _setupDataChannel(_dataChannel!);
    }

    // Set up ICE candidate handler
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null &&
          _connectedPeerSocketId == peerSocketId) {
        AppLogger.i(
          'Sending ICE candidate to peer: $peerSocketId',
          tag: 'WebRTC',
        );
        if (useLocalWebSocket) {
          _ws?.add(jsonEncode({
            'type': 'ice-candidate',
            'roomId': _roomId,
            'to': peerSocketId,
            'from': _peerId,
            'candidate': candidate.toMap(),
          }));
        } else {
          _socket?.emit('ice-candidate', {
            'roomId': _roomId,
            'to': peerSocketId,
            'from': _mySocketId,
            'candidate': candidate.toMap(),
          });
        }
      }
    };
  }

  /// Accept offer and create answer
  Future<void> _handleOffer(
    String fromSocketId,
    Map<String, dynamic> offer,
  ) async {
    AppLogger.i('Handling offer from peer: $fromSocketId', tag: 'WebRTC');

    // Implement perfect negotiation pattern for collision handling
    final isPolite = _isPolite(fromSocketId);

    // Only consider it a collision if we have a peer connection AND it's not stable
    final offerCollision =
        _peerConnection != null &&
        (_makingOffer ||
            _peerConnection!.signalingState !=
                RTCSignalingState.RTCSignalingStateStable);

    _ignoreOffer = !isPolite && offerCollision;

    if (_ignoreOffer) {
      AppLogger.i(
        'Ignoring offer due to collision (impolite peer)',
        tag: 'WebRTC',
      );
      return;
    }

    AppLogger.i(
      'Processing offer (isPolite: $isPolite, collision: $offerCollision, signalingState: ${_peerConnection?.signalingState})',
      tag: 'WebRTC',
    );

    // Close any existing peer connection to ensure clean state
    if (_peerConnection != null) {
      AppLogger.i(
        'Closing existing peer connection before handling offer',
        tag: 'WebRTC',
      );
      await _peerConnection?.close();
      await _dataChannel?.close();
      _peerConnection = null;
      _dataChannel = null;
      _isConnected = false;
      connectionEstablished.value = false;
    }

    // Always create a fresh peer connection (as answerer, don't create data channel)
    await _createPeerConnectionForPeer(fromSocketId, createDataChannel: false);

    try {
      // Set remote description
      final remoteDescription = RTCSessionDescription(offer['sdp'], 'offer');
      await _peerConnection!.setRemoteDescription(remoteDescription);

      // Create answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Send answer via Socket.IO with 'to' parameter
      AppLogger.i(
        'Sending answer to peer: $fromSocketId in room: $_roomId',
        tag: 'WebRTC',
      );
      if (useLocalWebSocket) {
        _ws?.add(jsonEncode({
          'type': 'answer',
          'roomId': _roomId,
          'to': fromSocketId,
          'from': _peerId,
          'sdp': answer.toMap(),
        }));
      } else {
        _socket?.emit('answer', {
          'roomId': _roomId,
          'to': fromSocketId,
          'from': _mySocketId,
          'sdp': answer.toMap(),
        });
      }
    } catch (e) {
      AppLogger.e('Failed to handle offer: $e', tag: 'WebRTC');
      rethrow;
    }
  }

  /// Handle answer from peer
  Future<void> _handleAnswer(Map<String, dynamic> answer) async {
    if (_peerConnection == null) {
      AppLogger.e(
        'Cannot handle answer: peer connection not initialized',
        tag: 'WebRTC',
      );
      return;
    }

    try {
      final remoteDescription = RTCSessionDescription(answer['sdp'], 'answer');
      await _peerConnection!.setRemoteDescription(remoteDescription);
      AppLogger.i('Answer processed successfully', tag: 'WebRTC');
    } catch (e) {
      AppLogger.e('Failed to handle answer: $e', tag: 'WebRTC');
      rethrow;
    }
  }

  /// Handle ICE candidate from peer
  Future<void> _handleIceCandidate(Map<String, dynamic> candidateData) async {
    if (_peerConnection == null) {
      AppLogger.e(
        'Cannot handle ICE candidate: peer connection not initialized',
        tag: 'WebRTC',
      );
      return;
    }

    try {
      final iceCandidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );
      await _peerConnection!.addCandidate(iceCandidate);
      AppLogger.i('ICE candidate added successfully', tag: 'WebRTC');
    } catch (e) {
      AppLogger.e('Failed to add ICE candidate: $e', tag: 'WebRTC');
    }
  }

  /// Send file to connected peer
  Future<void> sendFile(String filePath) async {
    if (_dataChannel == null) {
      throw Exception('WebRTC data channel not available');
    }

    // Ensure data channel is open before sending
    await _ensureDataChannelOpen();

    if (kIsWeb) {
      throw UnsupportedError('sendFile() with file path is not supported on web. Use sendFileBytes() instead.');
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File does not exist: $filePath');
      }

      final fileName = p.basename(filePath);
      final fileSize = await file.length();
      final fileData = await file.readAsBytes();

      // Store current send file info for callback
      _currentSendFilePath = filePath;
      _currentSendFileSize = fileSize;

      isTransferring.value = true;
      currentFileName.value = fileName;
      transferProgress.value = 0.0;
      _transferStartTime = DateTime.now();
      _totalBytesTransferred = 0;
      transferSpeed.value = 0.0;

      // Send file metadata first
      final metadata = {
        'type': 'file-metadata',
        'fileName': fileName,
        'fileSize': fileSize,
      };
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(metadata)));

      // Send file data in chunks with backpressure + stall detection + credit-based flow control
      const chunkSize = 16 * 1024; // 16KB chunks
      const highWaterMark = 1024 * 1024; // 1MB buffer threshold
      var sentBytes = 0;
      // Stall detection while waiting on bufferedAmount/credits (300s for slow networks)
      const stallTimeout = Duration(seconds: 300);
      int lastBuffered = -1;
      DateTime? stallSince;

      // Initialize credits
      _sendCredits = _creditWindow;

      for (var i = 0; i < fileData.length; i += chunkSize) {
        final end = (i + chunkSize < fileData.length)
            ? i + chunkSize
            : fileData.length;
        final chunk = fileData.sublist(i, end);

        // Wait for credits from receiver (ack-based flow control)
        DateTime waitStart = DateTime.now();
        while (_sendCredits <= 0) {
          if (DateTime.now().difference(waitStart) > stallTimeout) {
            final name = fileName;
            _resetSendState();
            onFileTransferError?.call(
                name, 'Sender stalled: no receiver acks for ${stallTimeout.inSeconds}s', true);
            throw Exception('WebRTC send stalled (no acks)');
          }
          await Future.delayed(const Duration(milliseconds: 2));
        }

        // Backpressure: wait while the outbound buffer is large with stall detection
        while ((_dataChannel!.bufferedAmount ?? 0) > highWaterMark) {
          final currentBuffered = _dataChannel!.bufferedAmount ?? 0;
          if (lastBuffered == -1 || currentBuffered < lastBuffered) {
            lastBuffered = currentBuffered;
            stallSince = null; // progress observed
          } else {
            stallSince ??= DateTime.now();
            if (DateTime.now().difference(stallSince) > stallTimeout) {
              final name = fileName;
              _resetSendState();
              onFileTransferError?.call(
                  name, 'Sender stalled: no drain for ${stallTimeout.inSeconds}s', true);
              throw Exception('WebRTC send stalled');
            }
          }
          if (DateTime.now().second % 10 == 0) {
            AppLogger.i('Waiting: bufferedAmount=$currentBuffered (> $highWaterMark)', tag: 'WebRTC');
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }

        // Send with offset header for ordered writes on receiver
        // Format: 8 bytes offset (2x uint32 big endian) + chunk data
        final offsetBytes = Uint8List(8);
        final byteData = ByteData.view(offsetBytes.buffer);
        // Split 64-bit offset into two 32-bit values (high, low)
        final offsetHigh = (i >> 32) & 0xFFFFFFFF;
        final offsetLow = i & 0xFFFFFFFF;
        byteData.setUint32(0, offsetHigh, Endian.big);
        byteData.setUint32(4, offsetLow, Endian.big);
        final packedChunk = Uint8List(8 + chunk.length);
        packedChunk.setRange(0, 8, offsetBytes);
        packedChunk.setRange(8, packedChunk.length, chunk);
        _dataChannel!.send(RTCDataChannelMessage.fromBinary(packedChunk));
        _sendCredits--;

        sentBytes += chunk.length;
        _totalBytesTransferred += chunk.length;
        transferProgress.value = sentBytes / fileSize;
        
        // Calculate transfer speed
        if (_transferStartTime != null) {
          final elapsed = DateTime.now().difference(_transferStartTime!).inMilliseconds;
          if (elapsed > 0) {
            transferSpeed.value = (_totalBytesTransferred * 1000.0) / elapsed;
          }
        }
        
        onFileSendProgress?.call(fileName, sentBytes.toInt(), fileSize);
        // Adaptive pacing based on current bufferedAmount
        final b = _dataChannel!.bufferedAmount ?? 0;
        int delayMs = 0;
        if (b > 1024 * 1024) {
          delayMs = 8;
        } else if (b > 512 * 1024) {
          delayMs = 5;
        } else if (b > 256 * 1024) {
          delayMs = 3;
        } else if (b > 128 * 1024) {
          delayMs = 1;
        }
        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }

      // Log completion of sending all chunks
      AppLogger.i('All chunks sent: $sentBytes/$fileSize bytes', tag: 'WebRTC');

      // CRITICAL: Wait for all buffered data to be sent before completion message
      // The data channel buffers data, so we need to wait until bufferedAmount is 0
      final initialBuffered = _dataChannel!.bufferedAmount ?? 0;
      AppLogger.i('Waiting for data channel to flush (bufferedAmount: $initialBuffered)...', tag: 'WebRTC');
      
      // Wait with timeout (60 seconds max for large files)
      final flushStartTime = DateTime.now();
      const maxFlushWait = Duration(seconds: 60);
      while ((_dataChannel!.bufferedAmount ?? 0) > 0) {
        if (DateTime.now().difference(flushStartTime) > maxFlushWait) {
          final remaining = _dataChannel!.bufferedAmount ?? 0;
          AppLogger.w('Flush timeout after 60s, remaining buffer: $remaining bytes', tag: 'WebRTC');
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      final finalBuffered = _dataChannel!.bufferedAmount ?? 0;
      AppLogger.i('Data channel flushed (remaining: $finalBuffered), sending completion message', tag: 'WebRTC');

      // Send completion message
      final completion = {'type': 'file-complete', 'fileName': fileName};
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(completion)));

      isTransferring.value = false;
      transferProgress.value = 1.0;
      onFileSendComplete?.call(
        fileName,
        _currentSendFilePath!,
        _currentSendFileSize,
      );

      NotificationService().showNotification(
        type: NotificationType.fileTransferCompleted,
        title: 'File Sent',
        body: 'Successfully sent $fileName via WebRTC',
      );

      AppLogger.i('File sent successfully: $fileName', tag: 'WebRTC');

      // Clear send file info
      _resetSendState();
    } catch (e) {
      AppLogger.e('Failed to send file: $e', tag: 'WebRTC');
      // Surface error if available
      final name = _currentSendFilePath != null ? p.basename(_currentSendFilePath!) : (currentFileName.value ?? 'unknown');
      _resetSendState();
      onFileTransferError?.call(name, e.toString(), true);
      rethrow;
    }
  }

  /// Send file from bytes (web-compatible)
  Future<void> sendFileBytes(String fileName, List<int> fileBytes) async {
    if (_dataChannel == null) {
      throw Exception('WebRTC data channel not available');
    }

    // Ensure data channel is open before sending
    await _ensureDataChannelOpen();

    try {
      final fileSize = fileBytes.length;

      // Store current send file info for callback
      _currentSendFilePath = fileName;
      _currentSendFileSize = fileSize;

      isTransferring.value = true;
      currentFileName.value = fileName;
      transferProgress.value = 0.0;
      _transferStartTime = DateTime.now();
      _totalBytesTransferred = 0;
      transferSpeed.value = 0.0;

      // Send file metadata
      final metadata = {
        'type': 'file-metadata',
        'fileName': fileName,
        'fileSize': fileSize,
      };
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(metadata)));

      AppLogger.i('Sending file: $fileName ($fileSize bytes)', tag: 'WebRTC');

      // Send file in chunks with backpressure + stall detection + credit-based flow control
      const chunkSize = 16 * 1024; // 16KB chunks
      const highWaterMark = 1024 * 1024; // 1MB buffer threshold
      int sentBytes = 0;
      // Stall detection while waiting on bufferedAmount/credits (300s for slow networks)
      const stallTimeout = Duration(seconds: 300);
      int lastBuffered = -1;
      DateTime? stallSince;

      // Initialize credits
      _sendCredits = _creditWindow;

      for (int i = 0; i < fileSize; i += chunkSize) {
        final end = (i + chunkSize < fileSize) ? i + chunkSize : fileSize;
        final chunk = fileBytes.sublist(i, end);

        // Wait for credits from receiver (ack-based flow control)
        DateTime waitStart = DateTime.now();
        while (_sendCredits <= 0) {
          if (DateTime.now().difference(waitStart) > stallTimeout) {
            _resetSendState();
            onFileTransferError?.call(
                fileName, 'Sender stalled: no receiver acks for ${stallTimeout.inSeconds}s', true);
            throw Exception('WebRTC send stalled (no acks)');
          }
          await Future.delayed(const Duration(milliseconds: 2));
        }

        // Backpressure: wait while the outbound buffer is large with stall detection
        while ((_dataChannel!.bufferedAmount ?? 0) > highWaterMark) {
          final currentBuffered = _dataChannel!.bufferedAmount ?? 0;
          if (lastBuffered == -1 || currentBuffered < lastBuffered) {
            lastBuffered = currentBuffered;
            stallSince = null; // progress observed
          } else {
            stallSince ??= DateTime.now();
            if (DateTime.now().difference(stallSince) > stallTimeout) {
              _resetSendState();
              onFileTransferError?.call(
                  fileName, 'Sender stalled: no drain for ${stallTimeout.inSeconds}s', true);
              throw Exception('WebRTC send stalled');
            }
          }
          if (DateTime.now().second % 10 == 0) {
            AppLogger.i('Waiting: bufferedAmount=$currentBuffered (> $highWaterMark)', tag: 'WebRTC');
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }

        // Send with offset header for ordered writes on receiver
        // Format: 8 bytes offset (2x uint32 big endian) + chunk data
        final offsetBytes = Uint8List(8);
        final byteData = ByteData.view(offsetBytes.buffer);
        // Split 64-bit offset into two 32-bit values (high, low)
        final offsetHigh = (i >> 32) & 0xFFFFFFFF;
        final offsetLow = i & 0xFFFFFFFF;
        byteData.setUint32(0, offsetHigh, Endian.big);
        byteData.setUint32(4, offsetLow, Endian.big);
        final packedChunk = Uint8List(8 + chunk.length);
        packedChunk.setRange(0, 8, offsetBytes);
        packedChunk.setRange(8, packedChunk.length, chunk);
        _dataChannel!.send(RTCDataChannelMessage.fromBinary(packedChunk));
        _sendCredits--;

        sentBytes += chunk.length;
        _totalBytesTransferred += chunk.length;
        transferProgress.value = sentBytes / fileSize;
        
        // Calculate transfer speed
        if (_transferStartTime != null) {
          final elapsed = DateTime.now().difference(_transferStartTime!).inMilliseconds;
          if (elapsed > 0) {
            transferSpeed.value = (_totalBytesTransferred * 1000.0) / elapsed;
          }
        }
        
        onFileSendProgress?.call(fileName, sentBytes.toInt(), fileSize);
        // Adaptive pacing based on current bufferedAmount
        final b = _dataChannel!.bufferedAmount ?? 0;
        int delayMs = 0;
        if (b > 1024 * 1024) {
          delayMs = 8;
        } else if (b > 512 * 1024) {
          delayMs = 5;
        } else if (b > 256 * 1024) {
          delayMs = 3;
        } else if (b > 128 * 1024) {
          delayMs = 1;
        }
        if (delayMs > 0) {
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }

      // Log completion of sending all chunks (web)
      AppLogger.i('All chunks sent (web): $sentBytes/$fileSize bytes', tag: 'WebRTC');

      // CRITICAL: Wait for all buffered data to be sent before completion message
      final initialBuffered = _dataChannel!.bufferedAmount ?? 0;
      AppLogger.i('Waiting for data channel to flush (bufferedAmount: $initialBuffered)...', tag: 'WebRTC');
      
      // Wait with timeout (60 seconds max for large files)
      final flushStartTime = DateTime.now();
      const maxFlushWait = Duration(seconds: 60);
      while ((_dataChannel!.bufferedAmount ?? 0) > 0) {
        if (DateTime.now().difference(flushStartTime) > maxFlushWait) {
          final remaining = _dataChannel!.bufferedAmount ?? 0;
          AppLogger.w('Flush timeout after 60s, remaining buffer: $remaining bytes', tag: 'WebRTC');
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      final finalBuffered = _dataChannel!.bufferedAmount ?? 0;
      AppLogger.i('Data channel flushed (remaining: $finalBuffered), sending completion message', tag: 'WebRTC');

      // Send completion message
      final completion = {'type': 'file-complete', 'fileName': fileName};
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(completion)));

      isTransferring.value = false;
      transferProgress.value = 1.0;
      transferSpeed.value = 0.0;
      onFileSendComplete?.call(
        fileName,
        fileName, // Use fileName as path for web
        _currentSendFileSize,
      );

      NotificationService().showNotification(
        type: NotificationType.fileTransferCompleted,
        title: 'File Sent',
        body: 'Successfully sent $fileName via WebRTC',
      );

      AppLogger.i('File sent successfully: $fileName', tag: 'WebRTC');

      // Clear send file info
      _resetSendState();
    } catch (e) {
      AppLogger.e('Failed to send file: $e', tag: 'WebRTC');
      _resetSendState();
      onFileTransferError?.call(fileName, e.toString(), true);
      rethrow;
    }
  }

  /// Set up data channel event handlers
  void _setupDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;

    channel.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        _handleBinaryChunk(message.binary);
        return;
      }
      try {
        final data = jsonDecode(message.text);
        _handleDataChannelMessage(data);
      } catch (e) {
        AppLogger.e('Failed to parse data channel message: $e', tag: 'WebRTC');
      }
    };

    channel.onDataChannelState = (RTCDataChannelState state) {
      AppLogger.i('Data channel state: $state', tag: 'WebRTC');
      if (state == RTCDataChannelState.RTCDataChannelClosed &&
          isTransferring.value) {
        final name = currentFileName.value ?? 'unknown';
        onFileTransferError?.call(
            name, 'Data channel closed during transfer',
            // If we are sending, treat as send; else receive
            _currentSendFileSize > 0);
      }
    };

    // For browsers that support it, try to set bufferedAmountLowThreshold via JS interop (best effort)
    try {
      // ignore: undefined_prefixed_name
      // This is a no-op on platforms without JS interop; left as future enhancement
    } catch (_) {}
  }

  /// Handle incoming data channel messages
  void _handleDataChannelMessage(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'file-metadata':
        _handleFileMetadata(data);
        break;
      case 'file-chunk':
        _handleFileChunk(data);
        break;
      case 'file-complete':
        _handleFileComplete(data);
        break;
      case 'ack':
        // Receiver reports it processed some chunks; increase send credits
        final inc = (data['count'] is int)
            ? data['count'] as int
            : int.tryParse('${data['count']}') ?? 0;
        if (inc > 0) {
          _sendCredits += inc;
          if (_sendCredits > _creditWindow) _sendCredits = _creditWindow;
        }
        break;
    }
  }

  /// Handle file metadata
  void _handleFileMetadata(Map<String, dynamic> data) {
    _expectedFileName = data['fileName'];
    _expectedFileSize = data['fileSize'];
    if (kIsWeb) {
      _receiveBuffer = null; // avoid huge contiguous allocation on web
      _webReceivedParts = <Uint8List>[];
    } else {
      _receiveBuffer = Uint8List(_expectedFileSize);
      _webReceivedParts = null;
    }
    _receivedBytes = 0;
    _isCompleting = false;
    _chunksSinceAck = 0; // reset receiver ack counter
    _transferStartTime = DateTime.now();
    _totalBytesTransferred = 0;
    transferSpeed.value = 0.0;
    isTransferring.value = true;
    currentFileName.value = _expectedFileName;
    transferProgress.value = 0.0;
    // Start receiver inactivity watchdog
    _lastReceiveAt = DateTime.now();
    _startReceiveInactivityWatch();

    AppLogger.i(
      'Receiving file: $_expectedFileName ($_expectedFileSize bytes)',
      tag: 'WebRTC',
    );
  }

  /// Handle file chunk
  void _handleFileChunk(Map<String, dynamic> data) {
    try {
      final chunkData = base64Decode(data['data']);
      if (kIsWeb) {
        _webReceivedParts ??= <Uint8List>[];
        _webReceivedParts!.add(Uint8List.fromList(chunkData));
        _receivedBytes += chunkData.length;
      } else {
        final int? offset = data['offset'] is int
            ? data['offset'] as int
            : int.tryParse('${data['offset']}');
        if (_receiveBuffer != null && offset != null) {
          final end = (offset + chunkData.length) > _receiveBuffer!.length
              ? _receiveBuffer!.length
              : offset + chunkData.length;
          _receiveBuffer!.setRange(offset, end, chunkData);
          final written = end;
          if (written > _receivedBytes) _receivedBytes = written;
        } else {
          _receivedBytes += chunkData.length;
        }
      }

      final receivedBytes = _receivedBytes.clamp(0, _expectedFileSize);
      transferProgress.value = _expectedFileSize == 0
          ? 0
          : receivedBytes / _expectedFileSize;
      onFileReceiveProgress?.call(
        _expectedFileName!,
        receivedBytes,
        _expectedFileSize,
      );
      // Bump activity timestamp
      _lastReceiveAt = DateTime.now();

      AppLogger.d(
        'Received chunk: $receivedBytes/$_expectedFileSize bytes',
        tag: 'WebRTC',
      );
    } catch (e) {
      AppLogger.e('Failed to handle file chunk: $e', tag: 'WebRTC');
    }
  }

  /// Handle binary chunk (preferred for performance)
  void _handleBinaryChunk(Uint8List chunkData) {
    try {
      // Extract offset from first 8 bytes (2x uint32 big endian)
      if (chunkData.length < 8) {
        AppLogger.e('Invalid binary chunk: too small (${chunkData.length} bytes)', tag: 'WebRTC');
        return;
      }
      final byteData = ByteData.view(chunkData.buffer, chunkData.offsetInBytes, chunkData.lengthInBytes);
      // Reconstruct 64-bit offset from two 32-bit values (high, low)
      final offsetHigh = byteData.getUint32(0, Endian.big);
      final offsetLow = byteData.getUint32(4, Endian.big);
      final offset = (offsetHigh << 32) | offsetLow;
      final actualData = Uint8List.view(chunkData.buffer, chunkData.offsetInBytes + 8, chunkData.lengthInBytes - 8);
      
      // Track actual received bytes (chunk size, not offset)
      _receivedBytes += actualData.length;
      _totalBytesTransferred += actualData.length;
      
      // Log progress every 10MB for large files
      if (_expectedFileSize > 50 * 1024 * 1024 && _receivedBytes % (10 * 1024 * 1024) < actualData.length) {
        final percent = (_receivedBytes / _expectedFileSize * 100).toStringAsFixed(1);
        AppLogger.i('Receive progress: $_receivedBytes/$_expectedFileSize bytes ($percent%)', tag: 'WebRTC');
      }
      
      if (kIsWeb) {
        // For web, we need to maintain ordered parts for corruption-free assembly
        // Store chunk with its offset for later ordered reconstruction
        _webReceivedParts ??= <Uint8List>[];
        _webReceivedParts!.add(actualData);
      } else {
        if (_receiveBuffer != null) {
          final end = (offset + actualData.length) > _receiveBuffer!.length
              ? _receiveBuffer!.length
              : offset + actualData.length;
          _receiveBuffer!.setRange(offset.toInt(), end, actualData);
        }
      }

      // Calculate transfer speed
      if (_transferStartTime != null) {
        final elapsed = DateTime.now().difference(_transferStartTime!).inMilliseconds;
        if (elapsed > 0) {
          transferSpeed.value = (_totalBytesTransferred * 1000.0) / elapsed; // bytes per second
        }
      }

      final receivedBytes = _receivedBytes.clamp(0, _expectedFileSize);
      transferProgress.value = _expectedFileSize == 0
          ? 0
          : receivedBytes / _expectedFileSize;
      onFileReceiveProgress?.call(
        _expectedFileName ?? 'unknown',
        receivedBytes,
        _expectedFileSize,
      );
      _lastReceiveAt = DateTime.now();
      // Receiver-driven flow control: send an ack every 32 chunks processed
      _chunksSinceAck++;
      if (_chunksSinceAck >= 32) {
        final ack = {'type': 'ack', 'count': _chunksSinceAck};
        _dataChannel?.send(RTCDataChannelMessage(jsonEncode(ack)));
        _chunksSinceAck = 0;
      }
      
      // Auto-complete if all bytes received (in case completion message arrives early or is lost)
      if (_receivedBytes >= _expectedFileSize && _expectedFileSize > 0 && !_isCompleting) {
        AppLogger.i('All bytes received ($_receivedBytes/$_expectedFileSize), completing transfer', tag: 'WebRTC');
        // Trigger completion handling
        _handleFileComplete({});
      }
    } catch (e) {
      AppLogger.e('Failed to handle binary chunk: $e', tag: 'WebRTC');
    }
  }

  /// Handle file completion
  void _handleFileComplete(Map<String, dynamic> data) async {
    if (_expectedFileName == null || _isCompleting) return;

    try {
      _cancelReceiveInactivityWatch();
      
      // Verify all bytes received before completing
      if (_receivedBytes < _expectedFileSize) {
        final missing = _expectedFileSize - _receivedBytes;
        final percentReceived = (_receivedBytes / _expectedFileSize * 100).toStringAsFixed(2);
        AppLogger.w(
          'File completion received but missing $missing bytes ($_receivedBytes/$_expectedFileSize = $percentReceived%)',
          tag: 'WebRTC',
        );
        // Don't complete yet - wait for remaining chunks
        // Set a timeout based on file size (larger files get more time)
        final timeoutSeconds = (_expectedFileSize > 100 * 1024 * 1024) ? 30 : 10; // 30s for files > 100MB
        Future.delayed(Duration(seconds: timeoutSeconds), () {
          if (_receivedBytes < _expectedFileSize && _expectedFileName != null && !_isCompleting) {
            final finalMissing = _expectedFileSize - _receivedBytes;
            final finalPercent = (_receivedBytes / _expectedFileSize * 100).toStringAsFixed(2);
            AppLogger.e(
              'File transfer incomplete after ${timeoutSeconds}s timeout: $_expectedFileName - '
              'Missing $finalMissing bytes ($finalPercent% received)',
              tag: 'WebRTC',
            );
            onFileTransferError?.call(
              _expectedFileName!,
              'Incomplete transfer: received $_receivedBytes of $_expectedFileSize bytes ($finalPercent%)',
              false,
            );
            _expectedFileName = null;
            _expectedFileSize = 0;
            _receivedBytes = 0;
            _receiveBuffer = null;
            _webReceivedParts = null;
            isTransferring.value = false;
            transferSpeed.value = 0.0;
            _isCompleting = false;
          }
        });
        return;
      }
      
      // Mark as completing to prevent duplicate calls
      _isCompleting = true;
      
      String? filePath;
      final isWeb = kIsWeb;
      final bytes = (!isWeb && _receiveBuffer != null)
          ? Uint8List.view(_receiveBuffer!.buffer, 0, _expectedFileSize)
          : Uint8List(0);
      
      if (isWeb) {
        final parts = _webReceivedParts ?? <Uint8List>[];
        final total = _receivedBytes;
        AppLogger.i('File received on web: ${_expectedFileName!}, $total bytes in ${parts.length} parts', tag: 'WebRTC');

        isTransferring.value = false;
        transferProgress.value = 1.0;
        transferSpeed.value = 0.0;

        final id = WebReceivedCache.putParts(_expectedFileName!, parts, total);
        onFileReceiveComplete?.call(_expectedFileName!, 'web-parts:$id');
        // Send final ack for any remaining credit
        if (_chunksSinceAck > 0) {
          final ack = {'type': 'ack', 'count': _chunksSinceAck};
          _dataChannel?.send(RTCDataChannelMessage(jsonEncode(ack)));
          _chunksSinceAck = 0;
        }
      } else {
        // Save file to downloads directory (native platforms)
        final directory = await getApplicationDocumentsDirectory();
        filePath = p.join(directory.path, _expectedFileName!);
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        isTransferring.value = false;
        transferProgress.value = 1.0;
        transferSpeed.value = 0.0;

        // Call callback with file info
        onFileReceiveComplete?.call(_expectedFileName!, filePath);
      }

      NotificationService().showNotification(
        type: NotificationType.fileTransferCompleted,
        title: 'File Received',
        body: 'Successfully received $_expectedFileName via WebRTC',
      );

      if (kIsWeb) {
        AppLogger.i('File received: $_expectedFileName (web download ready)', tag: 'WebRTC');
      } else {
        AppLogger.i('File received and saved: $filePath', tag: 'WebRTC');
      }

      // Reset state
      _expectedFileName = null;
      _expectedFileSize = 0;
      _receivedBytes = 0;
      _receiveBuffer = null;
      _webReceivedParts = null;
      _isCompleting = false;
      _sendCredits = 0; // reset sender credits
    } catch (e) {
      AppLogger.e('Failed to save received file: $e', tag: 'WebRTC');
      isTransferring.value = false;
      _isCompleting = false;
    }
  }

  void _startReceiveInactivityWatch() {
    _cancelReceiveInactivityWatch();
    const threshold = Duration(seconds: 120); // Increased for large files
    _receiveInactivityTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final last = _lastReceiveAt;
      if (!isTransferring.value || last == null) {
        t.cancel();
        return;
      }
      if (DateTime.now().difference(last) > threshold) {
        t.cancel();
        final name = _expectedFileName ?? (currentFileName.value ?? 'unknown');
        onFileTransferError?.call(
            name, 'Receiver stalled: no data for ${threshold.inSeconds}s', false);
        // Reset receive state
        isTransferring.value = false;
        transferProgress.value = 0.0;
        _expectedFileName = null;
        _expectedFileSize = 0;
        _receivedBytes = 0;
        _receiveBuffer = null;
      }
    });
  }

  void _cancelReceiveInactivityWatch() {
    try {
      _receiveInactivityTimer?.cancel();
    } catch (_) {}
    _receiveInactivityTimer = null;
    _lastReceiveAt = null;
  }

  /// Disconnect from signaling server and reset connection
  Future<void> disconnect() async {
    AppLogger.i('Disconnecting WebRTC', tag: 'WebRTC');
    _cancelReceiveInactivityWatch();

    // Close socket connection
    _socket?.disconnect();
    _socket = null;
    _mySocketId = null;
    _roomId = null;
    _connectedPeerSocketId = null;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;

    // Close WebRTC connections
    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _isConnected = false;

    AppLogger.i('WebRTC disconnected', tag: 'WebRTC');
  }

  /// Reset peer connection for new session
  Future<void> resetConnection(String roomId) async {
    AppLogger.i('Resetting WebRTC connection', tag: 'WebRTC');
    await disconnect();
    _isInitialized = false; // Reset initialization state
    // Reinitialize peer connection
    await connectToSignalingServer(roomId);
    AppLogger.i('WebRTC connection reset complete', tag: 'WebRTC');
  }

  /// Dispose resources
  Future<void> dispose() async {
    AppLogger.i('Disposing WebRTC service', tag: 'WebRTC');
    await disconnect();
    AppLogger.i('WebRTC service disposed', tag: 'WebRTC');
  }

  /// Log the currently selected ICE candidate pair to determine route (LAN vs internet)
  Future<void> logSelectedIceRoute() async {
    final pc = _peerConnection;
    if (pc == null) {
      AppLogger.e('Cannot log ICE route: peer connection is null', tag: 'WebRTC');
      return;
    }
    try {
      final stats = await pc.getStats();
      Map<String, dynamic>? selectedPair;
      final candidates = <String, Map<String, dynamic>>{};
      // Collect candidate reports
      for (final report in stats) {
        if (report.type == 'local-candidate' || report.type == 'remote-candidate' || report.type == 'candidate') {
          final mapValues = Map<String, dynamic>.from(report.values);
          candidates[report.id] = mapValues;
        }
      }
      // Find selected pair
      for (final report in stats) {
        if (report.type == 'candidate-pair' && (report.values['selected'] == true || report.values['state'] == 'succeeded')) {
          selectedPair = Map<String, dynamic>.from(report.values);
          break;
        }
      }
      if (selectedPair == null) {
        AppLogger.e('No selected ICE candidate pair found', tag: 'WebRTC');
        return;
      }
      final localId = selectedPair['localCandidateId'];
      final remoteId = selectedPair['remoteCandidateId'];
      final local = candidates[localId] ?? {};
      final remote = candidates[remoteId] ?? {};
      final localAddr = local['ip'] ?? local['address'];
      final remoteAddr = remote['ip'] ?? remote['address'];
      final localType = local['candidateType'];
      final remoteType = remote['candidateType'];
      final isLan = _isPrivateIp('$localAddr') && _isPrivateIp('$remoteAddr');
      AppLogger.i('Selected ICE route => local($localType $localAddr) <-> remote($remoteType $remoteAddr) | LAN: $isLan', tag: 'WebRTC');
    } catch (e) {
      AppLogger.e('Failed to log ICE route: $e', tag: 'WebRTC');
    }
  }

  bool _isPrivateIp(String ip) {
    // Basic RFC1918 + link-local checks
    return ip.startsWith('10.') ||
        ip.startsWith('192.168.') ||
        _startsWith172Private(ip) ||
        ip.startsWith('169.254.') || // link-local
        ip == '::1' || ip.startsWith('fe80:'); // IPv6 loopback/link-local
  }

  bool _startsWith172Private(String ip) {
    // 172.16.0.0 – 172.31.255.255
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }

  /// Reset send transfer state
  void _resetSendState() {
    isTransferring.value = false;
    transferProgress.value = 0.0;
    currentFileName.value = null;
    _currentSendFilePath = null;
    _currentSendFileSize = 0;
    transferSpeed.value = 0.0;
    _transferStartTime = null;
    _totalBytesTransferred = 0;
  }

  /// Ensure the RTCDataChannel is open before attempting to send
  Future<void> _ensureDataChannelOpen({Duration timeout = const Duration(seconds: 10)}) async {
    final dc = _dataChannel;
    if (dc == null) {
      throw Exception('WebRTC data channel not available');
    }
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      if (_dataChannel == null) break; // channel lost
      if (_dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    throw Exception('WebRTC data channel did not open in time');
  }
}
