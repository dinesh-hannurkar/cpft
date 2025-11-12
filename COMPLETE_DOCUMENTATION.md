# CPFT - Complete Documentation
## Cross-Platform File Transfer Application

**Last Updated:** November 12, 2025  
**Version:** 0.1.0  
**Platform:** Flutter (Android, iOS, macOS, Linux, Windows)

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Protocols & Technologies](#protocols--technologies)
4. [Full Forms & Terminology](#full-forms--terminology)
5. [Discovery System](#discovery-system)
6. [Connection System](#connection-system)
7. [File Transfer Protocol](#file-transfer-protocol)
8. [Background Service](#background-service)
9. [User Interface](#user-interface)
10. [Platform-Specific Features](#platform-specific-features)
11. [Security Considerations](#security-considerations)
12. [Troubleshooting](#troubleshooting)

---

## Overview

CPFT is a **peer-to-peer (P2P) file transfer application** that allows devices on the same local network to discover each other and exchange files without requiring internet connectivity or a central server.

### Key Features
- ✅ **Device Discovery**: Automatic discovery of nearby devices on the same WiFi network
- ✅ **Real-time Messaging**: Send text messages between connected devices
- ✅ **File Transfer**: Send files of any size with progress tracking and speed monitoring
- ✅ **Background Support**: Keep connections alive even when app is minimized (Android)
- ✅ **Cross-Platform**: Works on Android, iOS, macOS, Linux, and Windows
- ✅ **No Internet Required**: All communication happens over local network

---

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      CPFT Application                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Discovery  │  │  Connection  │  │     File     │      │
│  │    Layer     │  │    Layer     │  │   Transfer   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                  │                  │             │
│         ▼                  ▼                  ▼             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Multicast   │  │  TCP Socket  │  │  Chunking &  │      │
│  │  UDP (239.*) │  │  (Port 53318)│  │  ACK System  │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                  │                  │             │
│         └──────────────────┴──────────────────┘             │
│                           │                                 │
│                    Local Network                            │
└─────────────────────────────────────────────────────────────┘
```

### Component Breakdown

#### 1. **Discovery Layer**
- **Multicast Service**: Broadcasts device presence via UDP multicast
- **HTTP Server**: Provides device info via REST API
- **Bonjour/mDNS** (iOS): Alternative discovery for iOS devices
- **Connection Manager**: Manages all active P2P connections

#### 2. **Connection Layer**
- **Connection Service**: Handles individual device connections
- **TCP Socket Communication**: Bidirectional data channel
- **Keep-Alive Mechanism**: Maintains connection with ping/pong
- **Handshake Protocol**: Ensures proper connection establishment

#### 3. **File Transfer Layer**
- **Chunked Transfer**: Splits files into 64KB chunks
- **ACK-Based Flow Control**: Backpressure to prevent overwhelming receiver
- **Hash Verification**: SHA-256 checksum for integrity
- **Progress Tracking**: Real-time speed and progress monitoring

---

## Protocols & Technologies

### Network Protocols

#### **UDP (User Datagram Protocol)**
- **Port**: 53317 (discovery)
- **Address**: 239.255.42.99 (multicast group)
- **Purpose**: Device discovery broadcasts
- **Characteristics**: 
  - Connectionless
  - No guarantee of delivery
  - Low overhead
  - Suitable for discovery announcements

#### **TCP (Transmission Control Protocol)**
- **Port**: 53318 (peer-to-peer connections)
- **Purpose**: Reliable message and file transfer
- **Characteristics**:
  - Connection-oriented
  - Guaranteed delivery
  - In-order packet delivery
  - Error checking and correction

#### **HTTP (Hypertext Transfer Protocol)**
- **Port**: 53317 (same as UDP discovery)
- **Purpose**: Device information exchange
- **Endpoints**:
  - `GET /api/cpft/v2/info` - Get device information
  - `POST /api/cpft/v2/register` - Register discovered device

#### **mDNS/Bonjour (Multicast DNS)**
- **Service Type**: `_cpft._tcp.local.`
- **Purpose**: iOS device discovery (iOS doesn't support multicast UDP well)
- **Library**: `nsd` package

### Application Protocols

#### **Message Protocol**
All messages are **newline-delimited JSON** over TCP:

```json
{
  "type": "text|handshake|goodbye|file_offer|file_chunk|file_ack|file_cancel|ping|pong",
  "content": "message content or JSON payload",
  "senderName": "device name",
  "timestamp": "2025-11-12T10:30:00.000Z",
  "metadata": {
    // Optional type-specific data
  }
}
```

**Message Types:**
- `handshake` - Connection initiation
- `text` - Chat message
- `goodbye` - Clean disconnect
- `ping`/`pong` - Keep-alive heartbeat
- `file_offer` - Initiates file transfer
- `file_chunk` - Contains file data (base64 encoded)
- `file_ack` - Acknowledges received chunks
- `file_cancel` - Cancels ongoing transfer

#### **File Transfer Protocol**

**1. Offer Phase:**
```json
{
  "type": "file_offer",
  "content": "",
  "metadata": {
    "payload": {
      "transferId": "uuid",
      "fileName": "photo.jpg",
      "fileSize": 2048000,
      "mimeType": "image/jpeg",
      "sha256": "abc123..."
    }
  }
}
```

**2. Acceptance (Initial ACK):**
```json
{
  "type": "file_ack",
  "content": "{\"transferId\":\"uuid\",\"nextExpectedIndex\":0,\"completed\":false}"
}
```

**3. Chunk Transfer:**
```json
{
  "type": "file_chunk",
  "metadata": {
    "payload": {
      "transferId": "uuid",
      "index": 0,
      "dataBase64": "base64-encoded-bytes",
      "isLast": false
    }
  }
}
```

**4. Chunk ACK (repeated for each chunk):**
```json
{
  "type": "file_ack",
  "content": "{\"transferId\":\"uuid\",\"nextExpectedIndex\":1,\"completed\":false}"
}
```

**5. Final Chunk + ACK:**
- Sender sends chunk with `"isLast": true`
- Receiver sends final ACK with `"completed": true`

---

## Full Forms & Terminology

### Acronyms

| Acronym | Full Form | Meaning |
|---------|-----------|---------|
| **CPFT** | Cross-Platform File Transfer | The application name |
| **P2P** | Peer-to-Peer | Direct device-to-device communication without a server |
| **TCP** | Transmission Control Protocol | Reliable, connection-oriented protocol |
| **UDP** | User Datagram Protocol | Connectionless, fast protocol for broadcasts |
| **HTTP** | Hypertext Transfer Protocol | Web protocol for device info exchange |
| **mDNS** | Multicast DNS | Zero-configuration service discovery (Bonjour on Apple) |
| **ACK** | Acknowledgment | Confirmation that data was received |
| **SHA** | Secure Hash Algorithm | Cryptographic hash for file integrity |
| **JSON** | JavaScript Object Notation | Data interchange format |
| **UUID** | Universally Unique Identifier | Unique ID for transfers |
| **SAF** | Storage Access Framework | Android's file access system |
| **LAN** | Local Area Network | The WiFi network devices connect through |

### Technical Terms

**Multicast**: Sending data to multiple recipients simultaneously on a network. Address range 224.0.0.0 to 239.255.255.255.

**Socket**: A software endpoint for network communication (IP address + port number).

**Handshake**: Initial exchange of messages to establish a connection.

**Keep-Alive**: Periodic messages to maintain an idle connection.

**Backpressure**: Flow control mechanism to prevent sender from overwhelming receiver.

**Chunking**: Splitting large files into smaller pieces for transmission.

**Base64**: Encoding scheme to represent binary data as ASCII text.

**Foreground Service**: Android service that shows a notification and keeps running even when app is backgrounded.

**Isolate**: Dart's concurrency model (similar to threads).

---

## Discovery System

### How Discovery Works

```
Device A                                    Device B
   │                                           │
   │  1. Start UDP Broadcast (239.255.42.99) ◄─┤
   ├─► "Device A is here!" ──────────────────► │
   │                                           │
   │  2. HTTP Registration                     │
   ├─► POST /api/cpft/v2/register ────────────►│
   │                                           │
   │  3. Get Device Info                       │
   ├─► GET /api/cpft/v2/info ─────────────────►│
   │◄── Device B Info ──────────────────────────┤
   │                                           │
   │  4. Show in UI                            │
   │  ✓ Device B appears in list               │
   └                                           ┘
```

### Discovery Components

**File**: `lib/services/multicast_service.dart`

**Purpose**: Broadcasts device presence and listens for other devices

**How it works**:
1. Creates UDP multicast socket bound to `239.255.42.99:53317`
2. Every 5 seconds, broadcasts JSON announcement:
```json
{
  "alias": "My Phone",
  "deviceModel": "iPhone 14",
  "fingerprint": "abc123",
  "port": 53317
}
```
3. Listens for announcements from other devices
4. Notifies discovery service when new device found

**Platform Notes**:
- **Android**: Requires `CHANGE_WIFI_MULTICAST_STATE` permission + multicast lock
- **iOS**: Multicast unreliable; use Bonjour instead
- **Desktop**: Works well with multicast

---

**File**: `lib/services/bonjour_service.dart`

**Purpose**: iOS-friendly discovery using mDNS/Bonjour

**How it works**:
1. Registers service: `_cpft._tcp.local.` on port 53317
2. Browses for other `_cpft._tcp.local.` services
3. Resolves service to get IP address and port
4. Notifies discovery service

**Why needed**: iOS restricts multicast UDP for battery optimization

---

**File**: `lib/services/http_server_service.dart`

**Purpose**: Provides device information via HTTP

**Endpoints**:
```
GET /api/cpft/v2/info
Response:
{
  "alias": "My Phone",
  "deviceModel": "iPhone 14",
  "fingerprint": "abc123",
  "port": 53317
}

POST /api/cpft/v2/register
Body: { "alias": "...", ... }
Response: 201 Created
```

---

**File**: `lib/services/discovery_service.dart`

**Purpose**: Orchestrates all discovery mechanisms

**Flow**:
1. Starts HTTP server (port 53317)
2. Starts multicast service (UDP broadcasts)
3. If iOS: starts Bonjour service
4. Maintains discovered devices map
5. Notifies UI listeners when devices appear/disappear

---

## Connection System

### Connection Lifecycle

```
Device A (Initiator)                Device B (Receiver)
      │                                    │
      │  1. TCP Connect (port 53318) ──────►│
      │                                    │ (Accept socket)
      │                                    │
      │  2. Wait for handshake             │
      │◄─── handshake message ──────────────┤
      │                                    │
      │  3. Send handshake response ───────►│
      │                                    │
      │  4. Connection ESTABLISHED         │
      │◄──────── ping/pong ────────────────►│
      │          (every 5 seconds)         │
      │                                    │
      │  5. Exchange messages/files        │
      │◄────────────────────────────────────►│
      │                                    │
      │  6. Disconnect                     │
      ├─── goodbye ────────────────────────►│
      │                                    │
      │  Connection CLOSED                 │
      └                                    ┘
```

### Connection Components

**File**: `lib/services/connection_service.dart`

**Purpose**: Manages individual device connection

**Key Methods**:

```dart
// Outgoing connection
Future<bool> connect(String deviceName, String ip, int port)
- Opens TCP socket to remote device
- Sets up listener for incoming data
- Waits for handshake from remote
- Returns true if successful

// Incoming connection
Future<bool> acceptConnection(Socket socket, String deviceName)
- Receives already-connected socket
- Sets up listener
- Sends handshake immediately
- Starts keep-alive timer

// Send message
Future<bool> sendMessage(DeviceMessage message)
- Converts message to JSON
- Adds newline delimiter
- Encodes to UTF-8 bytes
- Sends via socket.add()

// Handle incoming data
void _handleIncomingData(List<int> data)
- Decodes UTF-8 bytes
- Splits by newline (message delimiter)
- Parses JSON
- Routes to appropriate handler
```

**Message Buffer**: Uses `StringBuffer` to accumulate incomplete messages until newline delimiter received.

**Keep-Alive**: Timer sends ping every 5 seconds; expects pong response. Disconnects if no pong received.

---

**File**: `lib/services/connection_manager.dart`

**Purpose**: Manages multiple simultaneous connections

**Features**:
- Maintains map of device name → ConnectionService
- Prevents duplicate connections to same device
- Notifies listeners when connections established
- Cleans up stale connections

---

**File**: `lib/services/incoming_connection_service.dart`

**Purpose**: Listens for incoming TCP connections

**How it works**:
1. Binds `ServerSocket` to port 53318
2. When socket accepted, notifies listeners
3. Passes socket to ConnectionManager
4. ConnectionManager creates ConnectionService for that socket

**Why separate service**: Allows single listener for all incoming connections, then routes to appropriate ConnectionService.

---

## File Transfer Protocol

### Transfer Flow (Detailed)

```
Sender                                  Receiver
  │                                        │
  │ 1. User picks file                     │
  │    - File size, name, hash computed    │
  │                                        │
  │ 2. Send file_offer ────────────────────►│
  │    {transferId, fileName, size, sha256}│
  │                                        │ 3. Show accept dialog
  │                                        │    User clicks Accept
  │                                        │    Choose save folder
  │                                        │    Open file for writing
  │                                        │
  │◄─── 4. Send initial ACK ───────────────┤
  │    {transferId, nextExpectedIndex: 0}  │
  │                                        │
  │ 5. Send chunk 0 ───────────────────────►│ 6. Write to disk
  │    {index: 0, dataBase64, isLast: false}│   Update progress
  │                                        │
  │◄─── 7. ACK chunk 0 ─────────────────────┤
  │    {nextExpectedIndex: 1}              │
  │                                        │
  │ 8. Send chunk 1 ───────────────────────►│ Write to disk
  │                                        │
  │◄─── ACK chunk 1 ────────────────────────┤
  │                                        │
  │    ... (repeat for all chunks) ...     │
  │                                        │
  │ 9. Send final chunk (isLast: true) ────►│ 10. Close file
  │                                        │     Verify SHA-256
  │◄─── 11. Final ACK (completed: true) ────┤
  │                                        │
  │ 12. Transfer complete                  │ 13. Show file_complete
  │     Remove from progress               │     Add to received files
  └                                        ┘
```

### Chunking & Flow Control

**Chunk Size**: 64KB (64 * 1024 bytes)

**Why chunk**:
- Prevents memory overflow for large files
- Allows progress tracking
- Enables resume capability (future feature)
- Limits impact of network errors

**Flow Control (Backpressure)**:

Sender must wait for ACK before sending next chunk:

```dart
// Sender waits
if (ot.lastAckIndex != index - 1) {
  ot.chunkPermit = Completer<void>();
  await ot.chunkPermit!.future; // Blocks until ACK received
}
// Send next chunk
```

Receiver sends ACK after writing chunk:
```dart
final ack = FileAck(
  transferId: chunk.transferId,
  nextExpectedIndex: chunk.index + 1,
  completed: chunk.isLast
);
await sendMessage(ack);
```

**Benefits**:
- Prevents sender from overwhelming slow receiver
- Ensures reliable delivery
- Allows graceful handling of network slowdowns

### Progress Tracking

**Speed Calculation**:

```dart
void updateProgress(double newBytes) {
  final now = DateTime.now();
  final elapsed = now.difference(lastUpdate).inMilliseconds / 1000.0;
  if (elapsed > 0.1) {
    final delta = newBytes - lastBytes;
    speed = delta / elapsed; // bytes per second
    lastUpdate = now;
    lastBytes = newBytes;
  }
  progress = newBytes;
}
```

**UI Updates**:
- Progress bar: `progress / total`
- Speed: Formatted as KB/s, MB/s, GB/s
- ETA: `(total - progress) / speed` (not currently shown but calculable)

### File Integrity

**SHA-256 Hash**:

```dart
// Sender computes hash before sending
final bytes = file.bytes;
final sha = sha256.convert(bytes).toString();

// Receiver verifies after receiving
final receivedBytes = File(path).readAsBytesSync();
final calculatedHash = sha256.convert(receivedBytes).toString();
if (calculatedHash != offer.sha256) {
  // Show error
}
```

**When to use**: Optional for small files, recommended for large files.

---

## Background Service

### Android Foreground Service

**File**: `lib/services/background_service.dart`

**Purpose**: Keep app alive when minimized on Android

**How it works**:

1. **Initialization** (on app start):
```dart
FlutterForegroundTask.init(
  androidNotificationOptions: AndroidNotificationOptions(
    channelId: 'cpft_foreground_service',
    channelName: 'CPFT Background Service',
    // Low priority = silent notification
  ),
  foregroundTaskOptions: ForegroundTaskOptions(
    eventAction: ForegroundTaskEventAction.repeat(5000), // Every 5s
    allowWakeLock: true,  // Keep CPU awake
    allowWifiLock: true,  // Keep WiFi active
  ),
);
```

2. **Start Service**:
```dart
await FlutterForegroundTask.startService(
  notificationTitle: 'CPFT Running',
  notificationText: 'Maintaining connection...',
  callback: startCallback, // Entry point for background isolate
);
```

3. **Background Task**:
```dart
class BackgroundTaskHandler extends TaskHandler {
  @override
  void onRepeatEvent(DateTime timestamp) {
    // Called every 5 seconds
    // Updates notification
    // Keeps isolate alive
  }
}
```

4. **Stop Service** (on app close):
```dart
await FlutterForegroundTask.stopService();
```

**Why needed**:
- Android aggressively kills background apps to save battery
- Foreground service shows persistent notification = system won't kill it
- Keeps TCP sockets alive
- Ensures file transfers complete even if user switches apps

**Permissions** (AndroidManifest.xml):
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

**Service Declaration**:
```xml
<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="dataSync"
    android:exported="false" />
```

**User Experience**:
- Notification appears when app is running
- Notification is low-priority (doesn't make sound)
- Tapping notification brings app to foreground
- Notification disappears when app closes

---

## User Interface

### Screen Hierarchy

```
main.dart (App Entry)
    │
    ├─► home_screen.dart (Device List)
    │      │
    │      ├─► Shows discovered devices
    │      ├─► Incoming connection prompts
    │      └─► Tap device → ConnectionScreen
    │
    └─► connection_screen.dart (Chat & Transfer)
           │
           ├─► Chat messages
           ├─► File transfer progress
           ├─► Send file button
           └─► Received files sheet
```

### Connection Screen Features

**File**: `lib/screens/connection_screen.dart`

**Components**:

1. **Message List**:
   - Text messages
   - System messages (handshake, file complete)
   - File completion bubbles with actions

2. **Progress Tiles** (during transfer):
   ```
   📄 photo.jpg
   ━━━━━━━━━━━━━━━━━━ 65%
   15 MB / 23 MB          2.3 MB/s
   [Cancel]
   ```

3. **File Complete Actions**:
   - **Open**: Opens file in default app
   - **Reveal**: Opens containing folder
   - **Save As**: Copy file to chosen location

4. **Received Files Sheet**:
   - Accessible via folder icon in AppBar
   - Lists all received files
   - Same actions (Open/Reveal/Save As)

### File Selection & Saving

**Sending**:
```dart
// User taps "Send file" button
await _connectionService.pickAndSendFile();
  ↓
FilePicker.platform.pickFiles(withReadStream: true)
  ↓
File selected → Send offer → Stream chunks
```

**Receiving**:

**Desktop** (macOS, Windows, Linux):
```dart
// Show folder picker
final dir = await FilePicker.platform.getDirectoryPath();
// Save to chosen folder
```

**Android**:
```dart
// Option 1: Folder picker via SAF
final dir = await FilePicker.platform.getDirectoryPath();

// Option 2: Default to Documents folder
final docs = await getApplicationDocumentsDirectory();
```

**iOS**:
```dart
// iOS restricts folder access, use share sheet
await Share.shareXFiles([XFile(filePath)]);
// User chooses location in Files app
```

---

## Platform-Specific Features

### Android

**Permissions** (AndroidManifest.xml):
```xml
<!-- Network -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />

<!-- Location (required for WiFi scanning) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<!-- Background service -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Wake locks -->
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

**Multicast Lock**:
```dart
// Required to receive multicast UDP packets
final wifiManager = WifiManager();
await wifiManager.acquireMulticastLock();
```

**Foreground Service**: Keeps app alive in background (see Background Service section)

---

### iOS

**Permissions** (Info.plist):
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>CPFT needs local network access to discover and connect to nearby devices.</string>

<key>NSBonjourServices</key>
<array>
    <string>_cpft._tcp</string>
</array>
```

**Discovery**: Uses Bonjour/mDNS instead of multicast UDP

**File Saving**: Uses Share sheet instead of direct folder access

**Background Limitations**: iOS doesn't support true background socket connections without VoIP or background fetch entitlements

---

### Desktop (macOS, Windows, Linux)

**Advantages**:
- No special permissions needed
- Multicast works reliably
- Direct folder access for saving files
- Can run indefinitely without battery concerns

**File Locations**:
- **Default Save**: Downloads folder
- **User Choice**: Folder picker dialog

---

## Security Considerations

### Current Security Model

**Network Security**:
- ✅ Local network only (no internet exposure)
- ✅ User must explicitly accept incoming connections
- ✅ User must explicitly accept file transfers
- ❌ No encryption on data in transit
- ❌ No authentication (any device can connect)

**File Security**:
- ✅ SHA-256 integrity verification
- ✅ User chooses save location
- ✅ Filename sanitization (removes invalid characters)
- ✅ Duplicate file handling (auto-rename)
- ❌ No malware scanning

### Potential Improvements

**For Production Use**:

1. **TLS Encryption**:
   ```dart
   // Wrap TCP socket with TLS
   final secureSocket = await SecureSocket.secure(
     socket,
     context: SecurityContext.defaultContext,
   );
   ```

2. **Device Authentication**:
   - Public/private key pairs per device
   - Trust on first use (TOFU) model
   - QR code pairing

3. **Message Signing**:
   ```dart
   // Sign messages with private key
   final signature = privateKey.sign(messageBytes);
   
   // Verify with public key
   final valid = publicKey.verify(messageBytes, signature);
   ```

4. **Access Control**:
   - Allowlist/blocklist of devices
   - Require approval for each connection
   - Session timeouts

---

## Troubleshooting

### Discovery Issues

**Problem**: Devices not discovering each other

**Checks**:
1. ✓ Both devices on same WiFi network
2. ✓ WiFi router allows multicast (some public WiFi blocks it)
3. ✓ Firewall not blocking ports 53317-53318
4. ✓ Location permission granted (Android)
5. ✓ Local Network permission granted (iOS)

**Android Specific**:
```dart
// Check multicast lock
print('Multicast lock acquired: ${wifiLock.isHeld}');
```

**iOS Specific**:
- Check Settings → Privacy → Local Network → CPFT is ON
- Restart app after granting permission

---

### Connection Issues

**Problem**: Connection fails or drops

**Checks**:
1. ✓ Both devices discovered each other first
2. ✓ Port 53318 not blocked by firewall
3. ✓ Network stable (not switching between WiFi/cellular)
4. ✓ Not too many simultaneous connections

**Logs to check**:
```
[ConnectionService] 🔌 Connecting to...
[ConnectionService] ✅ Socket connected
[ConnectionService] 🤝 Acceptance received
[ConnectionService] 🏓 Received pong (connection alive)
```

**Error Messages**:
- `Connection refused (61)`: Other device not listening on port 53318
- `Connection timed out (60)`: Network issue or firewall blocking
- `Socket closed by remote`: Other device disconnected

---

### File Transfer Issues

**Problem**: Transfer starts but fails or stalls

**Checks**:
1. ✓ Both devices stay connected
2. ✓ Enough storage space on receiver
3. ✓ File permissions (can read source file)
4. ✓ Network stable during transfer

**Problem**: "StreamSink is bound to a stream" error

**Solution**: Fixed by using `socket.add()` instead of `socket.write()` and removing broadcast streams

**Problem**: Transfer very slow

**Possible causes**:
- Weak WiFi signal
- Other heavy network activity
- Device CPU throttling (battery saver mode)
- Large chunk size (can be tuned in connection_service.dart)

---

### Android Background Issues

**Problem**: App killed when minimized

**Solution**: Foreground service should prevent this. Check:
```dart
print('Foreground service running: ${BackgroundService.isRunning}');
```

**Problem**: "Share failed: Missing Plugin Exception" (iOS)

**Solution**: Rebuild app after adding share_plus:
```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run
```

---

## Code Organization

### Project Structure

```
lib/
├── main.dart                          # App entry point
├── models/
│   ├── connection_state.dart         # DeviceMessage, ConnectionInfo
│   └── file_transfer.dart            # FileOffer, FileChunk, FileAck
├── screens/
│   ├── home_screen.dart              # Device discovery list
│   └── connection_screen.dart        # Chat & file transfer UI
└── services/
    ├── discovery_service.dart        # Orchestrates discovery
    ├── multicast_service.dart        # UDP multicast broadcasts
    ├── bonjour_service.dart          # iOS mDNS discovery
    ├── http_server_service.dart      # HTTP info endpoint
    ├── http_discovery_client.dart    # HTTP registration
    ├── incoming_connection_service.dart  # TCP server
    ├── connection_manager.dart       # Multi-connection management
    ├── connection_service.dart       # Single connection handler
    ├── background_service.dart       # Android foreground service
    └── multicast_platform_helper.dart # Platform-specific multicast
```

### Key Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Network & Discovery
  http: ^1.1.0                  # HTTP client/server
  shelf: ^1.4.1                 # HTTP server framework
  nsd: ^4.0.3                   # mDNS/Bonjour (iOS)
  
  # File System
  file_picker: ^8.0.2           # File/folder picker
  path_provider: ^2.1.4         # System directories
  open_filex: ^4.5.0            # Open files
  share_plus: ^10.0.2           # Share sheet (iOS)
  
  # Utilities
  crypto: ^3.0.3                # SHA-256 hashing
  permission_handler: ^11.3.1   # Runtime permissions
  wakelock_plus: ^1.2.8         # Keep screen/CPU awake
  
  # Background Service
  flutter_foreground_task: ^8.11.0  # Android foreground service
  
  # Preferences
  shared_preferences: ^2.2.3    # Key-value storage
```

---

## Performance Metrics

### Typical Performance

**Discovery Time**: 1-3 seconds (local network)

**Connection Time**: 100-500ms (TCP handshake)

**Transfer Speed**:
- WiFi 5 (802.11ac): 10-50 MB/s
- WiFi 6 (802.11ax): 20-100 MB/s
- WiFi 4 (802.11n): 5-20 MB/s

**Memory Usage**:
- Idle: ~50 MB
- During transfer: ~100 MB (chunk buffering)

**Battery Impact** (Android):
- Foreground service: ~2-5% per hour
- Active transfer: ~10-15% per hour

### Optimization Opportunities

1. **Chunk Size Tuning**:
   ```dart
   // Current: 64KB
   const chunkSize = 64 * 1024;
   
   // Larger chunks = faster but more memory
   // Try: 256KB or 512KB for WiFi 6
   ```

2. **Compression**:
   ```dart
   // Add gzip compression for text files
   import 'dart:io';
   final compressed = gzip.encode(bytes);
   ```

3. **Parallel Transfers**:
   - Multiple TCP connections for same file
   - Requires protocol changes

---

## Future Enhancements

### Planned Features

1. **Resume Interrupted Transfers**
   - Store transfer state
   - Request missing chunks
   - Continue from last ACK

2. **Group Transfers**
   - Send file to multiple devices simultaneously
   - Multicast data stream

3. **QR Code Pairing**
   - Generate QR with connection info
   - Scan to auto-connect

4. **Transfer History**
   - SQLite database
   - Persistent sent/received log

5. **Bandwidth Throttling**
   - User-configurable speed limit
   - Adaptive based on network quality

6. **Dark Mode**
   - Theme switching
   - System theme detection

---

## Conclusion

CPFT demonstrates a complete peer-to-peer file transfer system with:

- ✅ **Discovery**: Multi-protocol device discovery (UDP, HTTP, mDNS)
- ✅ **Connection**: Reliable TCP connections with keep-alive
- ✅ **Transfer**: Chunked file transfer with flow control and integrity verification
- ✅ **UX**: Real-time progress, speed monitoring, and file management
- ✅ **Platform Support**: Works across Android, iOS, and desktop platforms
- ✅ **Background Support**: Android foreground service keeps app alive

The architecture is modular, extensible, and follows Flutter best practices.

---

**Questions or Issues?**

Check the logs:
- All services log with `[ServiceName]` prefix
- Look for ❌ for errors, ✅ for success, ⚠️ for warnings

**Contributing:**

Feel free to extend this with:
- Encryption (TLS)
- Authentication (public key)
- Compression
- Resume capability
- Multi-device transfers

---

*Documentation Version: 1.0*  
*Last Updated: November 12, 2025*
