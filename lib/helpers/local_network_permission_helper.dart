import 'dart:io';

/// Helper to check and request iOS Local Network permission
class LocalNetworkPermissionHelper {
  
  /// Check if Local Network permission is likely granted
  /// Note: iOS doesn't provide a direct API to check this permission
  static Future<bool> checkPermission() async {
    if (!Platform.isIOS) {
      return true; // Only needed on iOS
    }
    
    print('[LocalNetworkPermission] Checking Local Network permission...');
    print('[LocalNetworkPermission] Note: iOS doesn\'t provide direct permission check');
    print('[LocalNetworkPermission] Permission is checked when network access is attempted');
    
    return true; // We can't actually check, iOS will prompt when needed
  }
  
  /// Request Local Network permission
  /// This will trigger the iOS permission dialog if not already granted
  static Future<bool> requestPermission() async {
    if (!Platform.isIOS) {
      return true; // Only needed on iOS
    }
    
    print('[LocalNetworkPermission] ========================================');
    print('[LocalNetworkPermission] iOS Local Network Permission Required');
    print('[LocalNetworkPermission] ========================================');
    print('[LocalNetworkPermission] 📱 IMPORTANT INSTRUCTIONS:');
    print('[LocalNetworkPermission]');
    print('[LocalNetworkPermission] If you see a permission dialog:');
    print('[LocalNetworkPermission]   → Tap "Allow" to enable device discovery');
    print('[LocalNetworkPermission]');
    print('[LocalNetworkPermission] If NO dialog appears:');
    print('[LocalNetworkPermission]   1. Open Settings app on your iPhone');
    print('[LocalNetworkPermission]   2. Go to: Privacy & Security → Local Network');
    print('[LocalNetworkPermission]   3. Find "cpft" in the list');
    print('[LocalNetworkPermission]   4. Toggle the switch to ON ✅');
    print('[LocalNetworkPermission]   5. Come back and restart this app');
    print('[LocalNetworkPermission]');
    print('[LocalNetworkPermission] Without this permission:');
    print('[LocalNetworkPermission]   ❌ Device discovery will NOT work');
    print('[LocalNetworkPermission]   ❌ Multicast will show "0 bytes sent"');
    print('[LocalNetworkPermission]   ❌ Bonjour/mDNS will fail silently');
    print('[LocalNetworkPermission] ========================================');
    
    // iOS will automatically show the permission dialog when we attempt
    // to use multicast or Bonjour for the first time
    return true;
  }
  
  /// Show instructions for manually enabling the permission
  static void showManualInstructions() {
    print('[LocalNetworkPermission] ========================================');
    print('[LocalNetworkPermission] 📱 MANUAL PERMISSION SETUP');
    print('[LocalNetworkPermission] ========================================');
    print('[LocalNetworkPermission]');
    print('[LocalNetworkPermission] To enable Local Network access:');
    print('[LocalNetworkPermission]');
    print('[LocalNetworkPermission] 1. Open Settings app on your iPhone');
    print('[LocalNetworkPermission] 2. Scroll down to "Privacy & Security"');
    print('[LocalNetworkPermission] 3. Tap "Local Network"');
    print('[LocalNetworkPermission] 4. Look for "cpft" in the app list');
    print('[LocalNetworkPermission] 5. Toggle the switch to ON (green) ✅');
    print('[LocalNetworkPermission] 6. Force quit and restart this app');
    print('[LocalNetworkPermission]');
    print('[LocalNetworkPermission] ========================================');
  }
}
