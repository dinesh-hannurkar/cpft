import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
// import 'package:flutter_web_plugins/flutter_web_plugins.dart'
//     if (dart.library.io) 'package:flutter/foundation.dart'
//     as web_plugins; // uncomment when deploying on web
import 'utils/permissions.dart';
import 'helpers/local_network_permission_helper.dart';
import 'services/discovery_service.dart';
import 'services/notification_service.dart';
import 'services/sound_service.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/chat/presentation/chat_screen.dart';
import 'features/chat/services/connection_service.dart';
import 'common/theme/app_theme.dart';
import 'features/setup/presentation/device_name_setup_screen.dart';
import 'features/webshare/presentation/web_room_entry_screen.dart';
import 'features/settings/presentation/privacy_policy_screen.dart';
import 'features/settings/presentation/terms_of_use_screen.dart';
import 'package:fylooo/core/logging/app_logger.dart';
import 'services/firebase_initializer.dart';
import 'services/share_intent_service.dart';
import 'services/update_service_simple.dart';

// Global navigator key for navigation from anywhere (e.g., notifications)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global reference to discovery service for notification handling
DiscoveryService? globalDiscoveryService;
String? globalDeviceName;

// Build-time toggle (no UI):
// `flutter run --dart-define=CPFT_USE_NATIVE_RECEIVER=false`
// Defaults to true.
const bool _kUseNativeReceiver = bool.fromEnvironment(
  'CPFT_USE_NATIVE_RECEIVER',
  defaultValue: false,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Programmatic test switch for receiver I/O path.
  ConnectionService.useNativeReceiver = _kUseNativeReceiver;
  if (kDebugMode) {
    debugPrint(
      '[Main] CPFT_USE_NATIVE_RECEIVER=${ConnectionService.useNativeReceiver}',
    );
  }

  // Enable path-based routing on web (instead of hash-based) //uncomment when deploying on web
  // if (kIsWeb) {
  //   web_plugins.usePathUrlStrategy();
  // }

  // Initialize Firebase early and robustly; log but don't block UI on failure
  try {
    await FirebaseInitializer.ensure();
  } catch (_) {}

  // Initialize sound service
  try {
    await SoundService().init();
  } catch (e) {
    debugPrint('[Main] Sound service initialization error: $e');
  }

  // Clean up old received files on Android (async, don't block app startup)
  ConnectionService.cleanupOldReceivedFiles().catchError((e) {
    debugPrint('[Main] Startup cleanup error: $e');
  });

  // Clean temp directory at startup to remove transient files from previous runs
  ConnectionService.cleanupTempFiles().catchError((e) {
    debugPrint('[Main] Temp cleanup error: $e');
  });

  runApp(const MainApp());
}


