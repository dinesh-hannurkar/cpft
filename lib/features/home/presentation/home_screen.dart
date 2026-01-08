import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:fylooo/core/logging/app_logger.dart';
import 'package:fylooo/features/home/presentation/widgets/buttons/link_share_button.dart';
import 'package:fylooo/features/home/presentation/widgets/sheets/ios_hotspot_instruction_sheet.dart';
import 'package:fylooo/features/home/presentation/widgets/sheets/connected_devices_sheet.dart';
import 'package:fylooo/features/home/presentation/widgets/sheets/incoming_request_dialog.dart';
import 'package:fylooo/features/webshare/presentation/widgets/web_rtc_connection_bottomsheet.dart';
import 'package:fylooo/models/hotspot_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fylooo/core/constants/app_colors.dart';
import 'package:fylooo/core/constants/app_sizes.dart';
import 'package:fylooo/features/home/helpers/device_position.dart';
import 'package:fylooo/features/home/helpers/device_dot_layout_helper.dart';
import 'package:fylooo/features/home/helpers/connection_handler.dart';
import 'package:fylooo/features/home/helpers/service_restart_handler.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';
import 'package:fylooo/services/discovery_service.dart';
import 'package:fylooo/utils/network_utils.dart';
import 'package:fylooo/utils/permissions.dart';
import 'package:fylooo/services/hotspot_service.dart';
import 'package:fylooo/services/wifi_service.dart';
import 'package:fylooo/features/home/controllers/home_controller.dart';
import 'package:fylooo/features/home/presentation/widgets/radar_view.dart';
import 'package:fylooo/features/home/presentation/widgets/device_dot.dart';
import 'package:fylooo/features/home/presentation/widgets/network_banner.dart';

import 'package:fylooo/features/home/presentation/widgets/home_app_bar.dart';

