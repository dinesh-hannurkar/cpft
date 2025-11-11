import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:nsd/nsd.dart';

/// Bonjour/mDNS service for iOS device discovery
/// This is required for iOS real devices as multicast UDP doesn't work reliably
class BonjourService {
  static const String serviceType = '_cpft._tcp';
  
  final String alias;
  final int port;
  final String fingerprint;
  final String deviceModel;
  
  Registration? _registration;
  Discovery? _discovery;
  final List<Function(String deviceName, String ipAddress, int port)> _discoveryListeners = [];
  bool _isRunning = false;
  
  BonjourService({
    required this.alias,
    required this.port,
    required this.fingerprint,
    required this.deviceModel,
  }) {
    print('[BonjourService] Constructor called');
    print('[BonjourService] Alias: $alias');
    print('[BonjourService] Port: $port');
  }
  
  /// Add a listener for discovered devices
  void addDiscoveryListener(Function(String deviceName, String ipAddress, int port) listener) {
    _discoveryListeners.add(listener);
    print('[BonjourService] Added discovery listener, total: ${_discoveryListeners.length}');
  }
  
  /// Remove a discovery listener
  void removeDiscoveryListener(Function(String, String, int) listener) {
    _discoveryListeners.remove(listener);
  }
  
  /// Start Bonjour service (register and discover)
  Future<void> start() async {
    if (_isRunning) {
      print('[BonjourService] Already running');
      return;
    }
    
    print('[BonjourService] ========================================');
    print('[BonjourService] 🚀 Starting Bonjour service');
    print('[BonjourService] Platform: ${Platform.operatingSystem}');
    print('[BonjourService] ========================================');
    
    try {
      // Start registration and discovery in parallel without waiting
      _register().catchError((e) {
        print('[BonjourService] ❌ Registration error: $e');
      });
      
      _startDiscovery().catchError((e) {
        print('[BonjourService] ❌ Discovery error: $e');
      });
      
      _isRunning = true;
      print('[BonjourService] ✅ Bonjour service started (async)');
    } catch (e) {
      print('[BonjourService] ❌ Error starting Bonjour: $e');
      rethrow;
    }
  }
  
  /// Register this device on the network
  Future<void> _register() async {
    try {
      print('[BonjourService] Registering service: $alias');
      print('[BonjourService] Service type: $serviceType');
      print('[BonjourService] Port: $port');
      
      // Run registration asynchronously
      register(
        Service(
          name: alias,
          type: serviceType,
          port: port,
        ),
      ).then((registration) {
        _registration = registration;
        print('[BonjourService] ✅ Service registered successfully');
      }).catchError((e) {
        print('[BonjourService] ❌ Failed to register service: $e');
      });
    } catch (e) {
      print('[BonjourService] ❌ Registration exception: $e');
    }
  }
  
  /// Start discovering other devices
  Future<void> _startDiscovery() async {
    try {
      print('[BonjourService] Starting discovery for: $serviceType');
      
      // Run discovery asynchronously
      startDiscovery(serviceType).then((discovery) {
        _discovery = discovery;
        
        _discovery!.addListener(() {
          print('[BonjourService] Discovery listener triggered');
          _handleDiscovery();
        });
        
        print('[BonjourService] ✅ Discovery started successfully');
      }).catchError((e) {
        print('[BonjourService] ❌ Failed to start discovery: $e');
      });
    } catch (e) {
      print('[BonjourService] ❌ Discovery exception: $e');
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
      
      print('[BonjourService] 📱 Discovered device: $deviceName');
      print('[BonjourService]    Hostname: $hostname');
      print('[BonjourService]    Port: $devicePort');
      print('[BonjourService]    TXT: ${service.txt}');
      
      // Try multiple resolution strategies
      _resolveServiceMultipleWays(service, deviceName, devicePort, hostname);
    }
  }
  
