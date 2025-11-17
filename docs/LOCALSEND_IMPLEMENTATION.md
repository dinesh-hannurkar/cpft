# LocalSend-Style Device Discovery Implementation

## 🎉 What Changed

Your app now uses **LocalSend's proven discovery architecture** instead of mDNS. This is more reliable, works better on mobile platforms, and matches how production apps like LocalSend handle device discovery.

## 🏗️ Architecture Overview

### Previous Implementation (mDNS-based) ❌
- Used `multicast_dns` Dart package
- Could only **listen** for mDNS announcements
- Could NOT advertise/broadcast as mDNS responder
- Failed on iOS/Android due to SO_REUSEPORT limitations
- No fallback mechanism

### New Implementation (LocalSend-based) ✅
Based on LocalSend's actual codebase analysis:

1. **UDP Multicast Discovery**
   - Uses `RawDatagramSocket` for raw UDP multicast
   - Multicast group: `224.0.0.167:53317`
   - Sends periodic announcements (every 5 seconds)
   - Listens for announcements from other devices

2. **HTTP Server** (Critical Component)
   - Each device runs a small HTTP server on port `53317`
   - Endpoints:
     - `GET /info` - Returns device information
     - `POST /register` - Receives registration from other devices
   - Built with `shelf` package (lightweight HTTP server)

3. **HTTP Client**
   - When multicast announcement is received, device responds via HTTP POST to `/register`
   - Registration includes device name, fingerprint, port, model
   - HTTP provides reliability when UDP is unreliable

## 📁 New Files Created

### Models
- `lib/models/multicast_dto.dart` - Data transfer objects for UDP/HTTP communication

### Services
- `lib/services/multicast_service.dart` - UDP multicast announcement/listening
- `lib/services/http_server_service.dart` - HTTP server for registration
- `lib/services/http_discovery_client.dart` - HTTP client for registration requests
- `lib/services/discovery_service.dart` - Unified service combining all components

### Updated Files
- `lib/screens/device_discovery_screen.dart` - Uses new `DiscoveryService`
- `pubspec.yaml` - Added dependencies: `shelf`, `http`, `crypto`

## 🔄 How It Works

### Discovery Flow

```
Device A                          Device B
   |                                 |
   |--[UDP Multicast Announcement]-->|
   |     (224.0.0.167:53317)         |
   |                                 |
   |<---[HTTP POST /register]--------|
   |     (includes device info)      |
   |                                 |
   |---[HTTP 200 Response]---------->|
   |     (includes Device A info)    |
   |                                 |
   Both devices now know each other!
```

### Sequence

1. **App Starts**
   - HTTP server starts on port 53317
   - UDP socket binds and joins multicast group
   - Sends initial announcement

2. **Periodic Announcements**
   - Every 5 seconds, device sends UDP multicast packet
   - Contains: alias, fingerprint, port, device model

3. **Another Device Receives Announcement**
   - Parses UDP packet
   - Sends HTTP POST to `/register` endpoint
   - Includes its own device information

4. **HTTP Server Handles Registration**
   - Receives POST `/register`
   - Validates not self-discovery (checks fingerprint)
   - Adds device to discovered list
   - Responds with own device info

5. **UI Updates**
   - Discovery listeners are notified
   - Device list updates in UI
   - Both devices see each other

## 🧪 Testing

### Prerequisites
1. **Two devices** (real devices, not emulator)
2. **Same WiFi network** (192.168.x.x or 10.x.x.x range)
3. **No VPN** active on either device
4. **Mobile data disabled** (use WiFi only)

### Test Steps

1. **Check Network**
   ```
   iPhone Settings → WiFi → (i) icon
   Verify IP: 192.168.x.x (NOT 100.x.x.x)
   ```

2. **Run on Device 1** (e.g., iPhone)
   ```bash
   flutter run -d 00008020-00117DA02E03002E
   ```

3. **Run on Device 2** (e.g., Android/Pixel)
   ```bash
   flutter run -d adb-33061JEHN20119-Q51QBo._adb-tls-connect._tcp
   ```

