import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for playing sound effects throughout the app
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  SoLoud? _soloud;
  bool _soundsEnabled = true;
  final Map<String, AudioSource> _loadedSounds = {};

  /// Initialize sound service and load preferences
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _soundsEnabled = prefs.getBool('sounds_enabled') ?? true;
    
    try {
      // Initialize SoLoud
      _soloud = SoLoud.instance;
      await _soloud!.init();
      
      // Set global volume
      _soloud!.setGlobalVolume(0.6);
      
      // Preload all sounds for better performance
      await _preloadSounds();
    } catch (e) {
      print('[SoundService] Initialization error: $e');
    }
  }

  /// Preload all sound assets
  Future<void> _preloadSounds() async {
    final soundFiles = [
      'device_discovered.mp3',
      'connection_request.mp3',
      'connection_success.mp3',
      'connection_failed.mp3',
      'transfer_start.mp3',
      'transfer_complete.mp3',
      'transfer_failed.mp3',
      'disconnect.mp3',
      'notification.mp3',
      'message_sent.mp3',
      'message_received.mp3',
    ];

    for (final soundFile in soundFiles) {
      try {
        final source = await _soloud!.loadAsset('assets/sounds/$soundFile');
        _loadedSounds[soundFile] = source;
      } catch (e) {
        // Sound file might not exist yet, skip silently
        print('[SoundService] Could not load $soundFile: $e');
      }
    }
  }

  /// Enable or disable sounds
  Future<void> setSoundsEnabled(bool enabled) async {
    _soundsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sounds_enabled', enabled);
  }

  /// Check if sounds are enabled
  bool get soundsEnabled => _soundsEnabled;

  /// Play a sound effect
  Future<void> _playSound(String soundName) async {
    if (!_soundsEnabled || _soloud == null) return;
    
    try {
      final source = _loadedSounds[soundName];
      if (source != null) {
        await _soloud!.play(source);
      }
    } catch (e) {
      // Silently fail if sound can't be played
      print('[SoundService] Error playing sound $soundName: $e');
    }
  }

  // Sound effects for different events

  /// Play when a device appears on radar
  Future<void> playDeviceDiscovered() async {
    await _playSound('device_discovered.mp3');
  }

  /// Play when connection request is received
  Future<void> playConnectionRequest() async {
    await _playSound('connection_request.mp3');
  }

  /// Play when connection is successfully established
  Future<void> playConnectionSuccess() async {
    await _playSound('connection_success.mp3');
  }

  /// Play when connection fails or is rejected
  Future<void> playConnectionFailed() async {
    await _playSound('connection_failed.mp3');
  }

  /// Play when a file transfer starts
  Future<void> playTransferStart() async {
    await _playSound('transfer_start.mp3');
  }

  /// Play when a file transfer completes successfully
  Future<void> playTransferComplete() async {
    await _playSound('transfer_complete.mp3');
  }

  /// Play when a file transfer fails
  Future<void> playTransferFailed() async {
    await _playSound('transfer_failed.mp3');
  }

  /// Play when disconnecting from a device
  Future<void> playDisconnect() async {
    await _playSound('disconnect.mp3');
  }

  /// Play a generic notification sound
  Future<void> playNotification() async {
    await _playSound('notification.mp3');
  }

  /// Play when sending a message
  Future<void> playMessageSent() async {
    await _playSound('message_sent.mp3');
  }

  /// Play when receiving a message
  Future<void> playMessageReceived() async {
    await _playSound('message_received.mp3');
  }

  /// Dispose of resources
  Future<void> dispose() async {
    try {
      // Dispose all loaded sounds
      for (final source in _loadedSounds.values) {
        await _soloud?.disposeSource(source);
      }
      _loadedSounds.clear();
      
      // Deinitialize SoLoud
      _soloud?.deinit();
    } catch (e) {
      print('[SoundService] Dispose error: $e');
    }
  }
}
