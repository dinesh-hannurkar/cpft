import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:fylooo/shared/widgets/app_snackbar.dart';
import '../services/discovery_service.dart';
import '../utils/permissions.dart';

class DeviceDiscoveryScreen extends StatefulWidget {
  final String deviceName;

  const DeviceDiscoveryScreen({
    super.key,
    required this.deviceName,
  });

  @override
  State<DeviceDiscoveryScreen> createState() => _DeviceDiscoveryScreenState();
}

class _DeviceDiscoveryScreenState extends State<DeviceDiscoveryScreen> {
  late DiscoveryService _discoveryService;
  bool _isInitialized = false;
  bool _isRefreshing = false;
  final Map<String, String> _discoveredDevices = {};

  @override
  void initState() {
    super.initState();
    
    // Enable wakelock to keep screen on during discovery
    WakelockPlus.enable();
    
    _discoveryService = DiscoveryService(
      alias: widget.deviceName,
      deviceModel: Platform.operatingSystem,
      port: 53317,
    );
    _initializeDiscovery();
  }

  Future<void> _initializeDiscovery() async {
    try {
      // Request network permissions
      final hasPermission = await AppPermissions.requestNetworkPermissions();
      if (!hasPermission) {
        if (mounted) {
          AppSnackbar.showWarning(context, 'Network permissions are required for device discovery');
        }
        return;
      }

      debugPrint('Initializing LocalSend-style discovery...');
      await _discoveryService.initialize();
      _discoveryService.addDiscoveryListener(_onDeviceDiscovered);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }

      debugPrint('Discovery initialized successfully!');
    } catch (e) {
      debugPrint('Failed to initialize discovery: $e');
      if (mounted) {
        AppSnackbar.showError(context, 'Failed to initialize device discovery: $e');
      }
    }
  }

  void _onDeviceDiscovered(String deviceName, String ipAddress, int port) {
    if (mounted) {
      setState(() {
        _discoveredDevices[deviceName] = ipAddress;
      });
      debugPrint('UI updated: Device discovered - $deviceName at $ipAddress:$port');
    }
  }

  Future<void> _refreshDiscovery() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _discoveredDevices.clear();
    });

    try {
      _discoveryService.clearDevices();
      await Future.delayed(const Duration(milliseconds: 500));
      await _discoveryService.announce();
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Disable wakelock when leaving the screen
    WakelockPlus.disable();
    
    _discoveryService.removeDiscoveryListener(_onDeviceDiscovered);
    _discoveryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshDiscovery,
            tooltip: 'Refresh device search',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status indicators
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isInitialized ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isInitialized ? Icons.wifi : Icons.wifi_off,
                        size: 18,
                        color: _isInitialized ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isInitialized ? 'Discovering' : 'Initializing',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _isInitialized ? Colors.green[700] : Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.screen_lock_portrait,
                        size: 18,
                        color: Colors.blue[700],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Screen stays on',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  'Found ${_discoveredDevices.length} device${_discoveredDevices.length != 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                if (_isRefreshing) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Device list
          Expanded(
            child: _discoveredDevices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.devices_other,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isInitialized
                              ? 'No devices found'
                              : 'Initializing discovery...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_isInitialized)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48.0),
                            child: Text(
                              'Make sure other devices are running this app on the same WiFi network',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _discoveredDevices.length,
                    itemBuilder: (context, index) {
                      final deviceName = _discoveredDevices.keys.elementAt(index);
                      final ipAddress = _discoveredDevices[deviceName]!;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            // Handle device selection
                            AppSnackbar.showInfo(context, 'Selected $deviceName');
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.devices,
                                    color: Colors.blue[700],
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        deviceName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        ipAddress,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Colors.grey[400],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
