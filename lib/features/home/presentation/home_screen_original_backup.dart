import 'dart:async';
import 'dart:math';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/home/helpers/device_position.dart';
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
import '../../../features/chat/presentation/connection_screen.dart';
import '../../../features/webshare/presentation/webshare_screen.dart';
import '../../../features/webshare/services/web_server.dart';
import '../../../features/chat/services/connection_service.dart';
import '../../../features/chat/services/connection_manager.dart';
import '../../../features/chat/models/connection_state.dart';

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
  bool _isRestartingServices = false;
  // Track in-flight incoming prompts to avoid duplicate dialogs
  final Set<String> _pendingIncoming = {};
  String? _localIp;
  // Listener to refresh UI when connections change
  Function(String, ConnectionService, bool)? _connectionListener;
  Timer? _networkCheckTimer;

  @override
  void initState() {
    super.initState();
    controller = HomeController(
      discoveryService: widget.discoveryService,
      myDeviceName: widget.myDeviceName,
    );
    controller.init();
    _initializeLocalIp();
    // Listen for incoming connection requests to show confirmation popup
    widget.discoveryService.addIncomingRequestListener(_onIncomingRequest);
    _initializeNetworkName().then((_) {
      // Pause radar if starting with no network
      if (_networkName == 'Not Connected') {
        controller.pauseRadar();
      }
    });
    _startNetworkStatusCheck();

    // Attach connection manager listener if available to refresh connected device count
    final cm = widget.discoveryService.connectionManager;
    if (cm != null) {
      debugPrint(
        '[HomeScreen] 🎯 Setting up connection listener. Current connections: ${cm.activeConnections.length}',
      );

      _connectionListener = (deviceName, service, isIncoming) {
        debugPrint(
          '[HomeScreen] 🔔 Connection listener fired: $deviceName, isIncoming: $isIncoming, isConnected: ${service.isConnected}',
        );
        debugPrint(
          '[HomeScreen] 🔔 Total active connections: ${cm.activeConnections.length}, devices: ${cm.activeConnections.keys.join(", ")}',
        );

        // ONLY navigate for incoming connections (outgoing connections are handled by the caller who initiated them)
        if (isIncoming && service.isConnected) {
          debugPrint(
            '[HomeScreen] 📲 Auto-navigating to chat for INCOMING connection from $deviceName',
          );
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConnectionScreen(
                  deviceName: deviceName,
                  ipAddress: service.currentConnection?.ipAddress ?? '',
                  port: DiscoveryService.p2pPort,
                  myDeviceName: widget.myDeviceName,
                  connectionManager: cm,
                  initialDeviceId: deviceName,
                ),
              ),
            );
          }
        } else if (!isIncoming && service.isConnected) {
          debugPrint(
            '[HomeScreen] ✅ Outgoing connection to $deviceName completed - caller will handle navigation',
          );
        }

        // Also listen for status changes on this service to update UI when it disconnects/reconnects
        service.addStatusListener((info) {
          debugPrint(
            '[HomeScreen] 🔔 Status changed for $deviceName: ${info.status}',
          );
          if (mounted) {
            setState(() {
              debugPrint(
                '[HomeScreen] 🔔 setState called - rebuilding HomeScreen',
              );
            });
          }
        });

        if (mounted) {
          setState(() {
            debugPrint(
              '[HomeScreen] 🔔 setState called from connection listener',
            );
          });
        }
      };
      cm.addConnectionListener(_connectionListener!);
      debugPrint('[HomeScreen] 🎯 Connection listener registered successfully');
    } else {
      debugPrint(
        '[HomeScreen] ⚠️  ConnectionManager is null - cannot set up listener',
      );
    }
  }

  @override
  void dispose() {
    _networkCheckTimer?.cancel();
    // Remove incoming listener
    widget.discoveryService.removeIncomingRequestListener(_onIncomingRequest);
    if (_connectionListener != null) {
      widget.discoveryService.connectionManager?.removeConnectionListener(
        _connectionListener!,
      );
    }
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
        SnackBar(
          content: Text(
            'Connected with $deviceName',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.white),
          ),
        ),
      );
      // Don't navigate here - the _connectionListener will handle navigation for incoming connections
      debugPrint(
        '[HomeScreen] ✅ Accepted incoming connection from $deviceName - listener will navigate',
      );
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

  void _startNetworkStatusCheck() {
    // Check network status every 5 seconds
    _networkCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final oldNetworkName = _networkName;
      await _initializeNetworkName();

      final isNowDisconnected = _networkName == 'Not Connected';
      final wasDisconnected = oldNetworkName == 'Not Connected';

      // If network disconnected, clear discovered devices and pause radar
      if (isNowDisconnected && !wasDisconnected) {
        print(
          '[HomeScreen] Network disconnected - clearing discovered devices and pausing radar',
        );
        widget.discoveryService.clearDevices();
        controller.pauseRadar();
        if (mounted) {
          setState(() {});
        }
      }
      // If network reconnected, resume radar
      else if (!isNowDisconnected && wasDisconnected) {
        print('[HomeScreen] Network reconnected - resuming radar');
        controller.resumeRadar();
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  Future<void> _initializeNetworkName() async {
    print("=== _initializeNetworkName called ===");
    final permissionsGranted = await AppPermissions.requestNetworkPermissions();

    if (!permissionsGranted) {
      print('Permissions not granted - WiFi name may not be available');
      final locationGranted = await AppPermissions.checkLocationPermission();
      if (!locationGranted) {
        print(
          'Location permission required for WiFi name. Please enable in Settings.',
        );
      }
    }

    try {
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
    } catch (e) {
      print('Error getting network name: $e');
      if (mounted) {
        setState(() {
          _networkName = 'Not Connected';
        });
      }
    }
  }

  Future<void> _initializeLocalIp() async {
    try {
      _localIp = await NetworkUtils.getLanIPv4();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error getting local IP: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hasNetwork =
            _networkName != null && _networkName != 'Not Connected';
        final devices = hasNetwork
            ? controller.devices.values.where((d) => d.ip != _localIp).toList()
            : <DeviceInfo>[];
        final dots = <Widget>[];
        final List<DevicePosition> usedPositions = [];

        for (int i = 0; i < devices.length && i < 8; i++) {
          final d = devices[i];
          final hash = d.name.hashCode;

          // Better initial distribution: divide circle evenly, then add hash-based variation
          double baseAngle =
              (i * 2 * pi) /
              devices.length.clamp(1, 8); // Evenly space initially
          double angleVariation =
              ((hash % 60) - 30) * pi / 180.0; // ±30 degrees variation
          double angle = baseAngle + angleVariation;

          // Keep dots outside center circle: 0.60 .. 0.85 with increased radial jitter
          double dist = 0.60 + (hash % 50) / 200.0; // 0.60..0.85 base
          final double radialJitter =
              (((hash >> 8) % 21) - 10) / 100.0; // -0.10 .. +0.10
          dist = (dist + radialJitter).clamp(0.55, 0.90);

          // Calculate actual pixel size for collision detection
          final int hashFactor = (hash.abs() % 1000);
          final double baseVar = 18.0 * hashFactor / 1000.0; // 0..18
          final double proximityBoost =
              (1.0 - dist).clamp(0.0, 1.0) * 6.0; // 0..6
          final double dotSize = 45.0 + baseVar + proximityBoost; // ~30..54

          // Minimum angular separation based on dot size and distance
          // More aggressive separation to prevent overlaps
          final double minAngularSeparation =
              (dotSize * 2.0) / (dist * 180); // More conservative
          final double minSepRad = minAngularSeparation.clamp(
            pi / 4,
            pi / 2,
          ); // 45-90 degrees

          // Check collision against all existing positions
          bool hasCollision() {
            for (final pos in usedPositions) {
              final angleDiff = (angle - pos.angle).abs();
              final normalizedDiff = angleDiff > pi
                  ? (2 * pi - angleDiff)
                  : angleDiff;

              // Check if too close angularly or radially
              final radialOverlap =
                  (dist - pos.distance).abs() < 0.12; // Within 12% distance
              final angularOverlap = normalizedDiff < minSepRad;

              if (radialOverlap && angularOverlap) {
                return true;
              }
            }
            return false;
          }

          // Try to find a collision-free position with smaller angle increments
          int attempts = 0;
          const int maxAttempts = 120; // More attempts for finer resolution
          while (hasCollision() && attempts < maxAttempts) {
            angle += pi / 60; // 3 degrees - finer resolution
            if (angle > 2 * pi) angle -= 2 * pi;
            attempts++;
          }

          // If still colliding after max attempts, try radial adjustment
          if (hasCollision()) {
            // Try moving radially outward
            dist = (dist + 0.05).clamp(0.55, 0.95);
            if (!hasCollision()) {
              print(
                'Resolved collision for ${d.name} by moving radially to $dist',
              );
            } else {
              // Try moving radially inward
              dist = (dist - 0.10).clamp(0.55, 0.95);
              if (!hasCollision()) {
                print(
                  'Resolved collision for ${d.name} by moving radially inward to $dist',
                );
              } else {
                print(
                  'Warning: Could not find collision-free position for device ${d.name}',
                );
              }
            }
          }

          // Record this position
          usedPositions.add(
            DevicePosition(angle: angle, distance: dist, size: dotSize),
          );

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
                      content: Text(
                        'Preparing discovery...',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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
                // Re-read to a non-nullable local after initialization above
                final cm = manager;

                // Check if already connected to this device (by name or IP)
                debugPrint(
                  '[HomeScreen] 🔍 Tapped device: ${d.name} (IP: ${d.ip})',
                );
                debugPrint(
                  '[HomeScreen] 🔍 Active connections keys: ${cm.activeConnections.keys.join(", ")}',
                );

                // Try to find connection by name first, then by IP
                var existingConnection = cm.getConnection(d.name);
                if (existingConnection == null) {
                  debugPrint(
                    '[HomeScreen] 🔍 No connection found by name, trying by IP: ${d.ip}',
                  );
                  existingConnection = cm.getConnection(d.ip);
                }

                debugPrint(
                  '[HomeScreen] 🔍 Connection found: ${existingConnection != null}, isConnected: ${existingConnection?.isConnected}, status: ${existingConnection?.currentConnection?.status}',
                );

                if (existingConnection != null) {
                  final status = existingConnection.currentConnection?.status;
                  final connectionDeviceName =
                      existingConnection.currentConnection?.deviceName ??
                      d.name;

                  // If connected or connecting, navigate directly (avoid duplicate connection attempts)
                  if (status == ConnectionStatus.connected ||
                      status == ConnectionStatus.connecting) {
                    debugPrint(
                      '[HomeScreen] ✅ Already connected/connecting to $connectionDeviceName, navigating to chat',
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConnectionScreen(
                          deviceName: connectionDeviceName,
                          ipAddress: d.ip,
                          port: DiscoveryService.p2pPort,
                          myDeviceName: widget.myDeviceName,
                          connectionManager: cm,
                          initialDeviceId: connectionDeviceName,
                        ),
                      ),
                    );
                    return;
                  } else if (status == ConnectionStatus.disconnected) {
                    // Connection exists but is disconnected - navigate to chat to allow reconnect
                    debugPrint(
                      '[HomeScreen] 📡 Connection to $connectionDeviceName is disconnected, navigating to chat for reconnect',
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConnectionScreen(
                          deviceName: connectionDeviceName,
                          ipAddress: d.ip,
                          port: DiscoveryService.p2pPort,
                          myDeviceName: widget.myDeviceName,
                          connectionManager: cm,
                          initialDeviceId: connectionDeviceName,
                        ),
                      ),
                    );
                    return;
                  }
                }

                // Not connected or disconnected - show confirmation dialog
                debugPrint(
                  '[HomeScreen] Showing connection dialog for ${d.name}',
                );
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
                            icon: _isRestartingServices
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
                            onPressed: _isRestartingServices
                                ? null
                                : () async {
                                    setState(() {
                                      _isRestartingServices = true;
                                    });

                                    // Show loading indicator
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Restarting all services...',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        duration: Duration(seconds: 3),
                                      ),
                                    );

                                    try {
                                      // Check web server status
                                      final portInUse =
                                          await WebServer.isPortInUse();
                                      if (portInUse) {
                                        debugPrint(
                                          '[HomeScreen] Web server detected on port 8080, stopping it...',
                                        );
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Stopping web server...',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            duration: Duration(seconds: 1),
                                          ),
                                        );

                                        // Force stop the web server
                                        final stopped =
                                            await WebServer.forceStop();
                                        if (stopped) {
                                          debugPrint(
                                            '[HomeScreen] Web server force stopped successfully',
                                          );
                                        } else {
                                          debugPrint(
                                            '[HomeScreen] Failed to force stop web server',
                                          );
                                        }

                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Web server stopped',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            duration: Duration(seconds: 1),
                                          ),
                                        );
                                      }

                                      // Restart device discovery using the existing service
                                      await widget.discoveryService
                                          .restartDiscovery();

                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Services restarted successfully',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    } catch (e) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to restart services: $e',
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          duration: const Duration(seconds: 3),
                                        ),
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _isRestartingServices = false;
                                        });
                                      }
                                    }
                                  },
                            tooltip: 'Restart All Services',
                          ),
                          const SizedBox(width: AppSizes.sm),
                          _buildConnectedDevicesButton(),
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
                            // Check if web server is already running
                            final isRunning = await WebServer.isPortInUse();
                            if (isRunning) {
                              // Navigate directly to link share screen
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => WebShareScreen(
                                    deviceName: widget.myDeviceName,
                                    discoveryService: widget.discoveryService,
                                  ),
                                ),
                              );
                            } else {
                              // Navigate to link share screen (it will start the server)
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => WebShareScreen(
                                    deviceName: widget.myDeviceName,
                                    discoveryService: widget.discoveryService,
                                  ),
                                ),
                              );
                            }
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

  Widget _buildConnectedDevicesButton() {
    final cm = widget.discoveryService.connectionManager;
    // Count only truly connected devices (not disconnected/failed)
    final connectedCount =
        cm?.activeConnections.values
            .where((service) => service.isConnected)
            .length ??
        0;

    return Badge(
      label: Text(connectedCount.toString()),
      child: IconButton(
        onPressed: connectedCount > 0
            ? () => _showConnectedDevicesDialog()
            : null,
        icon: Icon(
          Icons.devices,
          color: AppColors.primary,
          size: AppSizes.iconMd,
        ),
        tooltip: 'Connected Devices ($connectedCount)',
      ),
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

    debugPrint(
      '[HomeScreen] ============ Opening connected devices bottom sheet ============',
    );
    debugPrint(
      '[HomeScreen] Active connections count: ${connectionManager.activeConnections.length}',
    );
    debugPrint(
      '[HomeScreen] Connection keys: ${connectionManager.activeConnections.keys.join(", ")}',
    );
    for (final entry in connectionManager.activeConnections.entries) {
      debugPrint(
        '[HomeScreen]   ${entry.key}: status=${entry.value.currentConnection?.status}, isConnected=${entry.value.isConnected}',
      );
    }

    // Force a rebuild to update the badge count
    if (mounted) {
      setState(() {
        debugPrint('[HomeScreen] Forcing rebuild before showing sheet');
      });
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _ConnectedDevicesBottomSheet(
          connectionManager: connectionManager,
          onDeviceTap: _navigateToDeviceChat,
        );
      },
    );
  }

  void _navigateToDeviceChat(String deviceId) {
    final connectionManager = widget.discoveryService.connectionManager;
    if (connectionManager == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConnectionScreen(
          deviceName: deviceId,
          ipAddress: '', // Will be handled by the connection service
          port: DiscoveryService.p2pPort,
          myDeviceName: widget.myDeviceName,
          connectionManager: connectionManager,
          initialDeviceId: deviceId,
        ),
      ),
    );
  }
}

