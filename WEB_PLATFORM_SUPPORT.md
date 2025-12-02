# Web Platform Support for WebRTC File Transfer

## Changes Made

### 1. Platform Detection & Conditional Imports

**Files Modified:**
- `lib/features/webshare/services/webrtc_file_transfer_service.dart`
- `lib/features/webshare/services/local_websocket_signaling_server.dart`
- `lib/features/webshare/presentation/webshare_screen.dart`

**Created:**
- `lib/features/webshare/services/io_stub.dart` - Stub implementations for `dart:io` types on web

### 2. Key Changes

#### webrtc_file_transfer_service.dart
- Added conditional import: `import 'dart:io' if (dart.library.html) 'package:cpft/features/webshare/services/io_stub.dart';`
- Default `useLocalWebSocket` to `false` on web (`kIsWeb ? false : true`)
- Default `isLocalMode` to `false` on web
- Added web check in `setSignalingMode()` to prevent enabling local mode on web
- Added web check in `_detectLocalIp()` to return null on web platform

#### local_websocket_signaling_server.dart
- Added conditional import for `dart:io`
- Added web platform check in `start()` method - throws `UnsupportedError` on web
- Local signaling server cannot run in browser (browsers cannot host HTTP servers)

#### webshare_screen.dart
- Added `import 'package:flutter/foundation.dart' show kIsWeb;`
- Hides "Signaling Mode" toggle on web (always uses remote Socket.IO signaling)
- Hides "Host/Join" mode selector on web

### 3. Web Platform Limitations

**Not Available on Web:**
- ❌ Local WebSocket signaling server (browsers can't host servers)
- ❌ Host mode (requires running local server)
- ❌ Direct peer-to-peer discovery via subnet scanning
- ❌ NetworkInterface API for IP detection
- ❌ Local file system access (uses Downloads folder)

**Available on Web:**
- ✅ Remote signaling via Socket.IO (https://webrtc-yesc.onrender.com)
- ✅ WebRTC peer-to-peer data channels
- ✅ File sending via file picker
- ✅ File receiving via browser downloads
- ✅ Join mode only (connect to remote rooms)

### 4. How It Works on Web

**Web Workflow:**
1. User opens app in browser
2. Signaling mode automatically set to "Remote (Internet)"
3. User enters room ID to join
4. Connects via Socket.IO signaling server
5. Establishes WebRTC P2P connection
6. Files transferred directly browser-to-browser

**Native App Workflow (unchanged):**
1. Can choose Local WiFi or Remote Internet mode
2. Host mode available for local WiFi
3. Auto-generates room ID with IP octet and port
4. Direct subnet scanning and instant connection
5. Full local P2P without internet

### 5. Testing on Web

**To run on web:**
```bash
flutter run -d chrome
# or
flutter run -d web-server
# or build for deployment
flutter build web
```

**Expected Behavior:**
- Signaling mode toggle hidden
- Only "Join Room" option visible
- Must use remote signaling server
- Room ID input field shown
- Connect to rooms created by native apps (via remote mode)

### 6. Platform-Specific Features

| Feature | Native (iOS/Android/Desktop) | Web |
|---------|------------------------------|-----|
| Local WiFi Mode | ✅ Yes | ❌ No |
| Remote Internet Mode | ✅ Yes | ✅ Yes |
| Host Mode | ✅ Yes | ❌ No |
| Join Mode | ✅ Yes | ✅ Yes |
| Auto Room ID Generation | ✅ Yes | ❌ No |
| Subnet Scanning | ✅ Yes | ❌ No |
| File System Access | ✅ Full | ⚠️ Downloads only |

### 7. Cross-Platform Compatibility

**Web ↔ Native App Communication:**
- ✅ Web can join rooms created by native apps (using remote signaling)
- ✅ Native apps can join rooms with web users
- ✅ Files can be sent/received between web and native
- ❌ Web cannot use local WiFi mode
- ❌ Web cannot host local rooms

**Recommendation:**
- Use **Remote Mode** for web-to-native communication
- Use **Local WiFi Mode** for native-to-native on same network
- Web users should always use remote signaling server

### 8. Future Enhancements

Possible improvements for web platform:
1. **WebRTC Data Channel Discovery** - Use WebRTC for peer discovery instead of local server
2. **QR Code Sharing** - Generate QR code with room ID for easy joining
3. **Browser Notification API** - Notify when files are received
4. **Service Worker** - Enable offline file caching
5. **WebTorrent Integration** - Use distributed hash table for peer discovery

### 9. Security Considerations

**Web Platform:**
- Cannot bind to network ports (browser security)
- Cannot scan local network (privacy protection)
- Limited file system access (sandboxed downloads)
- Requires HTTPS for WebRTC in production
- Socket.IO signaling server must have CORS enabled

### 10. Deployment Notes

**For Web Deployment:**
1. Ensure signaling server (https://webrtc-yesc.onrender.com) is accessible
2. Configure CORS on signaling server for your domain
3. Use HTTPS for production (required for WebRTC)
4. Consider adding Web App Manifest for PWA support
5. Test file downloads in different browsers

**Environment Variables (if needed):**
```dart
// In webrtc_file_transfer_service.dart
final String signalingServerUrl = 
  kIsWeb 
    ? const String.fromEnvironment('WEB_SIGNALING_URL', defaultValue: 'https://webrtc-yesc.onrender.com')
    : 'https://webrtc-yesc.onrender.com';
```

## Summary

Your WebRTC file transfer app now supports web browsers! 

**Web users can:**
- Join rooms via remote signaling
- Send and receive files P2P
- Connect with native app users

**Web users cannot:**
- Host local rooms (no server capability)
- Use local WiFi mode (browser limitation)
- Scan local network (security restriction)

All changes maintain backward compatibility with native platforms while gracefully degrading features on web.
