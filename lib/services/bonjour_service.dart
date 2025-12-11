import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:nsd/nsd.dart';

class BonjourService {
  static const String serviceType = '_cpft._tcp';
  final String alias;
  final int port;
  final String fingerprint;
  final String deviceModel;
  Registration? _registration;
  Discovery? _discovery;
  final List<Function(String deviceName, String ipAddress, int port)>
  _discoveryListeners = [];
  bool _isRunning = false;

  BonjourService({
    required this.alias,
    required this.port,
    required this.fingerprint,
    required this.deviceModel,
  }) {
    debugPrint('[BonjourService] Constructor called');
    debugPrint('[BonjourService] Alias: $alias');
    debugPrint('[BonjourService] Port: $port');
  }

  /// Add a listener for discovered devices
  void addDiscoveryListener(
    Function(String deviceName, String ipAddress, int port) listener,
  ) {
    _discoveryListeners.add(listener);
    debugPrint(
      '[BonjourService] Added discovery listener, total: ${_discoveryListeners.length}',
    );
  }

  /// Remove a discovery listener
  void removeDiscoveryListener(Function(String, String, int) listener) {
    _discoveryListeners.remove(listener);
  }

  /// Start Bonjour service (register and discover)
  Future<void> start() async {
    if (_isRunning) {
      debugPrint('[BonjourService] Already running');
      return;
    }

    try {
      _register().catchError((e) {
        debugPrint('[BonjourService] ❌ Registration error: $e');
      });

      _startDiscovery().catchError((e) {
        debugPrint('[BonjourService] ❌ Discovery error: $e');
      });

      _isRunning = true;
      debugPrint('[BonjourService] ✅ Bonjour service started (async)');
    } catch (e) {
      debugPrint('[BonjourService] ❌ Error starting Bonjour: $e');
      rethrow;
    }
  }

  /// Register this device on the network
  Future<void> _register() async {
    try {
      // Run registration asynchronously
      register(Service(name: alias, type: serviceType, port: port))
          .then((registration) {
            _registration = registration;
            debugPrint('[BonjourService] ✅ Service registered successfully');
          })
          .catchError((e) {
            debugPrint('[BonjourService] ❌ Failed to register service: $e');
          });
    } catch (e) {
      debugPrint('[BonjourService] ❌ Registration exception: $e');
    }
  }

  /// Start discovering other devices
  Future<void> _startDiscovery() async {
    try {
      // Run discovery asynchronously
      startDiscovery(serviceType)
          .then((discovery) {
            _discovery = discovery;
            _discovery!.addListener(() {
              debugPrint('[BonjourService] Discovery listener triggered');
              _handleDiscovery();
            });
          })
          .catchError((e) {
            debugPrint('[BonjourService] ❌ Failed to start discovery: $e');
          });
    } catch (e) {
      debugPrint('[BonjourService] ❌ Discovery exception: $e');
    }
  }

  /// Handle discovered services
  void _handleDiscovery() {
    final services = _discovery?.services ?? [];

    for (final service in services) {
      // Ignore self-discovery
      if (service.name == alias || service.txt?['fingerprint'] == fingerprint) {
        continue;
      }

      final deviceName = service.name ?? 'Unknown';
      final devicePort = service.port ?? port;
      final hostname = service.host;

      // Try multiple resolution strategies
      _resolveServiceMultipleWays(service, deviceName, devicePort, hostname);
    }
  }