4. **Expected Logs** (on both devices)
   ```
   [DiscoveryService] Initializing...
   [HttpServer] Server started on port 53317
   [MulticastService] Listening on 224.0.0.167:53317
   [MulticastService] Sent announcement: cpft-...
   [MulticastService] Received announcement from cpft-... (192.168.x.x:53317)
   [HttpClient] Registering with 192.168.x.x:53317...
   [HttpServer] Registered device: cpft-... (192.168.x.x:53317)
   [DiscoveryService] Device discovered: cpft-... (192.168.x.x:53317)
   UI updated: Device discovered - cpft-... at 192.168.x.x:53317
   ```

5. **UI Should Show**
   - Other device appears in "Available Devices" list
   - Device name and IP address displayed
   - Can tap refresh to manually trigger announcement

## 🐛 Troubleshooting

### No devices appearing

**Check 1: Network**
- Both devices on same WiFi? ✓
- IP addresses in same subnet (192.168.x.x)? ✓
- VPN disabled? ✓

**Check 2: Firewall/Permissions**
- Android: Location permission granted? ✓
- iOS: Local Network permission granted? ✓
- Firewall blocking port 53317? ✓

**Check 3: Logs**
Look for these error patterns:
```
❌ "Error binding socket" → Port already in use or permission issue
❌ "Network is unreachable" → WiFi not properly connected
❌ "Self-discovered" → Normal, device found itself (ignored)
✓ "Received announcement" → Multicast working
✓ "Registered device" → HTTP registration working
```

**Quick Fixes:**
1. Press refresh button on both devices
2. Restart app on both devices
3. Reconnect to WiFi
4. Check device firewall settings

### Devices appear briefly then disappear
- This is normal if devices are removed/shut down
- Refresh button will re-announce

### HTTP errors (403, 412, 500)
- 412 = Self-discovery (normal, ignored)
- 403/500 = Check server logs for specific error

## 🎯 Key Differences from LocalSend

LocalSend has additional features we haven't implemented:

1. **HTTP Subnet Scan** - Scans 192.168.1.1-254 when multicast fails
2. **WebRTC Signaling** - For NAT traversal and internet-based discovery
3. **File Transfer** - Actual file sending/receiving over HTTP
4. **TLS/HTTPS** - Encrypted connections
5. **Favorites** - Saved devices

Our implementation focuses on **core discovery** which is the foundation for everything else.

## 📊 Port Usage

- **53317** - Default port for both UDP multicast and HTTP server
- Configurable via `DiscoveryService(port: xxx)`
- Must be same on all devices to discover each other

## 🔒 Security

**Fingerprint Generation:**
- MD5 hash of `alias + hostname + timestamp`
- Used to prevent self-discovery
- Not cryptographically secure (just for identity)

**For Production:**
- Use TLS certificates (like LocalSend)
- Implement proper authentication
- Validate all incoming HTTP requests
- Rate limit registration attempts

## 📚 Code References

Want to see how LocalSend does something?

- **Multicast Discovery:** `common/lib/src/task/discovery/multicast_discovery.dart`
- **HTTP Server:** `app/lib/provider/network/server/server_provider.dart`
- **Registration:** `app/lib/provider/network/server/controller/receive_controller.dart`
- **HTTP Scan:** `common/lib/src/task/discovery/http_scan_discovery.dart`

## 🚀 Next Steps

To make this production-ready:

1. **Add HTTP Subnet Scan** - Fallback when multicast blocked
2. **Implement File Transfer** - Use `/send` and `/receive` endpoints
3. **Add TLS/Certificates** - Secure communication
4. **Device Favorites** - Remember frequently used devices
5. **Better UI** - Show device type, signal strength, etc.
6. **Background Service** - Keep discovery running when app backgrounded

## 📝 License & Attribution

This implementation is based on analyzing [LocalSend](https://github.com/localsend/localsend)'s open-source codebase. LocalSend is licensed under MIT License.

Our implementation simplifies and adapts their discovery architecture for learning purposes.
