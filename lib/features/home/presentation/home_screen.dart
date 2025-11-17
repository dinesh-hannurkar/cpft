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

  @override
  void initState() {
    super.initState();
    print("=== HomeScreen initState called ===");
    controller = HomeController(
      discoveryService: widget.discoveryService,
      myDeviceName: widget.myDeviceName,
    );
    controller.init();
    _initializeNetworkName();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final devices = controller.devices.values.toList();
        final dots = <Widget>[];
        // Track used angles per distance bucket to keep dots separated
        final Map<int, List<double>> usedAnglesByBucket = {};
        for (int i = 0; i < devices.length && i < 8; i++) {
          final d = devices[i];
          final hash = d.name.hashCode;
          double angle = (hash % 360) * pi / 180.0;
          // Keep dots outside center circle: 0.60 .. 0.85 with a tiny radial jitter to reduce overlaps
          double dist = 0.60 + (hash % 50) / 200.0; // 0.60..0.85 base
          final double jitter =
              (((hash >> 8) % 7) - 3) / 100.0; // -0.03 .. +0.03
          dist = (dist + jitter).clamp(0.58, 0.88);
          // Compute a bucket based on distance to reduce collisions on same ring
          final int bucket = (dist * 10).floor(); // 6..8 typical
          usedAnglesByBucket.putIfAbsent(bucket, () => []);
          // Minimum angular separation in degrees (slightly smaller for outer rings)
          double minSepDeg = 22.0 - 8.0 * (dist - 0.60) / 0.25; // ~22 -> 14
          if (minSepDeg < 10.0) minSepDeg = 10.0;
          final double minSepRad = minSepDeg * pi / 180.0;
          // Adjust angle if too close to existing ones in the same bucket
          bool hasCollision() => usedAnglesByBucket[bucket]!.any((a) {
            double diff = (angle - a).abs();
            diff = diff > pi ? (2 * pi - diff) : diff; // shortest wrap-around
            return diff < minSepRad;
          });
          int guard = 0;
          while (hasCollision() && guard < 24) {
            angle += minSepRad;
            if (angle > 2 * pi) angle -= 2 * pi;
            guard++;
          }
          usedAnglesByBucket[bucket]!.add(angle);
          dots.add(
            DeviceDot(
              label: d.name, // full name for 2-line label
              angle: angle,
              distanceFactor: dist,
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
                      child: SettingsButton(
                        onPressed: () {
                          /* TODO: navigate to settings */
                        },
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
