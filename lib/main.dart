import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'utils/permissions.dart';
import 'helpers/local_network_permission_helper.dart';
import 'services/discovery_service.dart';
import 'services/notification_service.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/chat/presentation/chat_screen.dart';
import 'features/chat/services/connection_service.dart';
import 'common/theme/theme/app_theme.dart';
import 'features/setup/presentation/device_name_setup_screen.dart';
import 'features/webshare/presentation/web_room_entry_screen.dart';
import 'package:cpft/core/logging/app_logger.dart';
import 'firebase_options.dart';
import 'services/firebase_initializer.dart';
import 'widgets/firebase_status_banner.dart';

// Global navigator key for navigation from anywhere (e.g., notifications)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global reference to discovery service for notification handling
DiscoveryService? globalDiscoveryService;
String? globalDeviceName;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase early and robustly; log but don't block UI on failure
  try {
    await FirebaseInitializer.ensure();
  } catch (_) {}
  
  // Clean up old received files on Android (async, don't block app startup)
  ConnectionService.cleanupOldReceivedFiles().catchError((e) {
    debugPrint('[Main] Startup cleanup error: $e');
  });
  
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (context) => MaterialApp(
      title: 'CPFT',
      theme: AppTheme.lightTheme,
      navigatorKey: navigatorKey,
      // On web, only show the WebShare (WebRTC) screen
      initialRoute: kIsWeb ? '/webshare' : '/',
      routes: {
        '/': (context) => const PermissionWrapper(),
        '/setup': (context) => const DeviceNameSetupScreen(),
        '/home': (context) => const HomeWrapper(),
        '/webshare': (context) => const WebRoomEntryScreen(),
      },
      builder: (context, child) {
        final content = Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE2F6FB), Color(0xFFFFFFFF)],
              stops: [0.0, 1.0],
            ),
          ),
          child: child,
        );
        return Stack(
          children: [
            content, 
            // FirebaseStatusBanner(),
          ],
        );
      },
    ),
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
  DiscoveryService? _discoveryService;

  @override
  void initState() {
    super.initState();
    _loadDeviceName();
  }

  @override
  void dispose() {
    _discoveryService?.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('device_name');
    if (name != null && name.isNotEmpty) {
      if (mounted) {
        setState(() {
          _deviceName = name;
        });
      }
      // Create discovery service once we have the device name
      _initializeDiscoveryService(name);
    } else {
      // This should not happen since PermissionWrapper already checked
      // But as a safety net, redirect to setup
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/setup');
      }
    }
  }

  void _initializeDiscoveryService(String deviceName) {
    final platformName = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
    _discoveryService = DiscoveryService(
      alias: deviceName,
      deviceModel: platformName,
      port: 53317,
    );
    // Store globally for notification handler
    globalDiscoveryService = _discoveryService;
    globalDeviceName = deviceName;
    // Set up notification tap handler
    _setupNotificationHandler();
  }
  
  void _setupNotificationHandler() {
    debugPrint('[HomeWrapper] Setting up notification handler');
    NotificationService().onNotificationTap = (String deviceName, String transferId) async {
      debugPrint('[HomeWrapper] ========================================');
      debugPrint('[HomeWrapper] Notification callback triggered!');
      debugPrint('[HomeWrapper] Device: $deviceName, Transfer: $transferId');
      debugPrint('[HomeWrapper] globalDiscoveryService is null: ${globalDiscoveryService == null}');
      debugPrint('[HomeWrapper] globalDeviceName: $globalDeviceName');
      
      final cm = globalDiscoveryService?.connectionManager;
      debugPrint('[HomeWrapper] ConnectionManager is null: ${cm == null}');
      
      if (cm == null) {
        debugPrint('[HomeWrapper] ERROR: ConnectionManager not available');
        return;
      }
      
      final connection = cm.getConnection(deviceName);
      debugPrint('[HomeWrapper] Connection found: ${connection != null}');
      
      if (connection == null) {
        debugPrint('[HomeWrapper] ERROR: No connection found for $deviceName');
        debugPrint('[HomeWrapper] Available connections: ${cm.activeConnections.keys.toList()}');
        return;
      }
      
      // Navigate using global navigator key
      final context = navigatorKey.currentContext;
      debugPrint('[HomeWrapper] Navigator context available: ${context != null}');
      
      if (context != null) {
        debugPrint('[HomeWrapper] Navigating to ConnectionScreenRefactored...');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              deviceName: deviceName,
              ipAddress: connection.currentConnection?.ipAddress ?? '',
              port: DiscoveryService.p2pPort,
              myDeviceName: globalDeviceName ?? '',
              connectionManager: cm,
              initialDeviceId: deviceName,
            ),
          ),
        );
        debugPrint('[HomeWrapper] Navigation pushed successfully');
      } else {
        debugPrint('[HomeWrapper] ERROR: No navigator context available');
      }
      debugPrint('[HomeWrapper] ========================================');
    };
    debugPrint('[HomeWrapper] Notification handler setup complete');
  }

  @override
  Widget build(BuildContext context) {
    if (_deviceName == null || _discoveryService == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return HomeScreen(
      discoveryService: _discoveryService!,
      myDeviceName: _deviceName!,
    );
  }
}

class PermissionWrapper extends StatefulWidget {
  const PermissionWrapper({super.key});

  @override
  State<PermissionWrapper> createState() => _PermissionWrapperState();
}

