import 'dart:io';
import 'package:flutter/material.dart';
import 'screens/device_discovery_screen.dart';
import 'utils/permissions.dart';
import 'helpers/local_network_permission_helper.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mDNS Discovery Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PermissionWrapper(),
    );
  }
}

class PermissionWrapper extends StatefulWidget {
  const PermissionWrapper({super.key});

  @override
  State<PermissionWrapper> createState() => _PermissionWrapperState();
}

class _PermissionWrapperState extends State<PermissionWrapper> {
  bool _permissionsGranted = false;
  bool _isCheckingPermissions = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() {
      _isCheckingPermissions = true;
    });

    final granted = await AppPermissions.requestNetworkPermissions();
    
    // For iOS, also show Local Network permission instructions
    if (Platform.isIOS) {
      await LocalNetworkPermissionHelper.requestPermission();
    }

    setState(() {
      _permissionsGranted = granted;
      _isCheckingPermissions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermissions) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking permissions...'),
            ],
          ),
        ),
      );
    }

    if (!_permissionsGranted) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Permissions Required',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This app needs network permissions to discover devices on your local network.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _checkPermissions,
                  child: const Text('Grant Permissions'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: AppPermissions.openSettingsIfNeeded,
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DeviceDiscoveryScreen(
      deviceName: _getUniqueDeviceName(),
    );
  }
  
  /// Generate a unique and identifiable device name
  String _getUniqueDeviceName() {
    final hostname = Platform.localHostname;
    
    // Extract a cleaner hostname
    String cleanHostname = hostname;
    
    // Remove .local suffix if present
    if (cleanHostname.endsWith('.local')) {
      cleanHostname = cleanHostname.substring(0, cleanHostname.length - 6);
    }
    
    // Remove common suffixes and clean up
    cleanHostname = cleanHostname
        .replaceAll('.', '-')
        .replaceAll('_', '-')
        .replaceAll(' ', '-');
    
    // Generate a unique 4-character ID based on hostname hash
    // Ensure it's always exactly 4 digits by padding with zeros if needed
    final hashValue = hostname.hashCode.abs() % 10000; // Ensure max 4 digits
    final uniqueId = hashValue.toString().padLeft(4, '0');
    
    print('[Main] 🏷️  Generated device name components:');
    print('[Main]   - Original hostname: $hostname');
    print('[Main]   - Cleaned hostname: $cleanHostname');
    print('[Main]   - Unique ID: $uniqueId');
    
    // For iOS devices, use a more descriptive name
    if (Platform.isIOS) {
      // iOS devices often have generic hostnames, so add a platform identifier
      final deviceName = 'iPhone-$cleanHostname-$uniqueId';
      print('[Main] ✅ Final device name: $deviceName');
      return deviceName;
    } else if (Platform.isAndroid) {
      final deviceName = 'Android-$cleanHostname-$uniqueId';
      print('[Main] ✅ Final device name: $deviceName');
      return deviceName;
    } else if (Platform.isMacOS) {
      final deviceName = 'Mac-$cleanHostname-$uniqueId';
      print('[Main] ✅ Final device name: $deviceName');
      return deviceName;
    } else if (Platform.isWindows) {
      final deviceName = 'Windows-$cleanHostname-$uniqueId';
      print('[Main] ✅ Final device name: $deviceName');
      return deviceName;
    } else if (Platform.isLinux) {
      final deviceName = 'Linux-$cleanHostname-$uniqueId';
      print('[Main] ✅ Final device name: $deviceName');
      return deviceName;
    }
    
    // Fallback
    final deviceName = 'Device-$cleanHostname-$uniqueId';
    print('[Main] ✅ Final device name: $deviceName');
    return deviceName;
  }
}