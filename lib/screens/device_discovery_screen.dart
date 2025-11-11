import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/discovery_service.dart';
import '../utils/permissions.dart';
import 'connection_screen.dart';

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
  // Track pending incoming prompts to avoid duplicates
  final Set<String> _pendingIncoming = {};

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
  // Listen for incoming connection requests (pre-accept)
  _discoveryService.addIncomingRequestListener(_onIncomingRequest);

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

  void _onIncomingRequest(
    String deviceName,
    String ipAddress,
    int port,
    Future<void> Function() accept,
    Future<void> Function() decline,
  ) async {
    if (_pendingIncoming.contains(deviceName)) return;
    _pendingIncoming.add(deviceName);
    await _handleIncomingConnectionUI(deviceName, ipAddress, port, accept, decline);
  }

  Future<void> _handleIncomingConnectionUI(
    String deviceName,
    String ipAddress,
    int port,
    Future<void> Function() accept,
    Future<void> Function() decline,
  ) async {
    if (!mounted) return;

    // If you prefer auto-open, you can short-circuit here by pushing without dialog.
    // For now, show a prompt so user can accept/decline.
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Incoming chat request'),
          content: Text('$deviceName wants to chat.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Decline'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );

    _pendingIncoming.remove(deviceName);

    if (result == true && mounted) {
      // Accept the socket and then open chat
      await accept();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConnectionScreen(
            deviceName: deviceName,
            ipAddress: ipAddress,
            port: port,
            myDeviceName: widget.deviceName,
            connectionManager: _discoveryService.connectionManager!,
          ),
        ),
      );
    } else if (result == false) {
      // Declined: close the socket
      await decline();
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
  _discoveryService.removeIncomingRequestListener(_onIncomingRequest);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // This Device Info Card
                Card(
                  elevation: 1,
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Icon(Icons.smartphone, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'This Device',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.deviceName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Status badges row - scrollable to prevent overflow
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatusBadge(
                        icon: _isInitialized ? Icons.wifi : Icons.wifi_off,
                        label: _isInitialized ? 'Discovering' : 'Initializing',
                        color: _isInitialized ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(
                        icon: Icons.link,
                        label: 'Ready to connect',
                        color: _isInitialized ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(
                        icon: Icons.screen_lock_portrait,
                        label: 'Screen on',
                        color: Colors.blue,
                      ),
                    ],
                  ),
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
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: deviceInfo['color'].withOpacity(0.15),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: deviceInfo['color'].withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  deviceInfo['icon'],
                  color: deviceInfo['color'],
                  size: 26,
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
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Platform badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: deviceInfo['color'].withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: deviceInfo['color'].withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            deviceInfo['platform'],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: deviceInfo['color'],
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        // Device ID badge (if available)
                        if (deviceInfo['deviceId'] != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fingerprint, size: 10, color: Colors.grey[700]),
                                const SizedBox(width: 3),
                                Text(
                                  deviceInfo['deviceId'],
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.wifi, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          ipAddress,
                          style: TextStyle(
                            fontSize: 12,
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
    print('[UI] 🔍 Parsing device name: "$deviceName"');
    
    IconData icon = Icons.devices;
    Color color = Colors.blue;
    String platform = 'Unknown';
    String displayName = deviceName;
    String? deviceId;
    
    // Extract device ID if present (last 4 digits after last hyphen)
    final parts = deviceName.split('-');
    print('[UI] 📊 Split into ${parts.length} parts: $parts');
    
    if (parts.length > 1 && parts.last.length == 4 && int.tryParse(parts.last) != null) {
      deviceId = parts.last;
      print('[UI] ✅ Extracted device ID: $deviceId');
      // Rebuild device name without the ID for display
      final nameWithoutId = parts.sublist(0, parts.length - 1).join('-');
      deviceName = nameWithoutId;
      print('[UI] 📝 Device name without ID: "$deviceName"');
    } else {
      print('[UI] ⚠️  No valid device ID found (last part: "${parts.last}", length: ${parts.last.length})');
    }
    
    if (deviceName.startsWith('iPhone-')) {
      icon = Icons.phone_iphone;
      color = const Color(0xFF000000); // Apple Black
      platform = 'iOS';
      displayName = deviceName.substring(7); // Remove "iPhone-" prefix
    } else if (deviceName.startsWith('Android-')) {
      icon = Icons.phone_android;
      color = const Color(0xFF3DDC84); // Android Green
      platform = 'Android';
      displayName = deviceName.substring(8); // Remove "Android-" prefix
    } else if (deviceName.startsWith('Mac-')) {
      icon = Icons.laptop_mac;
      color = const Color(0xFF0071E3); // Apple Blue
      platform = 'macOS';
      displayName = deviceName.substring(4); // Remove "Mac-" prefix
    } else if (deviceName.startsWith('Windows-')) {
      icon = Icons.desktop_windows;
      color = const Color(0xFF0078D4); // Windows Blue
      platform = 'Windows';
      displayName = deviceName.substring(8); // Remove "Windows-" prefix
    } else if (deviceName.startsWith('Linux-')) {
      icon = Icons.computer;
      color = const Color(0xFFFF6600); // Linux Orange
      platform = 'Linux';
      displayName = deviceName.substring(6); // Remove "Linux-" prefix
    } else if (deviceName.startsWith('cpft-')) {
      // Legacy format - try to determine from hostname
      displayName = deviceName.substring(5); // Remove "cpft-" prefix
      platform = 'Legacy';
      color = Colors.grey;
    }
    
    // Clean up display name
    displayName = displayName
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();
    
    // Capitalize each word
    if (displayName.isNotEmpty) {
      displayName = displayName.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }
    
    return {
      'icon': icon,
      'color': color,
      'platform': platform,
      'displayName': displayName,
      'deviceId': deviceId,
    };
  }

  void _onDeviceSelected(String deviceName, String ipAddress) {
    print('[UI] 🔌 Device selected: $deviceName at $ipAddress');
    
    // Get connection manager from discovery service
    final connectionManager = _discoveryService.connectionManager;
    if (connectionManager == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection service not ready. Please wait...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Navigate to connection screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConnectionScreen(
          deviceName: deviceName,
          ipAddress: ipAddress,
          port: 53318, // Use P2P port
          myDeviceName: widget.deviceName,
          connectionManager: connectionManager,
        ),
      ),
    );
  }
}