  /// Resolve service using multiple strategies
  Future<void> _resolveServiceMultipleWays(
    Service service,
    String deviceName,
    int devicePort,
    String? hostname,
  ) async {
    // Strategy 1: Try to get addresses directly from the service
    final directAddresses = service.addresses ?? [];
    if (directAddresses.isNotEmpty) {
      debugPrint('[BonjourService] ✅ Using direct addresses from service');
      _notifyListeners(deviceName, devicePort, directAddresses);
      return;
    }

    // Strategy 2: Try nsd resolve() function
    try {
      debugPrint('[BonjourService] 🔍 Attempting nsd resolve for: $deviceName');
      final resolvedService = await resolve(
        service,
      ).timeout(const Duration(seconds: 2));
      final resolvedAddresses = resolvedService.addresses ?? [];

      if (resolvedAddresses.isNotEmpty) {
        debugPrint('[BonjourService] ✅ Got addresses from nsd resolve');
        _notifyListeners(deviceName, devicePort, resolvedAddresses);
        return;
      }
    } catch (e) {
      debugPrint('[BonjourService] ⚠️  nsd resolve failed: $e');
    }

    // Strategy 3: Resolve hostname using DNS lookup
    if (hostname != null && hostname.isNotEmpty) {
      try {
        debugPrint(
          '[BonjourService] 🔍 Attempting DNS lookup for hostname: $hostname',
        );
        final addresses = await InternetAddress.lookup(
          hostname,
        ).timeout(const Duration(seconds: 2));

        if (addresses.isNotEmpty) {
          debugPrint(
            '[BonjourService] ✅ Got ${addresses.length} address(es) from DNS lookup',
          );
          _notifyListeners(deviceName, devicePort, addresses);
          return;
        }
      } catch (e) {
        debugPrint('[BonjourService] ⚠️  DNS lookup failed: $e');
      }
    }

    // Strategy 4: Try resolving .local hostname variants
    if (deviceName.isNotEmpty) {
      final hostnameVariants = [
        deviceName,
        '$deviceName.local',
        deviceName.replaceAll(' ', '-'),
        '${deviceName.replaceAll(' ', '-')}.local',
      ];

      for (final variant in hostnameVariants) {
        try {
          debugPrint('[BonjourService] 🔍 Trying hostname variant: $variant');
          final addresses = await InternetAddress.lookup(
            variant,
          ).timeout(const Duration(seconds: 1));

          if (addresses.isNotEmpty) {
            debugPrint(
              '[BonjourService] ✅ Got addresses from variant: $variant',
            );
            _notifyListeners(deviceName, devicePort, addresses);
            return;
          }
        } catch (e) {
          // Silently continue to next variant
        }
      }
    }
  }

  /// Notify listeners with resolved addresses
  void _notifyListeners(
    String deviceName,
    int devicePort,
    List<InternetAddress> addresses,
  ) {
    debugPrint(
      '[BonjourService] 📡 Notifying listeners with ${addresses.length} address(es)',
    );

    for (final address in addresses) {
      final addressStr = address.address;

      // Filter out invalid addresses
      if (addressStr.isEmpty) continue;
      if (addressStr.contains('%')) continue; // Skip link-local with zone ID
      if (addressStr.startsWith('fe80:')) continue; // Skip IPv6 link-local
      if (addressStr == '::1' || addressStr == '127.0.0.1')
        continue; // Skip localhost

      for (var listener in _discoveryListeners) {
        try {
          listener(deviceName, addressStr, devicePort);
        } catch (e) {
          debugPrint('[BonjourService] ❌ Error notifying listener: $e');
        }
      }
    }
  }

  /// Manually trigger discovery processing (useful for refresh)
  void refreshDiscovery() {
    debugPrint('[BonjourService] 🔄 Manually triggering discovery...');
    _handleDiscovery();
  }

  /// Stop Bonjour service
  Future<void> stop() async {
    debugPrint('[BonjourService] Stopping...');

    if (!_isRunning) {
      debugPrint('[BonjourService] Not running, nothing to stop');
      return;
    }

    try {
      // Stop discovery
      if (_discovery != null) {
        debugPrint('[BonjourService] Disposing discovery...');
        _discovery!.dispose();
        await stopDiscovery(_discovery!);
        _discovery = null;
      }

      // Unregister service
      if (_registration != null) {
        debugPrint('[BonjourService] Unregistering service...');
        await unregister(_registration!);
        _registration = null;
      }
    } catch (e) {
      debugPrint('[BonjourService] Error stopping: $e');
    }

    _isRunning = false;
    _discoveryListeners.clear();
    debugPrint('[BonjourService] ✅ Stopped');
  }

  Future<void> dispose() async {
    await stop();
  }
}