import 'package:fylooo/shared/widgets/dialog_helpers.dart' as app_dialog;
import 'package:fylooo/shared/widgets/app_bottom_sheet.dart';
import 'package:fylooo/shared/widgets/app_confirm_dialog.dart';
import 'package:fylooo/shared/widgets/shared_content_banner.dart';
import 'package:fylooo/shared/widgets/drag_overlay.dart';
import 'package:fylooo/features/chat/presentation/chat_screen.dart';
import 'package:fylooo/features/webshare/services/webrtc_file_transfer_service.dart';
import 'package:fylooo/features/webshare/services/webshare_service.dart';
import 'package:fylooo/features/qr_scanner/presentation/qr_scanner_screen.dart';
import 'package:fylooo/features/chat/services/connection_service.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:fylooo/shared/showcase/showcase_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatefulWidget {
  final DiscoveryService discoveryService;
  final String myDeviceName;

  const HomeScreen({
    super.key,
    required this.discoveryService,
    required this.myDeviceName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late HomeController controller;
  String? _networkName;
  bool _autoHotspotEnabled =
      false; // Disabled auto-start, user must manually start hotspot
  bool _hotspotStarting = false;
  HotspotInfo? _hotspotInfo;
  Timer? _autoHotspotCooldown;
  bool _isRestartingServices = false;
  final Set<String> _pendingIncoming = {};
  String? _localIp;
  Function(String, ConnectionService, bool)? _connectionListener;
  Timer? _networkCheckTimer;
  bool _iosManualHotspotMode =
      false; // Track if iOS user manually enabled hotspot
  late WebRTCFileTransferService _webrtcService;
  late WebShareService _webShareService;
  bool _didStartShowcase = false;
  bool _dragging = false;
  List<XFile> _droppedFiles = []; // Files waiting to be sent to a device

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeController();
    _setupConnectionListener();
    _initializeLocalIp();
    _initializeNetworkName().then((_) {
      if (_networkName == 'Not Connected') {
        controller.pauseRadar();
      }
    });
    _startNetworkStatusCheck();
    widget.discoveryService.addIncomingRequestListener(_onIncomingRequest);
  }

  void _initializeController() {
    controller = HomeController(
      discoveryService: widget.discoveryService,
      myDeviceName: widget.myDeviceName,
    );
    controller.init();

    // Initialize WebRTC service for direct link sharing
    _webrtcService = WebRTCFileTransferService(
      onConnectionEstablished: () {
        if (!mounted) return;
        debugPrint('[HomeScreen] 🎉 WebRTC Connection Established!');
        AppSnackbar.showSuccess(
          context,
          'WebRTC Connected! Ready to transfer files.',
        );
      },
      onConnectionLost: () {
        if (!mounted) return;
        debugPrint('[HomeScreen] 💔 WebRTC Connection Lost');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WebRTC Connection Lost'),
            backgroundColor: Colors.orange,
          ),
        );
      },
      onFileTransferError: (filename, error, isReceive) {
        if (!mounted) return;
        debugPrint('[HomeScreen] ❌ WebRTC Transfer Error: $error');
        AppSnackbar.showError(context, 'Transfer Error: $error');
      },
    );

    // Initialize WebShare service for file management
    _webShareService = WebShareService(
      deviceName: widget.myDeviceName,
      customServiceName: 'CPFT_WebRTC_${widget.myDeviceName}',
    );
  }

  void _setupConnectionListener() {
    final cm = widget.discoveryService.connectionManager;
    if (cm == null) {
      debugPrint(
        '[HomeScreen] ⚠️  ConnectionManager is null - cannot set up listener',
      );
      return;
    }

    debugPrint(
      '[HomeScreen] 🎯 Setting up connection listener. Current connections: ${cm.activeConnections.length}',
    );

    _connectionListener = (deviceName, service, isIncoming) {
      debugPrint(
        '[HomeScreen] 🔔 Connection listener fired: $deviceName, isIncoming: $isIncoming, isConnected: ${service.isConnected}',
      );

      // ONLY navigate for incoming connections
      if (isIncoming && service.isConnected) {
        debugPrint(
          '[HomeScreen] 📲 Auto-navigating to chat for INCOMING connection from $deviceName',
        );
        if (mounted) {
          // Defer navigation to avoid setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  deviceName: deviceName,
                  ipAddress: service.currentConnection?.ipAddress ?? '',
                  port: DiscoveryService.p2pPort,
                  myDeviceName: widget.myDeviceName,
                  connectionManager: cm,
                  initialDeviceId: deviceName,
                ),
              ),
            );
          });
        }
      }

      // Listen for status changes
      service.addStatusListener((info) {
        if (mounted) {
          // Defer setState to avoid calling during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      });

      if (mounted) {
        // Defer setState to avoid calling during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    };

    cm.addConnectionListener(_connectionListener!);
    debugPrint('[HomeScreen] 🎯 Connection listener registered successfully');
  }

  @override
  void dispose() {
    _networkCheckTimer?.cancel();
    _autoHotspotCooldown?.cancel();
    widget.discoveryService.removeIncomingRequestListener(_onIncomingRequest);
    if (_connectionListener != null) {
      widget.discoveryService.connectionManager?.removeConnectionListener(
        _connectionListener!,
      );
    }
    controller.dispose();
    _webrtcService.dispose();
    _webShareService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // On resume, refresh network state immediately to restore banner/UI.
      _initializeLocalIp();
      _initializeNetworkName().then((_) {
        final hasNetwork =
            _networkName != null && _networkName != 'Not Connected';
        if (hasNetwork) {
          controller.resumeRadar();
        } else {
          controller.pauseRadar();
        }
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _onIncomingRequest(
    String deviceName,
    String ipAddress,
    int port,
    Future<void> Function() accept,
    Future<void> Function() decline,
  ) async {
    if (!mounted || _pendingIncoming.contains(deviceName)) return;
    _pendingIncoming.add(deviceName);

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final result = await app_dialog.showAppDialog<bool>(
      context: context,
      builder: (_) => IncomingRequestDialog(deviceName: deviceName),
    );

    _pendingIncoming.remove(deviceName);

    if (result == true) {
      await accept();
      if (!mounted) return;
      AppSnackbar.showSuccess(context, 'Connected with $deviceName');
    } else if (result == false) {
      await decline();
      if (!mounted) return;
      AppSnackbar.showInfo(
        context,
        'You rejected the request from $deviceName',
      );
    }
  }

  void _startNetworkStatusCheck() {
    _networkCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final oldNetworkName = _networkName;
      await _initializeNetworkName();

      final isNowDisconnected = _networkName == 'Not Connected';
      final wasDisconnected = oldNetworkName == 'Not Connected';

      if (isNowDisconnected && !wasDisconnected) {
        widget.discoveryService.clearDevices();
        // On Android, keep radar active since WiFi Direct discovery is still running
        // Only pause radar on iOS if not in manual hotspot mode
        if (Platform.isIOS && !_iosManualHotspotMode && _hotspotInfo == null) {
          controller.pauseRadar();
        }
        // Note: Auto-start hotspot is disabled, user must manually start it
        if (mounted) setState(() {});
      } else if (!isNowDisconnected && wasDisconnected) {
        // We reconnected to some network. If hotspot is active, keep it
        // until the user explicitly switches back to Wi‑Fi.
        // Clear iOS manual hotspot mode since we're on WiFi now
        if (_iosManualHotspotMode) {
          setState(() {
            _iosManualHotspotMode = false;
          });
        }
        controller.resumeRadar();
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _initializeNetworkName() async {
    final permissionsGranted = await AppPermissions.requestNetworkPermissions();

    if (!permissionsGranted) {
      await AppPermissions.checkLocationPermission();
    }

    try {
      final networkName = await NetworkUtils.getWifiName();

      // On iOS, detect if connected to Personal Hotspot
      if (Platform.isIOS) {
        final isHotspot = await NetworkUtils.isIosPersonalHotspot();
        if (isHotspot && !_iosManualHotspotMode) {
          // Auto-enable iOS manual hotspot mode if we detect hotspot IP range
          debugPrint('📱 Auto-detected iOS Personal Hotspot');
          if (mounted) {
            setState(() {
              _iosManualHotspotMode = true;
              _autoHotspotEnabled = true;
            });
            // Resume radar when hotspot is actually detected
            controller.resumeRadar();
          }
        } else if (!isHotspot && _iosManualHotspotMode) {
          // Hotspot was turned off, clear the flag
          debugPrint('📱 iOS Personal Hotspot turned off');
          if (mounted) {
            setState(() {
              _iosManualHotspotMode = false;
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          _networkName = networkName;
        });
      }
      // If offline, try to start hotspot; otherwise do not auto-stop hotspot.
      if (_networkName == 'Not Connected') {
        _maybeStartHotspot();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _networkName = 'Not Connected';
        });
      }
    }
  }

  Future<void> _maybeStopHotspot() async {
    if (_hotspotInfo != null) {
      final stopped = await LocalHotspotService.stopHotspot();
      if (stopped) {
        _hotspotInfo = null;
        // Pause radar if no network available after stopping hotspot
        if (_networkName == 'Not Connected' && !_iosManualHotspotMode) {
          controller.pauseRadar();
        }
      }
    }
  }

  Future<void> _maybeStartHotspot({bool autoShowQr = false}) async {
    if (!_autoHotspotEnabled) return;
    if (_hotspotStarting || _hotspotInfo != null) return;
    if (!mounted) return;
    if (!Platform.isAndroid) return;

    setState(() {
      _hotspotStarting = true;
    });

    try {
      final info = await LocalHotspotService.startHotspot();
      if (info != null && mounted) {
        setState(() {
          _hotspotInfo = info;
          _hotspotStarting = false;
        });

        // Resume radar when hotspot is active
        controller.resumeRadar();

        // Auto-show QR code when manually switching to hotspot
        if (autoShowQr && mounted) {
          // Small delay to ensure UI is updated
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            _showHotspotQrCode();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hotspotStarting = false;
        });
      }
    }
  }

  Future<void> _switchToWifi() async {
    _autoHotspotEnabled = false;
    if (Platform.isIOS) {
      setState(() {
        _iosManualHotspotMode = false;
      });
    }
    await _maybeStopHotspot();
    await WifiService.openWifiSettings();
    if (mounted) setState(() {});

    // Re-enable auto hotspot after a short cooldown if still offline
    _autoHotspotCooldown?.cancel();
    _autoHotspotCooldown = Timer(const Duration(seconds: 60), () async {
      _autoHotspotEnabled = true;
      await _initializeNetworkName();
      if (_networkName == 'Not Connected') {
        _maybeStartHotspot();
      }
    });
  }

  void _showHotspotQrCode() {
    if (_hotspotInfo == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.lg,
                  vertical: AppSizes.md,
                ),
                child: Column(
                  children: [
                    // Header with close button (iOS sheet style)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scan QR Code',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.darkPrimary,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Scan and Connect instantly',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 24),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                            padding: const EdgeInsets.all(10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSizes.md),

                    // QR Code with modern design
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.skyBlue.withValues(alpha: 0.15),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                            spreadRadius: 0,
                          ),
                        ],
                        border: Border.all(
                          color: AppColors.skyBlue.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: QrImageView(
                              data:
                                  'WIFI:T:${_hotspotInfo!.securityType};S:${_hotspotInfo!.ssid};P:${_hotspotInfo!.password};;',
                              version: QrVersions.auto,
                              size: 220,
                              errorCorrectionLevel: QrErrorCorrectLevel.H,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: AppColors.primary,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: AppColors.darkPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.wifi_rounded,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _hotspotInfo!.ssid,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.md),

                    // Quick steps
                    Container(
                      padding: const EdgeInsets.all(AppSizes.md),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Quick Steps',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _buildModernStep(
                            Icons.photo_camera_rounded,
                            'Open your Camera app',
                          ),
                          const SizedBox(height: 14),
                          _buildModernStep(
                            Icons.center_focus_strong_rounded,
                            'Point at the QR code',
                          ),
                          const SizedBox(height: 14),
                          _buildModernStep(
                            Icons.touch_app_rounded,
                            'Tap to connect',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),

                    // Manual connection
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Manual Connection',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.darkPrimary,
                                ),
                          ),
                          const SizedBox(height: 18),
                          _buildModernDetailRow(
                            Icons.wifi_rounded,
                            'Network',
                            _hotspotInfo!.ssid,
                          ),
                          const Divider(height: 24),
                          _buildModernDetailRow(
                            Icons.lock_rounded,
                            'Password',
                            _hotspotInfo!.password,
                          ),
                          const Divider(height: 24),
                          _buildModernDetailRow(
                            Icons.security_rounded,
                            'Security',
                            _hotspotInfo!.securityType,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),

                    // Info tip
                    Container(
                      padding: const EdgeInsets.all(AppSizes.md),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.blue.shade50, Colors.cyan.shade50],
                        ),
                        borderRadius: BorderRadius.circular(AppSizes.md),
                        border: Border.all(
                          color: Colors.blue.shade200.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.info_outline_rounded,
                              color: Colors.blue.shade700,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Can\'t scan? Use Wi‑Fi settings to connect manually',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),

                    // Done button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                          shadowColor: AppColors.primary.withValues(alpha: 0.4),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernStep(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSizes.sm),
          decoration: BoxDecoration(
            color: AppColors.skyBlue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: AppSizes.iconMd, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: AppColors.darkPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModernDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: AppSizes.iconMd, color: AppColors.darkPrimary),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              AppSnackbar.showSuccess(
                context,
                '$label copied',
                duration: const Duration(milliseconds: 1500),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.content_copy_rounded,
                size: 18,
                color: const Color(0xFF2962FF),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _switchToHotspot() async {
    // On iOS, show manual instructions since hotspot API is not available
    if (Platform.isIOS) {
      // Don't set _iosManualHotspotMode = true here
      // Let the auto-detection in _initializeNetworkName() handle it
      // when the user actually enables the hotspot
      _showIosHotspotInstructions();
      return;
    }

    // On Android, starting a local-only hotspot requires Nearby Devices permission.
    // Do not force Location permission for this specific action.
    final permissionsGranted =
        await AppPermissions.requestTemporaryHotspotPermissions();
    if (!permissionsGranted) {
      if (!mounted) return;

      // `requestTemporaryHotspotPermissions()` already triggers the system permission dialog.
      // Only guide the user to Settings when the permission is permanently denied/restricted
      // (when system dialog won’t show anymore).
      PermissionStatus? nearbyStatus;
      try {
        nearbyStatus = await Permission.nearbyWifiDevices.status;
      } catch (_) {
        nearbyStatus = null;
      }
      final permanentlyDenied =
          (nearbyStatus?.isPermanentlyDenied ?? false) ||
          (nearbyStatus?.isRestricted ?? false);

      if (permanentlyDenied) {
        final openSettings = await app_dialog.showAppDialog<bool>(
          context: context,
          builder: (context) => AppConfirmDialog(
            title: 'Permission Required',
            content: Text(
              'To create a temporary hotspot, please allow the required permissions (Location and Nearby devices) in Settings.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.darkPrimary),
            ),
            confirmLabel: 'Open Settings',
            cancelLabel: 'Cancel',
            destructive: false,
          ),
        );

        if (openSettings == true) {
          await AppPermissions.openSystemLocationSettings();
        }
      } else {
        AppSnackbar.showError(context, 'Nearby devices permission denied.');
      }
      return;
    }

    _autoHotspotEnabled = true;

    // Disconnect from WiFi if currently connected
    if (_networkName != null && _networkName != 'Not Connected') {
      // Disconnect from WiFi before starting hotspot
      // The native layer will handle WiFi state correctly:
      // - Android 10+: Keeps WiFi enabled, just disconnects
      // - Android 9-: Fully disables WiFi
      try {
        await WifiService.disconnectWifi();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _maybeStartHotspot(autoShowQr: true);
  }

  void _showIosHotspotInstructions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const IosHotspotInstructionsSheet(),
    );
  }

  Future<void> _initializeLocalIp() async {
    try {
      _localIp = await NetworkUtils.getLanIPv4();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[HomeScreen] Error getting local IP: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Trigger showcase only on first app launch
    if (!_didStartShowcase) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final prefs = await SharedPreferences.getInstance();
        final hasSeenShowcase = prefs.getBool('home_showcase_seen') ?? false;

        if (!hasSeenShowcase && mounted) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              try {
                ShowcaseHelper.startForHome(context);
                prefs.setBool('home_showcase_seen', true);
              } catch (_) {}
            }
          });
        }
      });
      _didStartShowcase = true;
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hasNetwork =
            _networkName != null && _networkName != 'Not Connected';
        // On iOS, if manual hotspot mode is active, treat it as having network
        // On Android, if hotspot is active, treat it as having network
        final effectiveHasNetwork =
            hasNetwork || _iosManualHotspotMode || _hotspotInfo != null;
        final devices = effectiveHasNetwork
            ? controller.devices.values.where((d) => d.ip != _localIp).toList()
            : <DeviceInfo>[];

        final deviceDots = _buildDeviceDots(devices);

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: false,
          appBar: HomeAppBar(
            connectionManager: widget.discoveryService.connectionManager,
            discoveryService: widget.discoveryService,
            isRestartingServices: _isRestartingServices,
            onRefresh: _handleServiceRestart,
            onShowConnectedDevices: _showConnectedDevicesDialog,
            onQrScan: _handleQrScan,
          ),
          body: DropTarget(
            onDragDone: (detail) async {
              setState(() {
                _dragging = false;
              });

              // Handle dropped files
              if (detail.files.isNotEmpty) {
                await _handleDroppedFiles(detail.files);
              }
            },
            onDragEntered: (detail) {
              setState(() {
                _dragging = true;
              });
            },
            onDragExited: (detail) {
              setState(() {
                _dragging = false;
              });
            },
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE2F6FB), Color(0xFFFFFFFF)],
                  stops: [0.0, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  SafeArea(
                    child: Column(
                      children: [
                        // Show shared content banner if available (only on mobile)
                        if (!kIsWeb) const SharedContentBanner(),
                        // Show dropped files banner if files are waiting
                        if (_droppedFiles.isNotEmpty)
                          _buildDroppedFilesBanner(),
                        const SizedBox(height: AppSizes.spaceBtwSections),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.md,
                          ),
                          child: Row(
                            textDirection: TextDirection.rtl,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: _isRestartingServices
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                AppColors.primary,
                                              ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.refresh_rounded,
                                        color: AppColors.primary,
                                        size: 24,
                                      ),
                                onPressed: _isRestartingServices
                                    ? null
                                    : _handleServiceRestart,
                                tooltip: 'Restart Services',
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Finding nearby devices....',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w400,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSizes.spaceBtwSections),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSizes.sm,
                                ),
                                child: RadarView(
                                  sweepAngle: controller.sweepAngle,
                                  deviceDots: deviceDots,
                                  center: _buildRadarCenter(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSizes.md),
                        NetworkBanner(
                          networkName: _networkName,
                          hotspotActive:
                              _hotspotInfo != null || _iosManualHotspotMode,
                          hotspotStarting: _hotspotStarting,
                          hotspotName:
                              _hotspotInfo?.ssid ??
                              (_iosManualHotspotMode
                                  ? 'Personal Hotspot'
                                  : null),
                          iosPersonalHotspot: _iosManualHotspotMode,
                          onSwitchToWifi:
                              (_hotspotInfo != null || _iosManualHotspotMode)
                              ? _switchToWifi
                              : null,
                          onShowQrCode: _hotspotInfo != null
                              ? _showHotspotQrCode
                              : null,
                          onSwitchToHotspot:
                              (_hotspotInfo == null && !_iosManualHotspotMode)
                              ? _switchToHotspot
                              : null,
                        ),
                        const SizedBox(height: AppSizes.lg),
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSizes.lg),
                          child: _buildShareOptionsSection(),
                        ),
                      ],
                    ),
                  ),
                  // Drag overlay
                  ...(_dragging
                      ? [
                          DragOverlay(
                            title: 'Drop files to share',
                            subtitle: 'Release to send files to nearby devices',
                            iconSize: 48,
                            showBorder: false,
                          ),
                        ]
                      : []),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildDeviceDots(List<DeviceInfo> devices) {
    final dots = <Widget>[];
    final usedPositions = <DevicePosition>[];

    for (int i = 0; i < devices.length && i < 8; i++) {
      final device = devices[i];
      final position = DeviceDotLayoutHelper.calculatePosition(
        device: device,
        index: i,
        totalDevices: devices.length,
        usedPositions: usedPositions,
      );

      usedPositions.add(
        DevicePosition(
          angle: position.angle,
          distance: position.distance,
          size: position.size,
        ),
      );

      dots.add(
        DeviceDot(
          label: device.name,
          angle: position.angle,
          distanceFactor: position.distance,
          onTap: () => _handleDeviceTap(device),
        ),
      );
    }

    return dots;
  }

  Future<void> _handleDeviceTap(DeviceInfo device) async {
    var manager = widget.discoveryService.connectionManager;
    if (manager == null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Preparing discovery...',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.white),
          ),
          duration: const Duration(seconds: 1),
        ),
      );

      try {
        await widget.discoveryService.initialize();
        await widget.discoveryService.ready;
      } catch (_) {}

      manager = widget.discoveryService.connectionManager;
      if (manager == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Discovery not ready yet. Please try again.',
              style: TextStyle(color: Colors.white),
            ),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    if (!mounted) return;

    await ConnectionHandler.handleDeviceTap(
      context: context,
      device: device,
      connectionManager: manager,
      discoveryService: widget.discoveryService,
      myDeviceName: widget.myDeviceName,
      droppedFiles: _droppedFiles.isNotEmpty
          ? List<XFile>.from(_droppedFiles)
          : null,
      onFilesSent: _droppedFiles.isNotEmpty
          ? () {
              setState(() {
                _droppedFiles.clear();
              });
            }
          : null,
    );
  }

  Widget _buildRadarCenter() {
    return Container(
      width: 140,
      height: 140,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFB8D9ED).withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.skyBlue.withValues(alpha: 0.1),
            blurRadius: 30,
            spreadRadius: 5,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sensors, color: AppColors.primary, size: AppSizes.iconLg),
          Text(
            widget.myDeviceName,
            textAlign: TextAlign.center,
            softWrap: true,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareOptionsSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Showcase(
              key: ShowcaseHelper.linkShareKey,
              disableBarrierInteraction: false,
              targetPadding: const EdgeInsets.all(8),
              title: 'Web Share',
              description: 'Share files via web without application.',
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
              child: LinkShareButton(
                onPressed: () async {
                  if (!mounted) return;

                  // Check if local-only hotspot is active (which blocks internet for WebRTC signaling)
                  final hotspotRunning =
                      await LocalHotspotService.isHotspotRunning();
                  final lanIp = await NetworkUtils.getLanIPv4();
                  final hasNetwork = lanIp != null;

                  AppLogger.d(
                    'Web share check: hotspotRunning=$hotspotRunning, hasNetwork=$hasNetwork, lanIp=$lanIp',
                    tag: 'HomeScreen',
                  );

                  if (hotspotRunning) {
                    // Local-only hotspot is active - this blocks internet access needed for WebRTC
                    // Show dialog and let user choose to switch to WiFi
                    if (!mounted) return;
                    final shouldSwitch = await app_dialog.showAppDialog<bool>(
                      context: context,
                      builder: (context) => AppConfirmDialog(
                        title: 'Internet Connection Required',
                        content: Text(
                          'WebRTC connections require internet access for signaling. '
                          'A local-only hotspot is currently active.\n\n'
                          'Would you like to stop the hotspot and open WiFi settings to connect to a network with internet access?',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.darkPrimary),
                        ),
                        confirmLabel: 'Yes, Switch to WiFi',
                        cancelLabel: 'Cancel',
                        destructive: false,
                      ),
                    );

                    if (shouldSwitch == true) {
                      // User confirmed - stop hotspot and open WiFi settings
                      try {
                        await LocalHotspotService.stopHotspot();
                        AppLogger.i(
                          'Stopped local-only hotspot for WiFi switch',
                          tag: 'HomeScreen',
                        );

                        // Clear hotspot info to update UI
                        if (mounted) {
                          setState(() {
                            _hotspotInfo = null;
                            _hotspotStarting = false;
                          });
                        }

                        // Open WiFi settings
                        await WifiService.openWifiSettings();
                        AppLogger.i(
                          'Opened WiFi settings for user',
                          tag: 'HomeScreen',
                        );

                        // Refresh network name after a short delay to allow WiFi connection
                        Future.delayed(const Duration(seconds: 2), () async {
                          if (mounted) {
                            await _initializeNetworkName();
                            AppLogger.i(
                              'Refreshed network name after WiFi switch',
                              tag: 'HomeScreen',
                            );
                          }
                        });

                        if (mounted) {
                          AppSnackbar.showSuccess(
                            context,
                            'Hotspot stopped. Please connect to WiFi with internet access.',
                          );
                        }
                      } catch (e) {
                        AppLogger.w(
                          'Failed to stop hotspot or open WiFi settings: $e',
                          tag: 'HomeScreen',
                        );
                        if (mounted) {
                          AppSnackbar.showError(context, 'Error: $e');
                        }
                      }
                    }
                    return;
                  }

                  showAppBottomSheet(
                    context: context,
                    title: 'Web Share',
                    subtitle:
                        'Establish direct web connection for file sharing.',
                    showCloseButton: true,
                    child: WebRTCConnectionBottomSheet(
                      webrtcService: _webrtcService,
                      webShareService: _webShareService,
                      onConnected: () {
                        // Optionally navigate to file transfer screen or show success
                      },
                      onError: (error) {
                        AppSnackbar.showError(
                          context,
                          'Connection Error: $error',
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
          child: Text(
            'Share files via link or create a local hotspot for direct connection',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.greyLight),
          ),
        ),
      ],
    );
  }

  Future<void> _handleQrScan() async {
    if (!mounted) return;

    // QR scanning should not run while hotspot is active.
    if (_hotspotInfo != null) {
      await _maybeStopHotspot();
      if (mounted) setState(() {});

      if (_hotspotInfo != null) {
        AppSnackbar.showError(
          context,
          'Please turn off hotspot before scanning QR code.',
        );
        return;
      }
    }

    if (_iosManualHotspotMode) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Turn off Hotspot'),
          content: const Text(
            'Please turn off Personal Hotspot before scanning a QR code.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await WifiService.openWifiSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const QrScannerScreen()));
  }

  Future<void> _handleServiceRestart() async {
    await ServiceRestartHandler.restartServices(
      context: context,
      discoveryService: widget.discoveryService,
      setRestartingState: (value) {
        if (mounted) {
          setState(() {
            _isRestartingServices = value;
          });
        }
      },
    );
  }

  void _showConnectedDevicesDialog() {
    final connectionManager = widget.discoveryService.connectionManager;
    if (connectionManager == null) {
      debugPrint(
        '[HomeScreen] ⚠️  ConnectionManager is null when trying to show devices',
      );
      return;
    }

    if (mounted) setState(() {});

    showAppBottomSheet(
      context: context,
      title: 'Connected Devices',
      subtitle: 'Tap to open chat',
      maxHeightFactor: 0.6,
      contentPadding: const EdgeInsets.only(top: 16),
      child: ConnectedDevicesBottomSheet(
        connectionManager: connectionManager,
        onDeviceTap: _navigateToDeviceChat,
        onFilesSent: _droppedFiles.isNotEmpty
            ? () {
                setState(() {
                  _droppedFiles.clear();
                });
              }
            : null,
      ),
    );
  }

  void _navigateToDeviceChat(
    String deviceId, [
    String? ipAddress,
    int? port,
    VoidCallback? onFilesSent,
  ]) {
    final connectionManager = widget.discoveryService.connectionManager;
    if (connectionManager == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          deviceName: deviceId,
          ipAddress: ipAddress ?? '',
          port: port ?? DiscoveryService.p2pPort,
          myDeviceName: widget.myDeviceName,
          connectionManager: connectionManager,
          initialDeviceId: deviceId,
          droppedFiles: _droppedFiles.isNotEmpty
              ? List<XFile>.from(_droppedFiles)
              : null,
          onFilesSent: onFilesSent,
        ),
      ),
    );
  }

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    if (files.isEmpty) return;

    // Add the dropped files to the existing list (avoid duplicates)
    setState(() {
      for (final file in files) {
        // Check if file already exists (by path)
        if (!_droppedFiles.any((existing) => existing.path == file.path)) {
          _droppedFiles.add(file);
        }
      }
    });

    // Show confirmation that files are ready
    AppSnackbar.showInfo(
      context,
      '${_droppedFiles.length} file${_droppedFiles.length > 1 ? 's' : ''} ready to send - tap a device to share',
    );
  }

  Widget _buildDroppedFilesBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.deepOrange.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.file_present,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text(
              '${_droppedFiles.length} file${_droppedFiles.length > 1 ? 's' : ''} selected to transfer - select device to start transfer',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _droppedFiles.clear();
              });
              AppSnackbar.showInfo(context, 'Files cleared');
            },
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            tooltip: 'Clear files',
          ),
        ],
      ),
    );
  }
}
