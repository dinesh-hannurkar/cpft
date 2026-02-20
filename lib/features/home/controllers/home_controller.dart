import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../services/discovery_service.dart';
import '../../../services/sound_service.dart';

class HomeController extends ChangeNotifier {
  final DiscoveryService discoveryService;
  final String myDeviceName;

  Timer? _radarTimer;
  // Radar animation is now handled internally by RadarView
  bool _isPaused = false;
  final Set<String> _knownDevices = {};

  // Exposed state
  // sweepAngle is no longer needed in controller
  Map<String, DeviceInfo> get devices => discoveryService.discoveredDevices;
  bool get isPaused => _isPaused;

  HomeController({required this.discoveryService, required this.myDeviceName});

  Future<void> init() async {
    await discoveryService.initialize();

    discoveryService.addDiscoveryListener((name, ip, port) {
      // Play sound when new device is discovered
      final deviceKey = '$name:$ip';
      if (!_knownDevices.contains(deviceKey)) {
        _knownDevices.add(deviceKey);
        SoundService().playDeviceDiscovered();
      }
      // Handle both device discoveries and cleanup notifications
      notifyListeners();
    });

    // Radar animation is now handled internally by RadarView
    // No need for a timer here that rebuilds the whole screen
  }

  @override
  void dispose() {
    _radarTimer?.cancel();
    super.dispose();
  }

  /// Force cleanup of unavailable devices
  void forceCleanup() {
    // This will trigger the cleanup timer in DiscoveryService
    // For immediate effect, we could call notifyListeners after a delay
    // but the sweep timer will handle UI updates
  }

  /// Pause radar sweep
  void pauseRadar() {
    if (!_isPaused) {
      _isPaused = true;
      notifyListeners();
    }
  }

  /// Resume radar sweep
  void resumeRadar() {
    if (_isPaused) {
      _isPaused = false;
      notifyListeners();
    }
  }
}
