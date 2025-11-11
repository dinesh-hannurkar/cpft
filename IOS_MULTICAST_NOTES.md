# iOS Multicast Implementation Notes

## Important Discovery

The `com.apple.developer.networking.multicast` entitlement is **macOS-only** and **NOT available for iOS apps**.

### What This Means

1. **iOS multicast works WITHOUT special entitlements**
   - iOS allows UDP multicast through the standard networking APIs
   - No special entitlement is required
   - Only Info.plist permissions are needed

2. **Required Info.plist Keys** (Already Added)
   ```xml
   <key>NSLocalNetworkUsageDescription</key>
   <string>This app needs access to discover and connect to nearby devices on your local network.</string>
   <key>NSBonjourServices</key>
   <array>
       <string>_cpft._udp</string>
   </array>
   ```

3. **iOS-Specific Socket Configuration** (Already Implemented)
   ```dart
   // Bind to anyIPv4 instead of specific interface
   _socket = await RawDatagramSocket.bind(
     InternetAddress.anyIPv4, 
     port, 
     reuseAddress: true,
     reusePort: false,  // iOS doesn't support reusePort well
   );
   ```

## iOS Restrictions

### What Works
- ✅ Send/receive multicast packets in foreground
- ✅ Standard multicast groups (224.0.0.0/4)
- ✅ UDP sockets with multicast
- ✅ Local network discovery

### What Doesn't Work
- ❌ Background multicast (iOS suspends network activity)
- ❌ Multicast when app is terminated
- ❌ Multicast on cellular networks
- ❌ VPN interferes with multicast

## Testing on iOS

### Prerequisites
1. **Local Network Permission**: iOS will prompt on first run - MUST allow
2. **WiFi Connection**: Must be on WiFi (not cellular)
3. **Foreground**: App must be in foreground
4. **Same Network**: All devices on same WiFi network

### Expected Behavior
- First launch: iOS asks for "Local Network" permission
- After allowing: Multicast should work immediately
- Logs should show: `[MulticastService] Sent announcement: XXX bytes` where XXX > 0

### Troubleshooting

**If you see "0 bytes sent":**
1. Check WiFi is connected (not cellular)
2. Verify Local Network permission is granted
3. Disable VPN if active
4. Try airplane mode + WiFi only
5. Restart the app

**If permission dialog doesn't appear:**
1. Delete the app from device
2. Reinstall and run again
3. Check Settings → Privacy & Security → Local Network

## Why This Works

Apple's iOS allows multicast networking through the standard POSIX socket APIs without special entitlements. The `com.apple.developer.networking.multicast` entitlement is only needed for:
- macOS apps using the Network framework
- macOS apps that need multicast in sandboxed environment

For iOS, the combination of:
1. Info.plist permissions (NSLocalNetworkUsageDescription)
2. Bonjour service declaration (NSBonjourServices)
3. Proper socket binding (anyIPv4, reusePort: false)

...is sufficient for multicast to work!

## References
- [Apple: Supporting Local Network Privacy](https://developer.apple.com/videos/play/wwdc2020/10110/)
- [Apple: Info.plist Keys - NSLocalNetworkUsageDescription](https://developer.apple.com/documentation/bundleresources/information_property_list/nslocalnetworkusagedescription)
- [Network Framework - Multicast](https://developer.apple.com/documentation/network/implementing_multicast_using_group_communications)
