import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/webshare/presentation/widgets/network_indicator.dart';
import 'package:cpft/features/webshare/services/webrtc_file_transfer_service.dart';
import 'package:cpft/utils/network_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cpft/features/webshare/services/html_stub.dart'
    if (dart.library.html) 'dart:html'
    as html;
import 'package:cpft/features/webshare/services/webshare_service.dart';
import 'package:cpft/features/webshare/presentation/webrtc_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cpft/utils/web_url_utils.dart';

/// WebRTC Connection Bottom Sheet
class WebRTCConnectionBottomSheet extends StatefulWidget {
  final WebRTCFileTransferService webrtcService;
  final VoidCallback onConnected;
  final Function(String) onError;
  final WebShareService? webShareService;
  final String? roomId;
  final VoidCallback? onDisconnect;
  final String? deviceName;

  const WebRTCConnectionBottomSheet({
    super.key,
    required this.webrtcService,
    required this.onConnected,
    required this.onError,
    this.webShareService,
    this.roomId,
    this.onDisconnect,
    this.deviceName,
  });

  @override
  State<WebRTCConnectionBottomSheet> createState() =>
      _WebRTCConnectionBottomSheetState();
}

class _WebRTCConnectionBottomSheetState
    extends State<WebRTCConnectionBottomSheet> {
  final TextEditingController _peerIdController = TextEditingController();
  bool _isConnecting = false;
  bool _hasJoinedRoom = false;
  bool _isDiscovering = false;
  bool _isStartingWebSharing = false;
  bool _didAutoRetry = false;
  bool _codeExpired = false;
  String? _currentRoomId;
  String? _networkName;
  String? _detectedHostIp;
  String? _urlRoomId;

  @override
  void initState() {
    super.initState();
    _checkNetworkStatus();
    _extractRoomIdFromUrl();
    // After connection is established, send our device name to the peer.
    widget.webrtcService.connectionEstablished.addListener(
      _sendNameIfConnected,
    );
  }

  void _sendNameIfConnected() async {
    try {
      if (widget.webrtcService.connectionEstablished.value != true) return;
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString('device_name') ?? '').trim();
      final fallback = (widget.deviceName ?? '').trim();
      String localName = saved.isNotEmpty ? saved : fallback;
      // If still empty, use a default based on platform
      if (localName.isEmpty) {
        localName = kIsWeb ? 'Web User' : 'Mobile User';
      }
      if (localName.isEmpty) return;
      final message = 'peer-info: $localName';
      widget.webrtcService.sendTextMessage(message);
      // Retry shortly once for reliability
      Future.delayed(const Duration(milliseconds: 400), () {
        try {
          widget.webrtcService.sendTextMessage(message);
        } catch (_) {}
      });
      // Remove listener after first successful send to avoid duplicates on reconnections
      widget.webrtcService.connectionEstablished.removeListener(
        _sendNameIfConnected,
      );
    } catch (_) {}
  }

  Future<void> _checkNetworkStatus() async {
    try {
      final networkName = await NetworkUtils.getWifiName();
      if (mounted) {
        setState(() {
          _networkName = networkName;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _networkName = 'Not Connected';
        });
      }
    }
  }

  void _extractRoomIdFromUrl() {
    if (kIsWeb) {
      final uri = Uri.parse(html.window.location.href);
      final roomId = uri.queryParameters['room'];
      if (roomId != null && roomId.isNotEmpty) {
        // Ensure web is in remote signaling mode and join mode
        widget.webrtcService.setSignalingMode(useLocal: false);
        widget.webrtcService.setHostMode(false);
        setState(() {
          _urlRoomId = roomId;
          _peerIdController.text = roomId;
        });
        // Auto-connect after a delay to ensure service is ready
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            // Ensure clean state before auto-connecting
            widget.webrtcService.disconnect();
            _connectToPeer();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _peerIdController.dispose();
    // Clean up connection listener if still attached
    try {
      widget.webrtcService.connectionEstablished.removeListener(
        _sendNameIfConnected,
      );
    } catch (_) {}
    super.dispose();
  }

  Future<void> _connectToPeer() async {
    // Check if local mode and if host
    final isLocal = widget.webrtcService.isLocalMode.value;
    final isHost = widget.webrtcService.isHostMode.value;

    // For host mode, room ID is auto-generated. For join mode, need manual entry.
    String roomId;
    if (isHost && isLocal) {
      // Host: room ID will be generated automatically with port
      roomId = ''; // Will be generated by startLocalHostAndConnect
    } else {
      // Join or remote mode: need code from user
      roomId = _peerIdController.text.trim();
      if (roomId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enter a code',
              style: TextStyle(color: Colors.red),
            ),
          ),
        );
        return;
      }

      // On web: auto-switch to local signaling if code encodes port (e.g., 1234-192-p8081)
      if (kIsWeb && !isLocal && RegExp(r"-p\d+").hasMatch(roomId)) {
        widget.webrtcService.setSignalingMode(useLocal: true);
        widget.webrtcService.setHostMode(false); // web cannot host local WS
      }
    }

    setState(() {
      _isConnecting = true;
      _currentRoomId = roomId;
    });

    try {
      setState(() {
        _isDiscovering = !isHost && isLocal; // Show discovery for join mode
      });

      if (isLocal) {
        if (isHost) {
          // Start as host and get generated room ID with port
          final generatedRoomId = await widget.webrtcService
              .startLocalHostAndConnect();
          if (mounted && generatedRoomId != null) {
            setState(() {
              _detectedHostIp = generatedRoomId; // Store the room ID
              _currentRoomId = generatedRoomId;
              _peerIdController.text = generatedRoomId; // Show in UI
              _isDiscovering = false;
            });
          }
        } else {
          // Join as client - automatic discovery with port extraction!
          await widget.webrtcService.connectToSignalingServer(roomId);
          if (mounted) {
            setState(() {
              _isDiscovering = false;
            });
          }
        }
      } else {
        // Use remote Socket.IO signaling
        await widget.webrtcService.connectToSignalingServer(roomId);
      }

      if (mounted) {
        setState(() {
          _hasJoinedRoom = true;
          _isConnecting = false;
          _isDiscovering = false;
        });
      }
      // Don't close dialog yet - wait for actual peer connection
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _hasJoinedRoom = false;
          _isDiscovering = false;
          // Detect expired/missing code
          final msg = e.toString().toLowerCase();
          _codeExpired = msg.contains('not found') || msg.contains('expired');
        });
      }

      // One-shot auto-retry: refresh signaling and try again
      if (!_didAutoRetry) {
        _didAutoRetry = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Connection failed. Refreshing and retrying…',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          setState(() => _isConnecting = true);
        }
        try {
          // Ensure clean state then retry
          widget.webrtcService.disconnect();
          await Future.delayed(const Duration(milliseconds: 300));
          await widget.webrtcService.connectToSignalingServer(
            _currentRoomId ?? '',
          );
          if (mounted) {
            setState(() {
              _hasJoinedRoom = true;
              _isConnecting = false;
            });
          }
          return; // success after retry
        } catch (e2) {
          // Fall through to normal error handling below
        } finally {
          if (mounted) setState(() => _isConnecting = false);
        }
      }

      // For auto-connect from URL, show error but allow manual retry
      final msg = e.toString();
      final friendly = (msg.contains('Room') && msg.contains('not found'))
          ? 'Code expired. Recreate a new code from mobile and try again.'
          : 'Auto-connect failed: $msg';
      if (_urlRoomId != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendly,
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(label: 'Retry', onPressed: _connectToPeer),
            ),
          );
        }
      } else {
        widget.onError(friendly);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: AppSizes.spaceBtwInputFields * 0.5),
            // Network status - simple one-line format like home screen
            NetworkIndicator(networkName: _networkName),

            const SizedBox(height: AppSizes.spaceBtwItems),
            // Clear instruction about network requirements
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSizes.xs * 0.4),
                  child: const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.red,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ensure both devices are on the same Wi‑Fi or Personal Hotspot network for the fastest and most reliable connection.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),

            // Discovery status (for join mode)
            if (_isDiscovering) ...[
              _buildStatusIndicator(
                icon: Icons.search,
                text: 'Finding Host',
                status: 'Scanning local network for host...',
                isComplete: false,
                color: Colors.blue,
                isLoading: true,
              ),
              const SizedBox(height: 12),
            ],
            // Step 2: Room Input/Joined
            if (!_hasJoinedRoom) ...[
              if (kIsWeb) ...[
                // Web: Show different UI based on URL room ID
                if (_urlRoomId != null) ...[
                  // Auto-joining with URL room ID
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isConnecting
                          ? Colors.blue.shade50
                          : (_hasJoinedRoom
                                ? Colors.green.shade50
                                : Colors.red.shade50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isConnecting
                            ? Colors.blue.shade200
                            : (_hasJoinedRoom
                                  ? Colors.green.shade200
                                  : Colors.red.shade200),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            if (_isConnecting) ...[
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.blue,
                                  ),
                                ),
                              ),
                            ] else if (_hasJoinedRoom) ...[
                              Icon(
                                Icons.check_circle,
                                color: Colors.green.shade600,
                                size: 24,
                              ),
                            ] else ...[
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade600,
                                size: 24,
                              ),
                            ],
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isConnecting
                                        ? 'Connecting'
                                        : (_hasJoinedRoom
                                              ? 'Connected'
                                              : 'Connection Failed'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: _isConnecting
                                          ? Colors.blue.shade900
                                          : (_hasJoinedRoom
                                                ? Colors.green.shade900
                                                : Colors.red.shade900),
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _isConnecting
                                        ? 'Automatically connecting using $_urlRoomId...'
                                        : (_hasJoinedRoom
                                              ? 'Connected using $_urlRoomId'
                                              : 'Failed to join with code $_urlRoomId. Tap retry to try again.'),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: _isConnecting
                                          ? Colors.blue.shade700
                                          : (_hasJoinedRoom
                                                ? Colors.green.shade700
                                                : Colors.red.shade700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!_isConnecting && !_hasJoinedRoom) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: ElevatedButton.icon(
                              onPressed: _connectToPeer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Retry Connection'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  // Manual code input
                  const Text(
                    'Enter a code to join the sharing session:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _peerIdController,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Enter code (e.g., "1234")',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      prefixIcon: const Icon(
                        Icons.meeting_room,
                        color: AppColors.primary,
                      ),
                      helperText: 'Enter the code shared by the other device',
                      helperStyle: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    enabled: !_isConnecting,
                    onSubmitted: (_) => _connectToPeer(),
                  ),
                ],
              ] else ...[
                // Mobile: Only show web sharing option
                const Text(
                  'Start a new sharing session that web browsers can join:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
              if (!kIsWeb) ...[
                // Mobile: Show QR code preview for web sharing
                if (_currentRoomId == null) ...[
                  // Show preview QR code with start button overlay
                  GestureDetector(
                    onTap: _isConnecting
                        ? null
                        : () async {
                            setState(() {
                              _isConnecting = true;
                              _isStartingWebSharing = true;
                            });
                            try {
                              // Ensure Firestore (remote) signaling for web sharing
                              widget.webrtcService.setSignalingMode(
                                useLocal: false,
                              );
                              widget.webrtcService.setHostMode(false);
                              final id = await widget.webrtcService
                                  .createAutoRoomAndConnect(
                                    length: 4,
                                    alphanumeric: false,
                                  );
                              if (!mounted) return;
                              setState(() {
                                _peerIdController.text = id;
                                _currentRoomId = id;
                                _hasJoinedRoom = true;
                                _isConnecting = false;
                                _isStartingWebSharing = false;
                              });
                            } catch (e) {
                              if (!mounted) return;
                              setState(() {
                                _isConnecting = false;
                                _isStartingWebSharing = false;
                              });
                              widget.onError(e.toString());
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Failed to start web sharing: $e',
                                  ),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSizes.lg * 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Blurred placeholder QR code
                          QrImageView(
                            data: WebUrlUtils.shareUrlForRoom('0000'),
                            version: QrVersions.auto,
                            size: 250,
                            backgroundColor: AppColors.white,
                            foregroundColor: AppColors.darkPrimary,
                          ),
                          // Semi-transparent overlay
                          Container(
                            // width: 250,
                            height: 250,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          // Content based on loading state
                          if (_isConnecting && _isStartingWebSharing) ...[
                            // Loading state
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                            ),
                          ] else ...[
                            // Start Web Sharing content
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.wifi_tethering,
                                  size: 48,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Start Web Sharing',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap to create sharing session',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16), // bottom spacing
              if (kIsWeb && _urlRoomId == null) ...[
                // Web: Show join button (only when not auto-joining from URL)
                ValueListenableBuilder<bool>(
                  valueListenable: widget.webrtcService.isHostMode,
                  builder: (context, isHost, _) {
                    return SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isConnecting ? null : _connectToPeer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: _isConnecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Icon(
                                isHost ? Icons.router : Icons.link,
                                size: 24,
                              ),
                        label: Text(
                          _isConnecting
                              ? (isHost ? 'Starting Server...' : 'Joining...')
                              : (isHost ? 'Start Hosting' : 'Join'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ] else ...[
              // Show different UI based on platform after joining
              if (!kIsWeb && _currentRoomId != null) ...[
                // Mobile: Show QR code for web sharing
                SizedBox(height: AppSizes.lg),
                const Text(
                  'Web Sharing Active!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  'Scan this QR code to join the sharing.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSizes.lg),
                Container(
                  padding: const EdgeInsets.only(
                    top: AppSizes.lg * 2,
                    bottom: AppSizes.lg,
                    left: AppSizes.lg * 2,
                    right: AppSizes.lg * 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QrImageView(
                        data: WebUrlUtils.shareUrlForRoom(_currentRoomId ?? ''),
                        version: QrVersions.auto,
                        size: 250,
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      SizedBox(height: AppSizes.md),
                      Text(
                        'Joining Code: $_currentRoomId',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        WebUrlUtils.shareUrlForRoom(_currentRoomId ?? ''),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_codeExpired) ...[
                        const SizedBox(height: AppSizes.md),
                        const Text(
                          'Code expired. Create a new code to continue.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSizes.sm),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Recreate Code'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              try {
                                setState(() => _isStartingWebSharing = true);
                                // Ensure remote signaling and allow host mode on mobile
                                widget.webrtcService.setSignalingMode(
                                  useLocal: false,
                                );
                                widget.webrtcService.setHostMode(false);
                                final newId = await widget.webrtcService
                                    .createAutoRoomAndConnect();
                                if (mounted) {
                                  setState(() {
                                    _currentRoomId = newId;
                                    _codeExpired = false;
                                    _isStartingWebSharing = false;
                                  });
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _isStartingWebSharing = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Failed to recreate code: $e',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                // Web: Show regular joined status
                _buildStatusIndicator(
                  icon: Icons.meeting_room,
                  text: 'Connected',
                  status: '$_currentRoomId',
                  isComplete: true,
                  color: Colors.green,
                ),
              ],
              const SizedBox(height: 12),
              // Show generated code if in local host mode
              if (_detectedHostIp != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    border: Border.all(color: Colors.purple.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.share,
                            color: Colors.purple.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Share This Code',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Other devices on the same WiFi can join using this code:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.purple.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.purple.shade200,
                                ),
                              ),
                              child: SelectableText(
                                _detectedHostIp!,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.blackDark,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              // Copy to clipboard
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'IP copied to clipboard',
                                    style: TextStyle(color: Colors.black),
                                  ),
                                ),
                              );
                            },
                            tooltip: 'Copy IP',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Step 3: Waiting for peer / Connected
              ValueListenableBuilder<bool>(
                valueListenable: widget.webrtcService.connectionEstablished,
                builder: (context, isConnected, _) {
                  if (isConnected) {
                    // Auto-close dialog after showing success
                    Future.delayed(const Duration(milliseconds: 1500), () {
                      if (mounted) {
                        widget.onConnected();
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WebRTCChatScreen(
                              webrtcService: widget.webrtcService,
                              webShareService: widget.webShareService,
                              roomId:
                                  widget.roomId ??
                                  widget.webrtcService.roomId ??
                                  'unknown',
                              deviceName: widget.deviceName,
                              disposeServiceOnClose: false,
                              onDisconnect:
                                  widget.onDisconnect ??
                                  () => Navigator.pop(context),
                            ),
                          ),
                        );
                      }
                    });
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatusIndicator(
                        icon: isConnected
                            ? Icons.check_circle
                            : Icons.hourglass_empty,
                        text: isConnected
                            ? 'Connected & Ready'
                            : 'Waiting for Connection',
                        status: isConnected
                            ? 'You can now send files to your peer'
                            : 'Enter the same code on the other device',
                        isComplete: isConnected,
                        color: isConnected ? Colors.green : Colors.blue,
                        isLoading: !isConnected,
                      ),
                      if (isConnected) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WebRTCChatScreen(
                                    webrtcService: widget.webrtcService,
                                    webShareService: widget.webShareService,
                                    roomId:
                                        widget.roomId ??
                                        widget.webrtcService.roomId ??
                                        'unknown',
                                    deviceName: widget.deviceName,
                                    disposeServiceOnClose: false,
                                    onDisconnect:
                                        widget.onDisconnect ??
                                        () => Navigator.pop(context),
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.chat, size: 24),
                            label: const Text(
                              'Go to Chat',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator({
    required IconData icon,
    required String text,
    required String status,
    required bool isComplete,
    required Color color,
    bool isLoading = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          if (isComplete) Icon(Icons.check, color: color, size: 20),
        ],
      ),
    );
  }
}
