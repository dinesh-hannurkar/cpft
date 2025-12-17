import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/webshare/services/webrtc_file_transfer_service.dart';
import 'package:cpft/features/webshare/services/webshare_service.dart';
import 'package:cpft/features/webshare/presentation/webrtc_chat_screen.dart';
import 'package:cpft/shared/widgets/primary_app_bar.dart';
import 'package:cpft/features/home/presentation/widgets/buttons/settings_button.dart';
import 'package:cpft/features/settings/presentation/settings_screen.dart';
import 'package:cpft/utils/web_url_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:cpft/shared/showcase/showcase_helper.dart';

class WebRoomEntryScreen extends StatefulWidget {
  const WebRoomEntryScreen({super.key});

  @override
  State<WebRoomEntryScreen> createState() => _WebRoomEntryScreenState();
}

class _WebRoomEntryScreenState extends State<WebRoomEntryScreen> {
  static bool _globalJoinInProgress = false; // Prevent duplicate joins globally
  
  final TextEditingController _roomIdController = TextEditingController();
  late WebRTCFileTransferService _webrtcService;
  WebShareService _webShareService = WebShareService(deviceName: 'WebClient');
  String _deviceName = 'WebClient';
  bool _isJoining = false;
  bool _serviceTransferred = false;
  bool _didAutoRetry = false;
  bool _hasAutoJoined = false; // Prevent duplicate auto-joins
  String? _errorText;
  Timer? _loadingTimeout;

