import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cpft/core/constants/app_colors.dart';
import 'package:cpft/core/constants/app_sizes.dart';
import 'package:cpft/features/home/helpers/device_position.dart';
import 'package:cpft/features/home/helpers/device_dot_layout_helper.dart';
import 'package:cpft/features/home/helpers/connection_handler.dart';
import 'package:cpft/features/home/helpers/service_restart_handler.dart';
import 'package:cpft/services/discovery_service.dart';
import 'package:cpft/utils/network_utils.dart';
import 'package:cpft/utils/permissions.dart';
import 'package:cpft/features/home/controllers/home_controller.dart';
import 'package:cpft/features/home/presentation/widgets/radar_view.dart';
import 'package:cpft/features/home/presentation/widgets/device_dot.dart';
import 'package:cpft/features/home/presentation/widgets/network_banner.dart';
import 'package:cpft/features/home/presentation/widgets/link_share_button.dart';
import 'package:cpft/features/home/presentation/widgets/home_app_bar.dart';
import 'package:cpft/features/home/presentation/widgets/connected_devices_sheet.dart';
import 'package:cpft/features/home/presentation/widgets/incoming_request_dialog.dart';
import 'package:cpft/shared/widgets/dialog_helpers.dart' as app_dialog;
import 'package:cpft/features/chat/presentation/connection_screen_refactored.dart';
import 'package:cpft/features/webshare/presentation/webshare_screen.dart';
import 'package:cpft/features/chat/services/connection_service.dart';

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
  final Set<String> _pendingIncoming = {};
  String? _localIp;
  Function(String, ConnectionService, bool)? _connectionListener;
  Timer? _networkCheckTimer;

  @override
  void initState() {
    super.initState();
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ConnectionScreenRefactored(
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
      }

      // Listen for status changes
      service.addStatusListener((info) {
        if (mounted) setState(() {});
      });

      if (mounted) setState(() {});
    };

    cm.addConnectionListener(_connectionListener!);
    debugPrint('[HomeScreen] 🎯 Connection listener registered successfully');
  }

  @override
  void dispose() {
    _networkCheckTimer?.cancel();
    widget.discoveryService.removeIncomingRequestListener(_onIncomingRequest);
    if (_connectionListener != null) {
      widget.discoveryService.connectionManager?.removeConnectionListener(
        _connectionListener!,
      );
    }
    controller.dispose();
    super.dispose();
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
    _networkCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final oldNetworkName = _networkName;
      await _initializeNetworkName();

      final isNowDisconnected = _networkName == 'Not Connected';
      final wasDisconnected = oldNetworkName == 'Not Connected';

      if (isNowDisconnected && !wasDisconnected) {
        widget.discoveryService.clearDevices();
        controller.pauseRadar();
        if (mounted) setState(() {});
      } else if (!isNowDisconnected && wasDisconnected) {
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
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hasNetwork =
            _networkName != null && _networkName != 'Not Connected';
        final devices = hasNetwork
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
                  NetworkBanner(networkName: _networkName),
                  const SizedBox(height: AppSizes.lg),
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.lg),
                    child: _buildLinkShareSection(),
                  ),
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
            style: Theme.of(context).textTheme.bodyMedium,
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

  Widget _buildLinkShareSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinkShareButton(
          onPressed: () async {
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
          },
        ),
        const SizedBox(height: AppSizes.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
          child: Text(
            'App not installed on other device? use link share',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.greyLight),
          ),
        ),
      ],
    );
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return ConnectedDevicesBottomSheet(
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
        builder: (context) => ConnectionScreenRefactored(
          deviceName: deviceId,
          ipAddress: '',
          port: DiscoveryService.p2pPort,
          myDeviceName: widget.myDeviceName,
          connectionManager: connectionManager,
          initialDeviceId: deviceId,
        ),
      ),
    );
  }
}