// Stateful bottom sheet widget that rebuilds when connection states change
class _ConnectedDevicesBottomSheet extends StatefulWidget {
  final ConnectionManager connectionManager;
  final Function(String) onDeviceTap;

  const _ConnectedDevicesBottomSheet({
    required this.connectionManager,
    required this.onDeviceTap,
  });

  @override
  State<_ConnectedDevicesBottomSheet> createState() =>
      _ConnectedDevicesBottomSheetState();
}

class _ConnectedDevicesBottomSheetState
    extends State<_ConnectedDevicesBottomSheet> {
  late List<MapEntry<String, ConnectionService>> _entries;
  Function(String, ConnectionService, bool)? _connectionListener;
  final Map<String, Function(ConnectionInfo)> _statusListeners = {};

  @override
  void initState() {
    super.initState();
    debugPrint('[ConnectedDevicesSheet] ============ INIT STATE ============');
    debugPrint(
      '[ConnectedDevicesSheet] Active connections count: ${widget.connectionManager.activeConnections.length}',
    );
    debugPrint(
      '[ConnectedDevicesSheet] Connection keys: ${widget.connectionManager.activeConnections.keys.join(", ")}',
    );
    for (final entry in widget.connectionManager.activeConnections.entries) {
      debugPrint(
        '[ConnectedDevicesSheet]   - ${entry.key}: status=${entry.value.currentConnection?.status}, isConnected=${entry.value.isConnected}',
      );
    }
    _updateEntries();

    // Listen for new connections
    _connectionListener = (deviceName, service, isIncoming) {
      debugPrint(
        '[ConnectedDevicesSheet] New connection listener fired for $deviceName',
      );
      if (mounted) {
        _updateEntries();
        // Add status listener for this new connection
        _addStatusListener(deviceName, service);
      }
    };
    widget.connectionManager.addConnectionListener(_connectionListener!);

    // Add status listeners for existing connections
    for (final entry in _entries) {
      debugPrint(
        '[ConnectedDevicesSheet] Adding status listener for existing connection: ${entry.key}',
      );
      _addStatusListener(entry.key, entry.value);
    }
  }

  void _addStatusListener(String deviceId, ConnectionService service) {
    if (_statusListeners.containsKey(deviceId)) return;

    void listener(ConnectionInfo info) {
      debugPrint(
        '[ConnectedDevicesSheet] Status changed for $deviceId: ${info.status}',
      );
      if (mounted) {
        _updateEntries();
      }
    }
    _statusListeners[deviceId] = listener;
    service.addStatusListener(listener);
  }

  void _updateEntries() {
    if (!mounted) return;
    setState(() {
      _entries = widget.connectionManager.activeConnections.entries.toList();
      debugPrint(
        '[ConnectedDevicesSheet] Updated entries: ${_entries.length} devices',
      );
      for (final entry in _entries) {
        debugPrint(
          '[ConnectedDevicesSheet]   Entry: ${entry.key}, status=${entry.value.currentConnection?.status}',
        );
      }
    });
  }

  @override
  void dispose() {
    if (_connectionListener != null) {
      widget.connectionManager.removeConnectionListener(_connectionListener!);
    }
    // Remove all status listeners
    for (final entry in _statusListeners.entries) {
      final service = widget.connectionManager.getConnection(entry.key);
      if (service != null) {
        service.removeStatusListener(entry.value);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Connected Devices',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_entries.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'No devices connected',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final deviceId = _entries[index].key;
                      final connection = _entries[index].value;
                      final status = connection.currentConnection?.status;
                      final connected = connection.isConnected;

                      // Determine status display
                      String statusText;
                      Color statusColor;
                      IconData statusIcon;

                      if (status == ConnectionStatus.connected) {
                        statusText = 'Connected';
                        statusColor = Colors.green;
                        statusIcon = Icons.wifi;
                      } else if (status == ConnectionStatus.connecting) {
                        statusText = 'Connecting...';
                        statusColor = Colors.blue;
                        statusIcon = Icons.sync;
                      } else if (status == ConnectionStatus.disconnected) {
                        statusText = 'Disconnected';
                        statusColor = Colors.orange;
                        statusIcon = Icons.wifi_off;
                      } else if (status == ConnectionStatus.failed) {
                        statusText = 'Failed';
                        statusColor = Colors.red;
                        statusIcon = Icons.error_outline;
                      } else {
                        statusText = 'Unknown';
                        statusColor = Colors.grey;
                        statusIcon = Icons.help_outline;
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: statusColor,
                          child: Icon(statusIcon, color: Colors.white),
                        ),
                        title: Text(
                          deviceId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          statusText,
                          style: TextStyle(color: statusColor),
                        ),
                        trailing: connected
                            ? IconButton(
                                icon: const Icon(Icons.chat_bubble_outline),
                                tooltip: 'Open Chat',
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onDeviceTap(deviceId);
                                },
                              )
                            : IconButton(
                                icon: const Icon(Icons.refresh),
                                tooltip: 'Reconnect',
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onDeviceTap(deviceId);
                                },
                              ),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onDeviceTap(deviceId);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
