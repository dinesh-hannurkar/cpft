import 'dart:math';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';
import '../../../services/discovery_service.dart';
import '../../../utils/network_utils.dart';
import '../../../utils/permissions.dart';
import '../controllers/home_controller.dart';
import 'widgets/radar_view.dart';
import 'widgets/device_dot.dart';
import 'widgets/network_banner.dart';
import 'widgets/link_share_button.dart';
import 'widgets/settings_button.dart';
import 'widgets/connection_flow_dialog.dart';
import 'widgets/incoming_request_dialog.dart';
import '../../../shared/widgets/dialog_helpers.dart' as app_dialog;
import '../../../screens/connection_screen.dart';

/// Simple data class to track device positions for collision detection
class DevicePosition {
  final double angle;
  final double distance;
  final double size;
  
  const DevicePosition({
    required this.angle,
    required this.distance,
    required this.size,
  });
}

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

class _HomeScreenState extends State<HomeScreen> {
  late HomeController controller;
  String? _networkName;
  bool _isRestartingDiscovery = false;
  // Track in-flight incoming prompts to avoid duplicate dialogs
  final Set<String> _pendingIncoming = {};
  String? _localIp;

  @override
  void initState() {
    super.initState();
    print("=== HomeScreen initState called ===");
    controller = HomeController(
      discoveryService: widget.discoveryService,
      myDeviceName: widget.myDeviceName,
    );
    controller.init();
    _initializeLocalIp();
  // Listen for incoming connection requests to show confirmation popup
  widget.discoveryService.addIncomingRequestListener(_onIncomingRequest);
    _initializeNetworkName();
  }

  @override
  void dispose() {
    // Remove incoming listener
    widget.discoveryService.removeIncomingRequestListener(_onIncomingRequest);
    controller.dispose();
    super.dispose();
  }

