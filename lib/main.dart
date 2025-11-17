import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/permissions.dart';
import 'helpers/local_network_permission_helper.dart';
import 'services/discovery_service.dart';
import 'features/home/presentation/home_screen.dart';
import 'common/theme/theme/app_theme.dart';
import 'features/setup/presentation/device_name_setup_screen.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CPFT',
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const PermissionWrapper(),
        '/setup': (context) => const DeviceNameSetupScreen(),
        '/home': (context) => const HomeWrapper(),
      },
    );
  }
}

class HomeWrapper extends StatefulWidget {
  const HomeWrapper({super.key});

  @override
  State<HomeWrapper> createState() => _HomeWrapperState();
}

class _HomeWrapperState extends State<HomeWrapper> {
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    _loadDeviceName();
  }

  Future<void> _loadDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('device_name');
    if (name != null && name.isNotEmpty) {
      setState(() {
        _deviceName = name;
      });
    } else {
      // This should not happen since PermissionWrapper already checked
      // But as a safety net, redirect to setup
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/setup');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_deviceName == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final discovery = DiscoveryService(
      alias: _deviceName!,
      deviceModel: Platform.operatingSystem,
      port: 53317,
    );
    return HomeScreen(
      discoveryService: discovery,
      myDeviceName: _deviceName!,
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
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initialize() async {
    await _checkPermissions();
    _deviceName = await _getDeviceName();
    
    // Navigate based on device name after initialization is complete
    if (_deviceName == null) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/setup');
      }
    }
    
    setState(() {});
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

  Future<String?> _getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('device_name');
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return null;
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
        resizeToAvoidBottomInset: false,
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

    // If device name is set, show home screen
    if (_deviceName != null) {
      final discovery = DiscoveryService(
        alias: _deviceName!,
        deviceModel: Platform.operatingSystem,
        port: 53317,
      );
      return HomeScreen(
        discoveryService: discovery,
        myDeviceName: _deviceName!,
      );
    }

    // If we're still initializing (device name check in progress), show loading
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}