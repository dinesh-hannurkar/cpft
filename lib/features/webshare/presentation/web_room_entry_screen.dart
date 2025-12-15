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
  final TextEditingController _roomIdController = TextEditingController();
  late WebRTCFileTransferService _webrtcService;
  WebShareService _webShareService = WebShareService(deviceName: 'WebClient');
  String _deviceName = 'WebClient';
  bool _isJoining = false;
  bool _serviceTransferred = false;
  bool _didAutoRetry = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _webrtcService = WebRTCFileTransferService();
    _loadDeviceName();
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
    });

    // Check for share code from URL parameters
    final roomIdFromUrl = WebUrlUtils.getRoomIdFromUrl();
    if (roomIdFromUrl != null && roomIdFromUrl.isNotEmpty) {
      _roomIdController.text = roomIdFromUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _joinWebRTCRoom(roomIdFromUrl);
          }
        });
      });
    }
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
    if (!_serviceTransferred) {
      _webrtcService.dispose();
    }
    super.dispose();
  }

  Future<void> _joinWebRTCRoom(String roomId) async {
    if (_isJoining) return;

    setState(() {
      _isJoining = true;
      _errorText = null;
    });

    try {
      await _webrtcService.connectToSignalingServer(roomId);
      if (!mounted) return;
      _serviceTransferred = true; // Mark service as transferred
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
        setState(() {
          _isJoining = false;
          _didAutoRetry = false;
          _serviceTransferred = false;
          _webrtcService = WebRTCFileTransferService();
        });
      }
    } catch (e) {
      // Prepare friendly error message for missing codes (web is join-only)
      final message = e.toString();
      final friendly = message.contains('not found')
          ? 'Code not found or expired. Start Link Share from the mobile app and try again.'
          : 'Failed to join: $message';
      if (mounted) {
        setState(() {
          _errorText = friendly;
        });
      }
      // One-shot auto-retry on failure
      if (!_didAutoRetry) {
        _didAutoRetry = true;
        if (mounted) {
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
          _webrtcService.disconnect();
          await Future.delayed(const Duration(milliseconds: 300));
          await _webrtcService.connectToSignalingServer(roomId);
          if (!mounted) return;
          _serviceTransferred = true;
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
            setState(() {
              _isJoining = false;
              _didAutoRetry = false;
              _serviceTransferred = false;
              _webrtcService = WebRTCFileTransferService();
            });
          }
          return;
        } catch (e2) {
          // fall through to show final failure
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendly,
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
    return PopScope(
      canPop:
          !kIsWeb, // On web, prevent back navigation since this is the home page
      child: ShowCaseWidget(
        builder: (context) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: PrimaryAppBar(
            titleWidget: const Padding(
              padding: EdgeInsets.only(left: AppSizes.sm),
              child: Text(
                'CPFT',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
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
