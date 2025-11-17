
import 'package:flutter/material.dart';
import 'app_routes.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return _slideRoute(
          const Scaffold(
            body: Center(
              child: Text('CPFT', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
            ),
          ),
          settings,
        );
      case AppRoutes.main:
        // Note: DeviceDiscoveryScreen requires deviceName parameter
        // This route would need to be updated if routing is implemented
        return _slideRoute(
          const Scaffold(
            body: Center(child: Text('Main Screen - Device Discovery')),
          ),
          settings,
        );
      case AppRoutes.home:
        return _slideRoute(
          const Scaffold(
            body: Center(child: Text('Home Screen')),
          ),
          settings,
        );
      case AppRoutes.settings:
        return _slideRoute(
          Scaffold(
            appBar: AppBar(title: const Text('Settings')),
            body: const Center(child: Text('Settings Screen - Coming Soon')),
          ),
          settings,
        );
      case AppRoutes.connectionChat:
        // Note: ConnectionScreen requires multiple parameters
        // This route would need proper args if routing is implemented
        return _slideRoute(
          const Scaffold(
            body: Center(child: Text('Connection Chat Screen')),
          ),
          settings,
        );
      case AppRoutes.webShare:
        // Note: WebFileManagerScreen requires discoveryService parameter
        // This route would need to be updated if routing is implemented
        return _slideRoute(
          const Scaffold(
            body: Center(child: Text('Web Share Screen')),
          ),
          settings,
        );

      default:
        return _defaultRoute(settings);
    }
  }

  static PageRouteBuilder _slideRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 100),
    );
  }

  static Route _defaultRoute(RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, __, ___) => Scaffold(
        body: Center(
          child: Text('Page Not Found: ${settings.name}'),
        ),
      ),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 200),
    );
  }
}