class _PermissionWrapperState extends State<PermissionWrapper> with WidgetsBindingObserver {
  bool _permissionsGranted = false;
  bool _isCheckingPermissions = true;
  bool _locationServiceDisabled = false;
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app resumes from background (e.g., returning from Settings), re-check permissions
    if (state == AppLifecycleState.resumed && (!_permissionsGranted || _locationServiceDisabled)) {
      AppLogger.d('App resumed - re-checking permissions', tag: 'PermWrap');
      _checkPermissions();
    }
  }

  Future<void> _initialize() async {
    AppLogger.d('PermissionWrapper _initialize called', tag: 'PermWrap');

    // Initialize notification service
    await NotificationService().initialize();
    await NotificationService().requestPermissions();

    await _checkPermissions();
    _deviceName = await _getDeviceName();
    AppLogger.d('Device name loaded: $_deviceName', tag: 'PermWrap');
    
    // If device name not set: on web, use a dummy name; on mobile, navigate to setup.
    if (_deviceName == null) {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('device_name', 'WebClient');
        _deviceName = 'WebClient';
        AppLogger.d('Web: using dummy device name WebClient', tag: 'PermWrap');
      } else {
        AppLogger.d('Navigating to setup screen', tag: 'PermWrap');
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/setup');
        }
      }
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkPermissions() async {
    if (mounted) {
      setState(() {
        _isCheckingPermissions = true;
        _locationServiceDisabled = false;
      });
    }

    // Check if location services are enabled
    final serviceEnabled = await AppPermissions.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _locationServiceDisabled = true;
          _permissionsGranted = false;
          _isCheckingPermissions = false;
        });
      }
      return;
    }

    final granted = await AppPermissions.requestNetworkPermissions();
    AppLogger.d('Permissions granted: $granted', tag: 'PermWrap');
    
    // For iOS, also show Local Network permission instructions
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await LocalNetworkPermissionHelper.requestPermission();
    }

    if (mounted) {
      setState(() {
        _permissionsGranted = granted;
        _isCheckingPermissions = false;
      });
    }
  }

  Future<String?> _getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('device_name');
    if (name != null && name.isNotEmpty) {
      return name;
    }
    // On web, prefer a dummy without forcing navigation
    if (kIsWeb) return null; // handled in _initialize
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
      final isServiceDisabled = _locationServiceDisabled;
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isServiceDisabled ? Icons.location_off : Icons.location_on,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                Text(
                    isServiceDisabled
                      ? 'Location Services Disabled'
                      : 'Location Permission Required',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                    isServiceDisabled
                      ? 'Please enable Location Services in your device settings to use this app. WiFi network detection requires location services to be turned on.'
                      : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                        ? 'On Android 10+, location permission is required to detect your WiFi network name. This helps you confirm you\'re connected to the right network for file transfers.'
                        : 'Location permission is needed to detect your WiFi network name and discover nearby devices on your local network.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                if (!isServiceDisabled) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Note: Your location data is never collected or shared. This permission only allows the app to read your WiFi name.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: isServiceDisabled
                      ? AppPermissions.openSystemLocationSettings
                      : _checkPermissions,
                  child: Text(isServiceDisabled
                      ? 'Open Location Settings'
                      : 'Grant Permission'),
                ),
                if (!isServiceDisabled) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: AppPermissions.openLocationSettings,
                    child: const Text('Open Settings'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // If device name is set, show home screen
    if (_deviceName != null) {
      AppLogger.i('Creating HomeScreen with device name: $_deviceName', tag: 'PermWrap');
      final platformName = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
      final discovery = DiscoveryService(
        alias: _deviceName!,
        deviceModel: platformName,
        port: 53317,
      );
      // Store globally for notification handler
      globalDiscoveryService = discovery;
      globalDeviceName = _deviceName;
      // Set up notification handler
      _setupNotificationHandler();
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
  
  void _setupNotificationHandler() {
    debugPrint('[PermissionWrapper] Setting up notification handler');
    NotificationService().onNotificationTap = (String deviceName, String transferId) async {
      debugPrint('[PermissionWrapper] ========================================');
      debugPrint('[PermissionWrapper] Notification callback triggered!');
      debugPrint('[PermissionWrapper] Device: $deviceName, Transfer: $transferId');
      debugPrint('[PermissionWrapper] globalDiscoveryService is null: ${globalDiscoveryService == null}');
      
      final cm = globalDiscoveryService?.connectionManager;
      debugPrint('[PermissionWrapper] ConnectionManager is null: ${cm == null}');
      
      if (cm == null) {
        debugPrint('[PermissionWrapper] ERROR: ConnectionManager not available');
        return;
      }
      
      final connection = cm.getConnection(deviceName);
      debugPrint('[PermissionWrapper] Connection found: ${connection != null}');
      
      if (connection == null) {
        debugPrint('[PermissionWrapper] ERROR: No connection found for $deviceName');
        debugPrint('[PermissionWrapper] Available connections: ${cm.activeConnections.keys.toList()}');
        return;
      }
      
      // Navigate using global navigator key
      final context = navigatorKey.currentContext;
      debugPrint('[PermissionWrapper] Navigator context available: ${context != null}');
      
      if (context != null) {
        debugPrint('[PermissionWrapper] Navigating to ConnectionScreenRefactored...');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              deviceName: deviceName,
              ipAddress: connection.currentConnection?.ipAddress ?? '',
              port: DiscoveryService.p2pPort,
              myDeviceName: globalDeviceName ?? '',
              connectionManager: cm,
              initialDeviceId: deviceName,
            ),
          ),
        );
        debugPrint('[PermissionWrapper] Navigation pushed successfully');
      } else {
        debugPrint('[PermissionWrapper] ERROR: No navigator context available');
      }
      debugPrint('[PermissionWrapper] ========================================');
    };
    debugPrint('[PermissionWrapper] Notification handler setup complete');
  }
}