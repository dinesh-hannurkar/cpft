# iOS Multicast Discovery Fix

## Problem
On real iOS devices, multicast packets fail to send with "0 bytes sent" error:
```
[MulticastService] Warning: Failed to send announcement (0 bytes sent)
```

This happens even though:
- ✅ Socket binds successfully
- ✅ Joins multicast group
- ✅ Local Network permission is granted
- ❌ But sending multicast packets returns 0 bytes

## Root Cause

iOS has strict restrictions on multicast/UDP operations:

1. **Socket binding**: iOS requires binding to `InternetAddress.anyIPv4` instead of specific interface address
2. **Socket options**: iOS doesn't fully support `reusePort` option
3. **Network permissions**: Requires `NSLocalNetworkUsageDescription` in Info.plist
4. **Broadcast**: Needs `broadcastEnabled = true` for better compatibility

## Solution Implemented

### 1. Platform-Specific Socket Binding

```dart
// iOS and Android need to bind to anyIPv4
final bindAddress = (Platform.isAndroid || Platform.isIOS)
    ? InternetAddress.anyIPv4 
    : localAddress;
```

### 2. iOS-Specific Socket Configuration

```dart
if (Platform.isIOS) {
  _socket = await RawDatagramSocket.bind(
    bindAddress, 
    port, 
    reuseAddress: true,
    reusePort: false,  // iOS doesn't support reusePort well
  );
} else {
  _socket = await RawDatagramSocket.bind(
    bindAddress, 
    port, 
    reuseAddress: true, 
    reusePort: true,
  );
}
```

### 3. Enable Broadcast Mode

```dart
_socket!.broadcastEnabled = true;  // Better compatibility on iOS
```

### 4. Info.plist Configuration

Already configured in `ios/Runner/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app needs access to the local network to discover nearby devices</string>
```

## Testing on iOS

### Prerequisites

1. **Physical iOS device** (multicast doesn't work reliably on simulator)
2. **Same WiFi network** for all devices
3. **Grant Local Network permission** when prompted
4. **Keep app in foreground** (iOS restricts background network activity)

### Test Steps

1. **Build and run on iOS device**:
   ```bash
   flutter run -d <ios-device-id>
   ```

2. **Grant Local Network permission** when prompted

3. **Check logs** for successful initialization:
   ```
   [MulticastService] iOS detected - using iOS-specific configuration
   [MulticastService] Binding UDP socket to 0.0.0.0:53317...
   [MulticastService] Listening on 224.0.0.167:53317
   [MulticastService] Sent announcement: cpft-device (XXX bytes)  ← Should show bytes > 0
   ```

4. **Run on second device** (iOS or Android)

5. **Verify discovery**:
   ```
   [MulticastService] Received announcement from cpft-device (192.168.1.142:53317)
   ```

## iOS-Specific Limitations

### ⚠️ Known iOS Restrictions

1. **Foreground only**: iOS heavily restricts background network activity
   - Solution: Keep app in foreground during discovery
   - Our wakelock keeps screen on to maintain foreground state

2. **Permission prompt**: iOS shows permission dialog on first run
   - User MUST grant "Local Network" permission
   - Goes to Settings if denied initially

3. **Simulator limitations**: Multicast may not work properly on iOS Simulator
   - Always test on real device

4. **VPN interference**: Some VPNs block multicast
   - Disable VPN during testing
   - Look for interface `pdp_ip0` or `ipsec` (indicates VPN/cellular)

5. **WiFi requirement**: Must be on WiFi (not cellular)
   - 192.168.x.x or 10.x.x.x addresses work
   - 100.x.x.x addresses (cellular/VPN) won't work

## Troubleshooting

### "0 bytes sent" on iOS

**Check:**
1. ✅ Are you on a real iOS device? (not simulator)
2. ✅ Is Local Network permission granted?
3. ✅ Are you on WiFi? (not cellular or VPN)
4. ✅ Is the IP address 192.168.x.x or 10.x.x.x?
5. ✅ Is the app in foreground?

**Try:**
```dart
// Check if broadcast is enabled
print('Broadcast enabled: ${_socket.broadcastEnabled}');

// Check socket address
print('Socket address: ${_socket.address}');
print('Socket port: ${_socket.port}');
```

### Permission Issues

If "Local Network" permission dialog doesn't appear:

1. Delete app from device
2. Rebuild and reinstall
3. Permission dialog should appear on first launch

If permission was denied:
1. Settings → cpft → Local Network → Enable
2. Restart app

### Network Interface Issues

**Preferred interface (WiFi)**:
```
en0: 192.168.1.142  ← WiFi, good!
```

**Avoid these**:
```
pdp_ip0: 100.70.74.162  ← Cellular/VPN, won't work
ipsec1: 192.0.0.6       ← VPN, won't work
```

## Comparison with Android

| Feature | Android | iOS |
|---------|---------|-----|
| Bind address | `anyIPv4` | `anyIPv4` |
| reusePort | ✅ Yes | ❌ No |
| Background | ✅ With wake lock | ⚠️ Limited |
| Simulator | ✅ Works | ❌ Unreliable |
| Permission | Runtime | Runtime |
| VPN | ⚠️ Blocks | ⚠️ Blocks |

## Success Criteria

✅ Logs show "Sent announcement: X bytes" where X > 0
✅ Other devices receive the announcement
✅ No VPN/cellular interfaces selected (pdp_ip0, ipsec)
✅ Using WiFi interface (en0) with 192.168.x.x IP
✅ Local Network permission granted
✅ Screen stays on (wakelock working)

## Additional Notes

- LocalSend (the app we're copying) has the same limitations on iOS
- iOS prioritizes battery life over background network activity
- This is a platform limitation, not a bug in our code
- Always keep app in foreground for best discovery results