  @override
  void initState() {
    super.initState();
    _webrtcService = WebRTCFileTransferService();
    _loadDeviceName();
    
    // Check for share code from URL parameters
    final roomIdFromUrl = WebUrlUtils.getRoomIdFromUrl();
    if (roomIdFromUrl != null && roomIdFromUrl.isNotEmpty) {
      _roomIdController.text = roomIdFromUrl;
      _hasAutoJoined = true; // Set immediately to prevent any duplicate triggers
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenShowcase = prefs.getBool('web_entry_showcase_seen') ?? false;

      if (!hasSeenShowcase && mounted) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            try {
              ShowcaseHelper.startForWebEntry(context);
              prefs.setBool('web_entry_showcase_seen', true);
            } catch (_) {}
          }
        });
      }
      
      // Auto-join if URL has room parameter (single callback for all initialization)
      if (roomIdFromUrl != null && roomIdFromUrl.isNotEmpty && mounted && !_isJoining) {
        // First set the loading state so user sees the button spinner
        debugPrint('[WebRoomEntry] postFrameCallback: Setting _isJoining=true');
        setState(() {
          _isJoining = true;
        });
        
        // Start timeout immediately
        _loadingTimeout?.cancel();
        _loadingTimeout = Timer(const Duration(seconds: 30), () {
          if (mounted && _isJoining && !_serviceTransferred) {
            debugPrint('[WebRoomEntry] Loading timeout reached (30s), forcing loader to stop');
            setState(() {
              _isJoining = false;
            });
            _globalJoinInProgress = false;
          }
        });
        
        // Wait a bit to ensure the loading UI is visible
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _isJoining && !_serviceTransferred) {
            debugPrint('[WebRoomEntry] Auto-joining room from URL: $roomIdFromUrl');
            _joinWebRTCRoom(roomIdFromUrl);
          }
        });
      }
    });
  }

  Future<void> _loadDeviceName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = (prefs.getString('device_name') ?? '').trim();
      if (name.isNotEmpty && name != _deviceName) {
        setState(() {
          _deviceName = name;
          _webShareService = WebShareService(deviceName: _deviceName);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _roomIdController.dispose();
    _loadingTimeout?.cancel();
    if (!_serviceTransferred) {
      _webrtcService.dispose();
    }
    super.dispose();
  }

  Future<void> _joinWebRTCRoom(String roomId) async {
    debugPrint('[WebRoomEntry] _joinWebRTCRoom called with roomId=$roomId, _isJoining=$_isJoining, _serviceTransferred=$_serviceTransferred, _globalJoinInProgress=$_globalJoinInProgress');
    
    if (_serviceTransferred) {
      debugPrint('[WebRoomEntry] Service already transferred, ignoring duplicate call');
      return;
    }
    if (_globalJoinInProgress && _isJoining) {
      debugPrint('[WebRoomEntry] Global join in progress, ignoring duplicate call');
      return;
    }

    _globalJoinInProgress = true; // Set global lock
    
    // Only set _isJoining if not already set (auto-join may have pre-set it)
    if (!_isJoining) {
      debugPrint('[WebRoomEntry] _joinWebRTCRoom: Setting _isJoining=true');
      setState(() {
        _isJoining = true;
        _errorText = null;
      });
      // Small delay to ensure loading UI is rendered before navigation
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Set a 30 second timeout to auto-stop the loader
    _loadingTimeout?.cancel();
    _loadingTimeout = Timer(const Duration(seconds: 30), () {
      if (mounted && _isJoining && !_serviceTransferred) {
        debugPrint('[WebRoomEntry] Loading timeout reached (30s), forcing loader to stop');
        setState(() {
          _isJoining = false;
        });
        _globalJoinInProgress = false;
      }
    });

    try {
      debugPrint('[WebRoomEntry] Attempting to connect to signaling server: $roomId');
      await _webrtcService.connectToSignalingServer(roomId);
      debugPrint('[WebRoomEntry] Successfully connected to signaling server');
      if (!mounted) {
        debugPrint('[WebRoomEntry] Widget unmounted after connection, cleaning up');
        _globalJoinInProgress = false;
        _loadingTimeout?.cancel();
        return;
      }
      
      // Cancel the timeout since connection was successful
      _loadingTimeout?.cancel();
      
      // Update URL to include room parameter for web sharing
      // WebUrlUtils.updateUrlWithRoomId(roomId);
      
      _serviceTransferred = true; // Mark service as transferred
      
      debugPrint('[WebRoomEntry] Opening chat screen for room: $roomId');
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => WebRTCChatScreen(
            webrtcService: _webrtcService,
            webShareService: _webShareService,
            roomId: roomId,
            deviceName: null,
            disposeServiceOnClose: true,
            onDisconnect: () {
              Navigator.of(context).pop();
            },
          ),
        ),
      );
      // After returning from chat, reset local state and reinitialize service
      if (mounted) {
        debugPrint('[WebRoomEntry] Returned from chat screen, resetting state');
        _globalJoinInProgress = false; // Release global lock
        _loadingTimeout?.cancel();
        setState(() {
          _isJoining = false;
          _didAutoRetry = false;
          _hasAutoJoined = false; // Reset for potential re-join
          _serviceTransferred = false;
          _webrtcService = WebRTCFileTransferService();
        });
      }
    } catch (e) {
      debugPrint('[WebRoomEntry] Error in _joinWebRTCRoom: $e');
      _globalJoinInProgress = false; // Release global lock on error
      _loadingTimeout?.cancel();
      // Prepare friendly error message for missing codes (web is join-only)
      final message = e.toString();
      final friendly = message.contains('not found')
          ? 'Code not found or expired. Start Link Share from the mobile app and try again.'
          : 'Failed to join: $message';
      if (mounted) {
        debugPrint('[WebRoomEntry] First error: Setting _isJoining=false');
        setState(() {
          _errorText = friendly;
          _isJoining = false; // Stop loading on first error
        });
      } else {
        debugPrint('[WebRoomEntry] Widget unmounted, cannot update error state');
        return;
      }
      // One-shot auto-retry on failure
      if (!_didAutoRetry) {
        _didAutoRetry = true;
        
        // Wait a moment to show the error before retrying
        await Future.delayed(const Duration(milliseconds: 1500));
        
        if (mounted) {
          debugPrint('[WebRoomEntry] Before retry: Setting _isJoining=true');
          setState(() {
            _isJoining = true; // Show loading again for retry
            _errorText = null; // Clear error during retry
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Joining failed. Refreshing and retrying…',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        try {
          debugPrint('[WebRoomEntry] Retry attempt for room: $roomId');
          _webrtcService.disconnect();
          await Future.delayed(const Duration(milliseconds: 300));
          await _webrtcService.connectToSignalingServer(roomId);
          if (!mounted) return;
          
          // Update URL to include room parameter for web sharing
          // WebUrlUtils.updateUrlWithRoomId(roomId);
          
          _serviceTransferred = true;
          
          debugPrint('[WebRoomEntry] Opening chat screen from retry for room: $roomId');
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => WebRTCChatScreen(
                webrtcService: _webrtcService,
                webShareService: _webShareService,
                roomId: roomId,
                deviceName: null,
                disposeServiceOnClose: true,
                onDisconnect: () => Navigator.of(context).pop(),
              ),
            ),
          );
          // After returning from chat, reset local state and reinitialize service
          if (mounted) {
            debugPrint('[WebRoomEntry] Returned from retry chat screen, resetting state');
            _globalJoinInProgress = false; // Release global lock
            setState(() {
              _isJoining = false;
              _didAutoRetry = false;
              _hasAutoJoined = false; // Reset for potential re-join
              _serviceTransferred = false;
              _webrtcService = WebRTCFileTransferService();
            });
          }
          return; // Exit successfully after retry
        } catch (e2) {
          debugPrint('[WebRoomEntry] Retry also failed: $e2');
          _globalJoinInProgress = false; // Release global lock on retry error
          if (mounted) {
            debugPrint('[WebRoomEntry] Retry failed: Setting _isJoining=false');
            setState(() {
              _isJoining = false; // Stop loading on retry failure
            });
          }
          // fall through to show final failure
        }
      }
      if (mounted) {
        debugPrint('[WebRoomEntry] Showing final error snackbar');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendly,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
        _globalJoinInProgress = false; // Release global lock on final error
        debugPrint('[WebRoomEntry] Final error: Setting _isJoining=false');
        setState(() {
          _isJoining = false;
        });
      }
    } finally {
      // Ensure loading state is always cleaned up
      // Only skip cleanup if service was successfully transferred to chat screen
      if (_isJoining && !_serviceTransferred) {
        debugPrint('[WebRoomEntry] Finally block: Cleaning up loading state (_isJoining=$_isJoining, _serviceTransferred=$_serviceTransferred)');
        if (mounted) {
          debugPrint('[WebRoomEntry] Finally block: Setting _isJoining=false');
          setState(() {
            _isJoining = false;
          });
        }
        _globalJoinInProgress = false;
      } else {
        debugPrint('[WebRoomEntry] Finally block: No cleanup needed (_isJoining=$_isJoining, _serviceTransferred=$_serviceTransferred)');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          !kIsWeb, // On web, prevent back navigation since this is the home page
      child: ShowCaseWidget(
        builder: (context) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: PrimaryAppBar(
            titleWidget: GestureDetector(
              onTap: () {
                if (kIsWeb) {
                  // Navigate to home by popping all routes and going to root
                  Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(left: AppSizes.sm),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(
                    'CPFT',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
            centerTitle: false,
            trailing: [
              Showcase(
                key: ShowcaseHelper.settingsIconKey,
                disableBarrierInteraction: false,
                targetPadding: const EdgeInsets.all(8),
                title: 'Settings',
                description: 'Change your device name and app preferences.',
                tooltipBackgroundColor: Colors.white,
                textColor: Colors.black,
                descTextStyle: const TextStyle(
                  fontSize: 12,
                  color: Colors.black87,
                ),
                titleTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontSize: 16,
                ),
                tooltipBorderRadius: BorderRadius.circular(12),
                targetBorderRadius: BorderRadius.circular(12),
                child: AppIconButton(
                  onPressed: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SettingsScreen(currentDeviceName: _deviceName),
                          ),
                        )
                        .then((_) => _loadDeviceName());
                  },
                  icon: Icons.settings,
                ),
              ),
              AppIconButton(
                onPressed: () {
                  try {
                    ShowcaseHelper.startForWebEntry(context);
                  } catch (_) {}
                },
                icon: Icons.help_outline,
              ),
            ],
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
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSizes.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Container(
                      padding: const EdgeInsets.all(AppSizes.lg),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Tip helper moved to class scope
                          Row(
                            children: const [
                              Icon(Icons.link, color: AppColors.primary),
                              SizedBox(width: AppSizes.sm),
                              Text(
                                'Join with Code',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSizes.sm),
                          const Text(
                            'Enter a code to join an existing session and start sharing files directly between devices.',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: AppSizes.md),
                          if (_errorText != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppSizes.md),
                              margin: const EdgeInsets.only(
                                bottom: AppSizes.sm,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red.shade700,
                                  ),
                                  const SizedBox(width: AppSizes.sm),
                                  Expanded(
                                    child: Text(
                                      _errorText!,
                                      style: TextStyle(
                                        color: Colors.red.shade800,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        setState(() => _errorText = null),
                                    icon: const Icon(Icons.close),
                                    color: Colors.red.shade700,
                                    tooltip: 'Dismiss',
                                  ),
                                ],
                              ),
                            ),
                          ],
                          Showcase(
                            key: ShowcaseHelper.joinCodeFieldKey,
                            disableBarrierInteraction: false,
                            targetPadding: const EdgeInsets.all(8),
                            title: 'Join Code',
                            description:
                                'Enter the code you received to join the session.',
                            tooltipBackgroundColor: Colors.white,
                            textColor: Colors.black,
                            descTextStyle: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                            titleTextStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontSize: 16,
                            ),
                            tooltipBorderRadius: BorderRadius.circular(12),
                            targetBorderRadius: BorderRadius.circular(12),
                            child: TextField(
                              controller: _roomIdController,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Code',
                                hintText: 'Enter code (e.g., ABC123)',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                prefixIcon: const Icon(
                                  Icons.key,
                                  color: AppColors.primary,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSizes.md,
                                  vertical: AppSizes.sm * 1.5,
                                ),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              enabled: !_isJoining,
                              onSubmitted: (_) {
                                final roomId = _roomIdController.text.trim();
                                if (roomId.isNotEmpty) {
                                  _joinWebRTCRoom(roomId);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: AppSizes.md),
                          Showcase(
                            key: ShowcaseHelper.joinButtonKey,
                            disableBarrierInteraction: false,
                            targetPadding: const EdgeInsets.all(8),
                            title: 'Join',
                            description:
                                'Tap to join your session using the code.',
                            tooltipBackgroundColor: Colors.white,
                            textColor: Colors.black,
                            descTextStyle: const TextStyle(
                              fontSize: AppSizes.sm * 1.5,
                              color: Colors.black87,
                            ),
                            titleTextStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontSize: AppSizes.md,
                            ),
                            tooltipBorderRadius: BorderRadius.circular(12),
                            targetBorderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _isJoining
                                    ? null
                                    : () {
                                        final roomId = _roomIdController.text
                                            .trim();
                                        if (roomId.isNotEmpty) {
                                          _joinWebRTCRoom(roomId);
                                        } else {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Please enter a code',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                icon: _isJoining
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Icon(Icons.login, size: 22),
                                label: Text(
                                  _isJoining ? 'Joining…' : 'Join',
                                  style: const TextStyle(
                                    fontSize: AppSizes.md,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSizes.md),
                          Container(
                            padding: const EdgeInsets.all(AppSizes.md),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: AppSizes.sm),
                                Expanded(
                                  child: Text(
                                    'Ensure both devices are on the same Wi‑Fi or Personal Hotspot.',
                                    style: TextStyle(
                                      fontSize: AppSizes.sm * 1.5,
                                      color: AppColors.primary,
                                      height: 1.4,
                                    ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
