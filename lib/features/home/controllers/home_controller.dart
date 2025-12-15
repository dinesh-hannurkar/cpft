import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../services/discovery_service.dart';
import '../../../services/sound_service.dart';

class HomeController extends ChangeNotifier {
  final DiscoveryService discoveryService;
  final String myDeviceName;

  Timer? _radarTimer;
  double _sweepAngle = 0;
  bool _isPaused = false;
  final Set<String> _knownDevices = {};

  // Exposed state
  double get sweepAngle => _sweepAngle;
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

    _radarTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_isPaused) {
        _sweepAngle += 0.010; // ~25% slower sweep
        if (_sweepAngle > 6.28318530718) _sweepAngle -= 6.28318530718; // 2*pi wrap
      }
      notifyListeners();
    });
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