  /// Resolve service using multiple strategies
  Future<void> _resolveServiceMultipleWays(Service service, String deviceName, int devicePort, String? hostname) async {
    // Strategy 1: Try to get addresses directly from the service
    final directAddresses = service.addresses ?? [];
    if (directAddresses.isNotEmpty) {
      print('[BonjourService] ✅ Using direct addresses from service');
      _notifyListeners(deviceName, devicePort, directAddresses);
      return;
    }
    
    // Strategy 2: Try nsd resolve() function
    try {
      print('[BonjourService] 🔍 Attempting nsd resolve for: $deviceName');
      final resolvedService = await resolve(service).timeout(const Duration(seconds: 2));
      final resolvedAddresses = resolvedService.addresses ?? [];
      
      if (resolvedAddresses.isNotEmpty) {
        print('[BonjourService] ✅ Got addresses from nsd resolve');
        _notifyListeners(deviceName, devicePort, resolvedAddresses);
        return;
      }
    } catch (e) {
      print('[BonjourService] ⚠️  nsd resolve failed: $e');
    }
    
    // Strategy 3: Resolve hostname using DNS lookup
    if (hostname != null && hostname.isNotEmpty) {
      try {
        print('[BonjourService] 🔍 Attempting DNS lookup for hostname: $hostname');
        final addresses = await InternetAddress.lookup(hostname).timeout(const Duration(seconds: 2));
        
        if (addresses.isNotEmpty) {
          print('[BonjourService] ✅ Got ${addresses.length} address(es) from DNS lookup');
          _notifyListeners(deviceName, devicePort, addresses);
          return;
        }
      } catch (e) {
        print('[BonjourService] ⚠️  DNS lookup failed: $e');
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
          print('[BonjourService] 🔍 Trying hostname variant: $variant');
          final addresses = await InternetAddress.lookup(variant).timeout(const Duration(seconds: 1));
          
          if (addresses.isNotEmpty) {
            print('[BonjourService] ✅ Got addresses from variant: $variant');
            _notifyListeners(deviceName, devicePort, addresses);
            return;
          }
        } catch (e) {
          // Silently continue to next variant
        }
      }
    }
    
    print('[BonjourService] ❌ All resolution strategies failed for $deviceName');
    print('[BonjourService] 💡 Device will still be discoverable via multicast');
  }
  
  /// Notify listeners with resolved addresses
  void _notifyListeners(String deviceName, int devicePort, List<InternetAddress> addresses) {
    print('[BonjourService] 📡 Notifying listeners with ${addresses.length} address(es)');
    
    for (final address in addresses) {
      final addressStr = address.address;
      
      // Filter out invalid addresses
      if (addressStr.isEmpty) continue;
      if (addressStr.contains('%')) continue; // Skip link-local with zone ID
      if (addressStr.startsWith('fe80:')) continue; // Skip IPv6 link-local
      if (addressStr == '::1' || addressStr == '127.0.0.1') continue; // Skip localhost
      
      print('[BonjourService] ✅ Notifying: $deviceName @ $addressStr:$devicePort');
      
      for (var listener in _discoveryListeners) {
        try {
          listener(deviceName, addressStr, devicePort);
        } catch (e) {
          print('[BonjourService] ❌ Error notifying listener: $e');
        }
      }
    }
  }
  
  /// Manually trigger discovery processing (useful for refresh)
  void refreshDiscovery() {
    print('[BonjourService] 🔄 Manually triggering discovery...');
    _handleDiscovery();
  }
  
  /// Stop Bonjour service
  Future<void> stop() async {
    print('[BonjourService] Stopping...');
    
    try {
      _discovery?.dispose();
      await stopDiscovery(_discovery!);
      await unregister(_registration!);
    } catch (e) {
      print('[BonjourService] Error stopping: $e');
    }
    
    _isRunning = false;
    _discoveryListeners.clear();
    print('[BonjourService] ✅ Stopped');
  }
  
  void dispose() {
    stop();
  }
}