  // Incoming connection confirmation flow
  Future<void> _onIncomingRequest(
    String deviceName,
    String ipAddress,
    int port,
    Future<void> Function() accept,
    Future<void> Function() decline,
  ) async {
    if (!mounted) return;
    if (_pendingIncoming.contains(deviceName)) return;
    _pendingIncoming.add(deviceName);

    bool? result;
    // Ensure dialog runs after current frame and on the root navigator
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    result = await app_dialog.showAppDialog<bool>(
      context: context,
      builder: (_) => IncomingRequestDialog(deviceName: deviceName),
    );

    _pendingIncoming.remove(deviceName);

  if (result == true) {
      await accept();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected with $deviceName', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.white))),
      );
      // Navigate to chat on the receiver side as well
      var cm = widget.discoveryService.connectionManager;
      if (cm == null) {
        try {
          await widget.discoveryService.initialize();
        } catch (_) {}
        cm = widget.discoveryService.connectionManager;
      }
      if (!mounted) return;
  if (cm != null) {
    final nonNullCm = cm;
    Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConnectionScreen(
              deviceName: deviceName,
              ipAddress: ipAddress,
              port: DiscoveryService.p2pPort,
              myDeviceName: widget.myDeviceName,
      connectionManager: nonNullCm,
            ),
          ),
        );
      }
    } else if (result == false) {
      await decline();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You rejected the request from $deviceName',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
  }

  Future<void> _initializeNetworkName() async {
    print("=== _initializeNetworkName called ===");
    // Request permissions first
    final permissionsGranted = await AppPermissions.requestNetworkPermissions();

    if (!permissionsGranted) {
      print('Permissions not granted - WiFi name may not be available');
      // Check if location permission is permanently denied
      final locationGranted = await AppPermissions.checkLocationPermission();
      if (!locationGranted) {
        print(
          'Location permission required for WiFi name. Please enable in Settings.',
        );
        // Could show a dialog here to guide user to settings
      }
    }

    // Get network name (WiFi name or IP-based fallback)
    final networkName = await NetworkUtils.getWifiName();
    print(
      networkName != null
          ? 'Network name obtained: $networkName'
          : 'No network name obtained',
    );
    if (mounted) {
      setState(() {
        _networkName = networkName;
      });
    }
  }

  Future<void> _initializeLocalIp() async {
    _localIp = await NetworkUtils.getLanIPv4();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final devices = controller.devices.values.where((d) => d.ip != _localIp).toList();
        final dots = <Widget>[];
        // Track all used positions to prevent any overlaps
        final List<DevicePosition> usedPositions = [];
        
        for (int i = 0; i < devices.length && i < 8; i++) {
          final d = devices[i];
          final hash = d.name.hashCode;
          double angle = (hash % 360) * pi / 180.0;
          // Keep dots outside center circle: 0.60 .. 0.85 with a tiny radial jitter to reduce overlaps
          double dist = 0.60 + (hash % 50) / 200.0; // 0.60..0.85 base
          final double jitter = (((hash >> 8) % 7) - 3) / 100.0; // -0.03 .. +0.03
          dist = (dist + jitter).clamp(0.58, 0.88);
          
          // Calculate actual pixel size for collision detection
          final int hashFactor = (hash.abs() % 1000);
          final double baseVar = 18.0 * hashFactor / 1000.0; // 0..18
          final double proximityBoost = (1.0 - dist).clamp(0.0, 1.0) * 6.0; // 0..6
          final double dotSize = 45.0 + baseVar + proximityBoost; // ~30..54
          
          // Minimum angular separation based on dot size and distance
          // Use a more conservative approach
          final double minAngularSeparation = (dotSize * 1.5) / (dist * 200); // Conservative multiplier
          final double minSepRad = minAngularSeparation.clamp(pi / 6, pi / 3); // 30-60 degrees
          
          // Check collision against all existing positions
          bool hasCollision() {
            for (final pos in usedPositions) {
              final angleDiff = (angle - pos.angle).abs();
              final normalizedDiff = angleDiff > pi ? (2 * pi - angleDiff) : angleDiff;
              
              // Check if too close angularly or radially
              final radialOverlap = (dist - pos.distance).abs() < 0.1; // Within 10% distance
              final angularOverlap = normalizedDiff < minSepRad;
              
              if (radialOverlap && angularOverlap) {
                return true;
              }
            }
            return false;
          }
          
          // Try to find a collision-free position
          int attempts = 0;
          const int maxAttempts = 72; // Full circle in 5-degree increments
          while (hasCollision() && attempts < maxAttempts) {
            angle += pi / 36; // 5 degrees
            if (angle > 2 * pi) angle -= 2 * pi;
            attempts++;
          }
          
          // If still colliding after max attempts, place it anyway but log warning
          if (hasCollision()) {
            print('Warning: Could not find collision-free position for device ${d.name}');
          }
          
          // Record this position
          usedPositions.add(DevicePosition(angle: angle, distance: dist, size: dotSize));
          
          dots.add(
            DeviceDot(
              label: d.name,
              angle: angle,
              distanceFactor: dist,
              onTap: () async {
                // Ensure connection manager is ready
        var manager = widget.discoveryService.connectionManager;
                if (manager == null) {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Preparing discovery...', style: Theme.of(context).textTheme.bodyMedium),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  try {
                    await widget.discoveryService.initialize();
          // Wait until DiscoveryService signals readiness
          await widget.discoveryService.ready;
                  } catch (_) {}
                  manager = widget.discoveryService.connectionManager;
                  if (manager == null) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Discovery not ready yet. Please try again.', style: TextStyle(color: Colors.white)),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                }

                if (!mounted) return;
                // Re-read to a non-nullable local after initialization above
                final cm = manager;
                final result = await app_dialog.showAppDialog(
                  context: context,
                  builder: (_) => ConnectionFlowDialog(
                    myDeviceName: widget.myDeviceName,
                    peerDeviceName: d.name,
                    peerIp: d.ip,
                    p2pPort: DiscoveryService.p2pPort,
                    connectionManager: cm,
                    discoveryService: widget.discoveryService,
                  ),
                );
                if (!mounted) return;
                if (result == 'connected') {
                  // Navigate to chat screen (ConnectionScreen)
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConnectionScreen(
                        deviceName: d.name,
                        ipAddress: d.ip,
                        port: DiscoveryService.p2pPort,
                        myDeviceName: widget.myDeviceName,
                        connectionManager: cm,
                      ),
                    ),
                  );
                }
              },
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: false,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(80),
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.skyBlue.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                ),
                height: AppSizes.appBarHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Text(
                        'CPFT',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.apply(color: AppColors.primary),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: _isRestartingDiscovery
                                ? SizedBox(
                                    width: AppSizes.iconMd,
                                    height: AppSizes.iconMd,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.primary,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.refresh,
                                    color: AppColors.primary,
                                    size: AppSizes.iconMd,
                                  ),
                            onPressed: _isRestartingDiscovery
                                ? null
                                : () async {
                                    setState(() {
                                      _isRestartingDiscovery = true;
                                    });

                                    // Show loading indicator
                                    final messenger = ScaffoldMessenger.of(context);
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Restarting device discovery...',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );

                                    try {
                                      await widget.discoveryService
                                          .restartDiscovery();
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Discovery restarted successfully',
                                            style: TextStyle(color: Colors.white),
                                          ),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    } catch (e) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to restart discovery: $e',
                                            style: const TextStyle(color: Colors.white),
                                          ),
                                          duration: const Duration(seconds: 3),
                                        ),
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _isRestartingDiscovery = false;
                                        });
                                      }
                                    }
                                  },
                            tooltip: 'Restart Discovery',
                          ),
                          const SizedBox(width: AppSizes.sm),
                          SettingsButton(
                            onPressed: () {
                              /* TODO: navigate to settings */
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
              child: Column(
                children: [
                  const SizedBox(height: AppSizes.spaceBtwSections),
                  Text(
                    'Finding nearby devices....',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceBtwSections),
                  // Radar centered with less side padding
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
                            deviceDots: dots,
                            center: Container(
                              width: 140,
                              height: 140,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSizes.xl,
                                // vertical: AppSizes.xs,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.secondary.withValues(
                                  alpha: 0.9,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Color(
                                    0xFFB8D9ED,
                                  ).withValues(alpha: 0.2),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.skyBlue.withValues(
                                      alpha: 0.1,
                                    ),
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
                                  Icon(
                                    Icons.sensors,
                                    color: AppColors.primary,
                                    size: AppSizes.iconLg,
                                  ),
                                  Text(
                                    widget.myDeviceName,
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w500,
                                          height: 1.2,
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
                  const SizedBox(height: AppSizes.md),
                  NetworkBanner(networkName: _networkName),
                  const SizedBox(height: AppSizes.lg),
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinkShareButton(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final ok = await widget.discoveryService
                                .startWebServer();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Web Share started. Open from a browser on the same network.'
                                      : 'Failed to start Web Share',
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: AppSizes.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.xl,
                          ),
                          child: Text(
                            'App not installed on other device? use link share',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.greyLight),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
