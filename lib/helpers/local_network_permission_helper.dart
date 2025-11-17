import 'dart:io';
import 'package:flutter/foundation.dart';

/// Helper to check and request iOS Local Network permission
class LocalNetworkPermissionHelper {
  
  /// Check if Local Network permission is likely granted
  /// Note: iOS doesn't provide a direct API to check this permission
  static Future<bool> checkPermission() async {
    if (!Platform.isIOS) {
      return true; // Only needed on iOS
    }
    
    debugPrint('[LocalNetworkPermission] Checking Local Network permission...');
    debugPrint('[LocalNetworkPermission] Note: iOS doesn\'t provide direct permission check');
    debugPrint('[LocalNetworkPermission] Permission is checked when network access is attempted');
    
    return true; // We can't actually check, iOS will prompt when needed
  }
  
  /// Request Local Network permission
  /// This will trigger the iOS permission dialog if not already granted
  static Future<bool> requestPermission() async {
    if (!Platform.isIOS) {
      return true; // Only needed on iOS
    }
    
    debugPrint('[LocalNetworkPermission] ========================================');
    debugPrint('[LocalNetworkPermission] iOS Local Network Permission Required');
    debugPrint('[LocalNetworkPermission] ========================================');
    debugPrint('[LocalNetworkPermission] 📱 IMPORTANT INSTRUCTIONS:');
    debugPrint('[LocalNetworkPermission]');
    debugPrint('[LocalNetworkPermission] If you see a permission dialog:');
    debugPrint('[LocalNetworkPermission]   → Tap "Allow" to enable device discovery');
    debugPrint('[LocalNetworkPermission]');
    debugPrint('[LocalNetworkPermission] If NO dialog appears:');
    debugPrint('[LocalNetworkPermission]   1. Open Settings app on your iPhone');
    debugPrint('[LocalNetworkPermission]   2. Go to: Privacy & Security → Local Network');
    debugPrint('[LocalNetworkPermission]   3. Find "cpft" in the list');
    debugPrint('[LocalNetworkPermission]   4. Toggle the switch to ON ✅');
    debugPrint('[LocalNetworkPermission]   5. Come back and restart this app');
    debugPrint('[LocalNetworkPermission]');
    debugPrint('[LocalNetworkPermission] Without this permission:');
    debugPrint('[LocalNetworkPermission]   ❌ Device discovery will NOT work');
    debugPrint('[LocalNetworkPermission]   ❌ Multicast will show "0 bytes sent"');
    debugPrint('[LocalNetworkPermission]   ❌ Bonjour/mDNS will fail silently');
    debugPrint('[LocalNetworkPermission] ========================================');
    
    // iOS will automatically show the permission dialog when we attempt
    // to use multicast or Bonjour for the first time
    return true;
  }
  
  /// Show instructions for manually enabling the permission
  static void showManualInstructions() {
    debugPrint('[LocalNetworkPermission] ========================================');
    debugPrint('[LocalNetworkPermission] 📱 MANUAL PERMISSION SETUP');
    debugPrint('[LocalNetworkPermission] ========================================');
    debugPrint('[LocalNetworkPermission]');
    debugPrint('[LocalNetworkPermission] To enable Local Network access:');
    debugPrint('[LocalNetworkPermission]');
    debugPrint('[LocalNetworkPermission] 1. Open Settings app on your iPhone');
    debugPrint('[LocalNetworkPermission] 2. Scroll down to "Privacy & Security"');
    debugPrint('[LocalNetworkPermission] 3. Tap "Local Network"');
    debugPrint('[LocalNetworkPermission] 4. Look for "cpft" in the app list');
    debugPrint('[LocalNetworkPermission] 5. Toggle the switch to ON (green) ✅');
    debugPrint('[LocalNetworkPermission] 6. Force quit and restart this app');
    debugPrint('[LocalNetworkPermission]');
    debugPrint('[LocalNetworkPermission] ========================================');
  }
}