class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    // On web, skip ShowCaseWidget entirely to avoid layout issues
    if (kIsWeb) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Fylooo',
        theme: AppTheme.lightTheme,
        navigatorKey: navigatorKey,
        // On web, only show the WebShare (WebRTC) screen
        initialRoute: '/webshare',
        onGenerateRoute: (settings) {
          // On web, redirect mobile-only routes to webshare
          if (kIsWeb) {
            final allowedWebRoutes = ['/webshare', '/privacy', '/termsofuse'];
            if (!allowedWebRoutes.contains(settings.name)) {
              return MaterialPageRoute(
                builder: (context) => const WebRoomEntryScreen(),
                settings: const RouteSettings(name: '/webshare'),
              );
            }
          }

          // Use default routes
          switch (settings.name) {
            case '/webshare':
              return MaterialPageRoute(
                builder: (context) => const WebRoomEntryScreen(),
                settings: settings,
              );
            case '/privacy':
              return MaterialPageRoute(
                builder: (context) => const PrivacyPolicyScreen(),
                settings: settings,
              );
            case '/termsofuse':
              return MaterialPageRoute(
                builder: (context) => const TermsOfUseScreen(),
                settings: settings,
              );
            default:
              return MaterialPageRoute(
                builder: (context) => const WebRoomEntryScreen(),
                settings: settings,
              );
          }
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
      );
    }

    Route<dynamic> _onGenerateRoute(RouteSettings settings) {
      // Use default routes
      switch (settings.name) {
        case '/':
          return MaterialPageRoute(
            builder: (context) => const PermissionWrapper(),
            settings: settings,
          );
        case '/setup':
          return MaterialPageRoute(
            builder: (context) => const DeviceNameSetupScreen(),
            settings: settings,
          );
        case '/home':
          return MaterialPageRoute(
            builder: (context) => const HomeWrapper(),
            settings: settings,
          );
        case '/webshare':
          return MaterialPageRoute(
            builder: (context) => const WebRoomEntryScreen(),
            settings: settings,
          );
        case '/privacy':
          return MaterialPageRoute(
            builder: (context) => const PrivacyPolicyScreen(),
            settings: settings,
          );
        case '/termsofuse':
          return MaterialPageRoute(
            builder: (context) => const TermsOfUseScreen(),
            settings: settings,
          );
        default:
          return MaterialPageRoute(
            builder: (context) => const PermissionWrapper(),
            settings: settings,
          );
      }
    }

    // On mobile/desktop, use ShowCaseWidget
    return ShowCaseWidget(
      builder: (context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Fylooo',
        theme: AppTheme.lightTheme,
        navigatorKey: navigatorKey,
        initialRoute: '/',
        onGenerateRoute: _onGenerateRoute,
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
    final platformName = kIsWeb
        ? 'web'
        : defaultTargetPlatform.name.toLowerCase();
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
    NotificationService().onNotificationTap =
        (String deviceName, String transferId) async {
          final cm = globalDiscoveryService?.connectionManager;
          if (cm == null) {
            return;
          }

          final connection = cm.getConnection(deviceName);
          if (connection == null) {
            return;
          }

          // Navigate using global navigator key
          final context = navigatorKey.currentContext;

          if (context != null) {
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
          } else {
            debugPrint('[HomeWrapper] ERROR: No navigator context available');
          }
        };
  }

  @override
  Widget build(BuildContext context) {
    if (_deviceName == null || _discoveryService == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

class _PermissionWrapperState extends State<PermissionWrapper>
    with WidgetsBindingObserver {
  bool _permissionsGranted = false;
  bool _isCheckingPermissions = true;
  bool _locationServiceDisabled = false;
  String? _deviceName;
  bool _postPermissionInitDone = false;

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
    // When app is resumed (re-opened), clear temp files to remove leftover
    // transient files from previous runs.
    if (state == AppLifecycleState.resumed) {
      // Use a small threshold to avoid removing very recent files still in use.
      ConnectionService.cleanupTempFiles(olderThanSeconds: 5).catchError((e) {
        debugPrint('[Main] Temp cleanup (on resume) failed: $e');
      });
    }
  }

  Future<void> _initialize() async {
    AppLogger.d('PermissionWrapper _initialize called', tag: 'PermWrap');

    // Initialize notification service
    await NotificationService().initialize();
    await NotificationService().requestPermissions();

    // Initialize share intent service (only on mobile platforms)
    if (!kIsWeb) {
      ShareIntentService().initialize();
    }

    // Ask required permissions at startup (system dialog), but do NOT block app entry.
    // Some users may deny Location/Nearby permissions; the app should still open.
    // Feature screens can handle missing permissions contextually.
    // Fire-and-forget so we don't block startup on the dialog.
    // ignore: unawaited_futures
    _checkPermissions();

    await _postPermissionInitialize();
  }

  Future<void> _postPermissionInitialize() async {
    if (_postPermissionInitDone) return;
    _postPermissionInitDone = true;

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

    // Check for app updates after device setup is complete
    if (_deviceName != null && mounted) {
      await UpdateService.checkForUpdates(context);
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

    // If device name is set, show home screen
    if (_deviceName != null) {
      AppLogger.i(
        'Creating HomeScreen with device name: $_deviceName',
        tag: 'PermWrap',
      );
      final platformName = kIsWeb
          ? 'web'
          : defaultTargetPlatform.name.toLowerCase();
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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }

  void _setupNotificationHandler() {
    debugPrint('[PermissionWrapper] Setting up notification handler');
    NotificationService()
        .onNotificationTap = (String deviceName, String transferId) async {
      debugPrint(
        '[PermissionWrapper] ========================================',
      );
      debugPrint('[PermissionWrapper] Notification callback triggered!');
      debugPrint(
        '[PermissionWrapper] Device: $deviceName, Transfer: $transferId',
      );
      debugPrint(
        '[PermissionWrapper] globalDiscoveryService is null: ${globalDiscoveryService == null}',
      );

      final cm = globalDiscoveryService?.connectionManager;
      debugPrint(
        '[PermissionWrapper] ConnectionManager is null: ${cm == null}',
      );

      if (cm == null) {
        debugPrint(
          '[PermissionWrapper] ERROR: ConnectionManager not available',
        );
        return;
      }

      final connection = cm.getConnection(deviceName);
      debugPrint('[PermissionWrapper] Connection found: ${connection != null}');

      if (connection == null) {
        debugPrint(
          '[PermissionWrapper] ERROR: No connection found for $deviceName',
        );
        debugPrint(
          '[PermissionWrapper] Available connections: ${cm.activeConnections.keys.toList()}',
        );
        return;
      }

      // Navigate using global navigator key
      final context = navigatorKey.currentContext;
      debugPrint(
        '[PermissionWrapper] Navigator context available: ${context != null}',
      );

      if (context != null) {
        debugPrint(
          '[PermissionWrapper] Navigating to ConnectionScreenRefactored...',
        );
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
      debugPrint(
        '[PermissionWrapper] ========================================',
      );
    };
    debugPrint('[PermissionWrapper] Notification handler setup complete');
  }
}
