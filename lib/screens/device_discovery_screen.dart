import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  Map<String, String> _discoveredDevices = {};

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
      final hasPermission = await AppPermissions.requestNetworkPermissions();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Network permissions are required for device discovery'),
            ),
          );
        }
        return;
      }

      print('Initializing LocalSend-style discovery...');
      await _discoveryService.initialize();
      _discoveryService.addDiscoveryListener(_onDeviceDiscovered);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }

      print('Discovery initialized successfully!');
    } catch (e) {
      print('Failed to initialize discovery: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize device discovery: $e'),
          ),
        );
      }
    }
  }

  void _onDeviceDiscovered(String deviceName, String ipAddress, int port) {
    print('[UI] 🟢 UI CALLBACK RECEIVED! Device: $deviceName at $ipAddress:$port');
    print('[UI] Current widget mounted state: $mounted');
    print('[UI] Current discovered devices count: ${_discoveredDevices.length}');
    
    if (mounted) {
      setState(() {
        _discoveredDevices[deviceName] = ipAddress;
        print('[UI] ✅ setState called - device added to map');
        print('[UI] New discovered devices count: ${_discoveredDevices.length}');
      });
      print('[UI] ✅ UI updated: Device discovered - $deviceName at $ipAddress:$port');
    } else {
      print('[UI] ⚠️  Widget not mounted - cannot update UI');
    }
  }

  Future<void> _refreshDiscovery() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _discoveredDevices.clear();
    });

    try {
      print('[UI] 🔄 Refresh triggered - clearing devices and re-scanning...');
      
      // Clear the discovery service's device list
      _discoveryService.clearDevices();
      
      // Wait a bit for the clear to propagate
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Force a re-announcement (this will work on Android/macOS, not iOS)
      await _discoveryService.announce();
      
      // On iOS, Bonjour is continuously running, so we just need to wait
      // for devices to be re-discovered from the ongoing Bonjour discovery
      // and incoming multicast messages
      if (Platform.isIOS) {
        print('[UI] 📱 iOS: Waiting for Bonjour re-discovery...');
        // Give Bonjour time to trigger discovery events
        await Future.delayed(const Duration(milliseconds: 1500));
      } else {
        // On other platforms, multicast announcements will trigger discoveries
        await Future.delayed(const Duration(milliseconds: 800));
      }
      
      print('[UI] ✅ Refresh complete - found ${_discoveredDevices.length} devices');
    } catch (e) {
      print('[UI] ❌ Refresh error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh failed: $e')),
        );
      }
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
          // VPN Warning Banner (iOS only)
          if (_isInitialized && _discoveryService.isVpnDetected && Platform.isIOS)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade900),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VPN Detected',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'iOS blocks multicast when VPN is active. Please disconnect VPN in Settings.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          // Status badges
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _buildStatusBadge(
                  icon: _isInitialized ? Icons.wifi : Icons.wifi_off,
                  label: _isInitialized ? 'Discovering' : 'Initializing',
                  color: _isInitialized ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(
                  icon: Icons.screen_lock_portrait,
                  label: 'Screen stays on',
                  color: Colors.blue,
                ),
              ],
            ),
          ),
          
          // Device count
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
                ? _buildEmptyState()
                : _buildDeviceList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
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
            _isInitialized ? 'No devices found' : 'Initializing discovery...',
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
    );
  }

  Widget _buildDeviceList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _discoveredDevices.length,
      itemBuilder: (context, index) {
        final deviceName = _discoveredDevices.keys.elementAt(index);
        final ipAddress = _discoveredDevices[deviceName]!;
        return _buildDeviceCard(deviceName, ipAddress);
      },
    );
  }

  Widget _buildDeviceCard(String deviceName, String ipAddress) {
    // Extract device type from name (e.g., "iPhone-xxx", "Mac-xxx", "Android-xxx")
    final deviceInfo = _parseDeviceName(deviceName);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      child: InkWell(
        onTap: () => _onDeviceSelected(deviceName, ipAddress),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: deviceInfo['color'].withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  deviceInfo['icon'],
                  color: deviceInfo['color'],
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            deviceInfo['displayName'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: deviceInfo['color'].withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            deviceInfo['platform'],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: deviceInfo['color'],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.router, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          ipAddress,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
  }
  
  /// Parse device name to extract platform and display information
  Map<String, dynamic> _parseDeviceName(String deviceName) {
    IconData icon = Icons.devices;
    Color color = Colors.blue;
    String platform = 'Unknown';
    String displayName = deviceName;
    
    if (deviceName.startsWith('iPhone-')) {
      icon = Icons.phone_iphone;
      color = Colors.black;
      platform = 'iOS';
      displayName = deviceName.substring(7); // Remove "iPhone-" prefix
    } else if (deviceName.startsWith('Android-')) {
      icon = Icons.phone_android;
      color = Colors.green;
      platform = 'Android';
      displayName = deviceName.substring(8); // Remove "Android-" prefix
    } else if (deviceName.startsWith('Mac-')) {
      icon = Icons.computer;
      color = Colors.blueGrey;
      platform = 'macOS';
      displayName = deviceName.substring(4); // Remove "Mac-" prefix
    } else if (deviceName.startsWith('Windows-')) {
      icon = Icons.desktop_windows;
      color = Colors.indigo;
      platform = 'Windows';
      displayName = deviceName.substring(8); // Remove "Windows-" prefix
    } else if (deviceName.startsWith('Linux-')) {
      icon = Icons.computer;
      color = Colors.orange;
      platform = 'Linux';
      displayName = deviceName.substring(6); // Remove "Linux-" prefix
    } else if (deviceName.startsWith('cpft-')) {
      // Legacy format - try to determine from hostname
      displayName = deviceName.substring(5); // Remove "cpft-" prefix
    }
    
    return {
      'icon': icon,
      'color': color,
      'platform': platform,
      'displayName': displayName,
    };
  }

  void _onDeviceSelected(String deviceName, String ipAddress) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Selected $deviceName ($ipAddress)'),
        action: SnackBarAction(
          label: 'Connect',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Connection feature coming soon!')),
            );
          },
        ),
      ),
    );
  }
}
