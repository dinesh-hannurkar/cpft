import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/webshare/services/webrtc_file_transfer_service.dart';
import 'package:cpft/features/webshare/services/webshare_service.dart';
import 'package:cpft/features/webshare/presentation/webrtc_chat_screen.dart';
import 'package:cpft/shared/widgets/primary_app_bar.dart';
import 'package:cpft/utils/web_url_utils.dart';

/// Web-only screen for entering WebRTC room IDs and handling URL parameters
class WebRoomEntryScreen extends StatefulWidget {
  const WebRoomEntryScreen({super.key});

  @override
  State<WebRoomEntryScreen> createState() => _WebRoomEntryScreenState();
}

class _WebRoomEntryScreenState extends State<WebRoomEntryScreen> {
  final TextEditingController _roomIdController = TextEditingController();
  final WebRTCFileTransferService _webrtcService = WebRTCFileTransferService();
  final WebShareService _webShareService = WebShareService(deviceName: 'WebClient');
  bool _isJoining = false;
  bool _serviceTransferred = false;

  @override
  void initState() {
    super.initState();

    // Check for room ID from URL parameters
    final roomIdFromUrl = WebUrlUtils.getRoomIdFromUrl();
    if (roomIdFromUrl != null && roomIdFromUrl.isNotEmpty) {
      _roomIdController.text = roomIdFromUrl;
      // Auto-join the room after a short delay to allow UI to build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _joinWebRTCRoom(roomIdFromUrl);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _roomIdController.dispose();
    // Only dispose WebRTC service if it wasn't transferred to chat screen
    if (!_serviceTransferred) {
      _webrtcService.dispose();
    }
    super.dispose();
  }

  Future<void> _joinWebRTCRoom(String roomId) async {
    if (_isJoining) return;

    setState(() {
      _isJoining = true;
    });

    try {
      // Connect to signaling server
      await _webrtcService.connectToSignalingServer(roomId);

      // Navigate to WebRTC chat screen
      if (!mounted) return;
      _serviceTransferred = true; // Mark service as transferred
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => WebRTCChatScreen(
            webrtcService: _webrtcService,
            webShareService: _webShareService,
            roomId: roomId,
            deviceName: null,
            onDisconnect: () {
              // Go back to room entry screen
              Navigator.of(context).pop();
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to join room: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PrimaryAppBar(
        titleWidget: const Padding(
          padding: EdgeInsets.only(left: AppSizes.sm),
          child: Text(
            'WebRTC File Transfer',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
        centerTitle: false,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE2F6FB), Color(0xFFFFFFFF)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Join WebRTC Room',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                const Text(
                  'Enter a room ID to join an existing WebRTC session, or get a room ID from someone else to share files.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: AppSizes.xl),
                TextField(
                  controller: _roomIdController,
                  decoration: InputDecoration(
                    labelText: 'Room ID',
                    hintText: 'Enter room ID (e.g., ABC123)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.meeting_room),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  enabled: !_isJoining,
                ),
                const SizedBox(height: AppSizes.lg),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isJoining
                        ? null
                        : () {
                            final roomId = _roomIdController.text.trim();
                            if (roomId.isNotEmpty) {
                              _joinWebRTCRoom(roomId);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isJoining
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Join Room',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: AppSizes.xl),
                Container(
                  padding: const EdgeInsets.all(AppSizes.md),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: AppSizes.sm),
                          Text(
                            'How it works',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSizes.sm),
                      Text(
                        '• Share the room ID with others to let them join\n'
                        '• Files are transferred directly between devices\n'
                        '• No files are stored on servers\n'
                        '• Works best on the same local network',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue.shade800,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}