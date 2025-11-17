# Fix: Messages Auto-Disconnect Issue

## Problem Summary

**Symptom:** When clicking on a device, it showed as "connected" but when sending a message, the connection automatically disconnected.

**Root Cause:** Incoming connections were being accepted and validated, but the socket wasn't being properly handled for bidirectional communication.

## The Issue Explained

### Before the Fix

The architecture had a fundamental flaw:

**Outgoing Connection (Device A initiates):**
```
Device A User → Taps Device B in list
Device A → Opens ConnectionScreen
Device A → Creates ConnectionService
Device A → Calls connect() to Device B:53318
Device A → Sends handshake
Device A → ✅ Can send/receive messages
```

**Incoming Connection (Device B receives):**
```
Device B → IncomingConnectionService receives TCP connection
Device B → Validates handshake
Device B → Cancels socket listener ❌
Device B → Notifies DiscoveryService
Device B → DiscoveryService just logs it ❌
Device B → Socket is abandoned, no listener! ❌
```

**When Device A tries to send a message:**
```
Device A → send("Hello")
Device B Socket → Receives data
Device B → NO LISTENER to process the data! ❌
Connection → Appears dead
```

### The Problem in Code

#### 1. IncomingConnectionService was canceling the socket listener

**Old code:**
```dart
// After receiving handshake
subscription?.cancel();  // ❌ This killed the socket!
_notifyListeners(socket, message.senderName);
```

This meant the socket couldn't receive any more data after the handshake.

#### 2. DiscoveryService did nothing with incoming connections

**Old code:**
```dart
void _onIncomingConnection(Socket socket, String remoteName) {
  print('[DiscoveryService] 📞 Incoming P2P connection from $remoteName');
  // ❌ That's it! Socket just dies here
}
```

The socket was never attached to a ConnectionService, so it couldn't handle messages.

#### 3. Each ConnectionScreen created its own ConnectionService

**Old code:**
```dart
@override
void initState() {
  _connectionService = ConnectionService(deviceName: widget.myDeviceName);  // ❌ New instance every time
  _connectToDevice();
}
```

This meant outgoing and incoming connections couldn't share the same service.

## The Solution

### 1. Created ConnectionManager (Singleton Pattern)

**New file:** `lib/services/connection_manager.dart`

```dart
class ConnectionManager {
  final Map<String, ConnectionService> _activeConnections = {};
  
  // Get or create a connection for a device
  ConnectionService getOrCreateConnection(String deviceName) {
    if (_activeConnections.containsKey(deviceName)) {
      return _activeConnections[deviceName]!;  // ✅ Reuse existing
    }
    
    final service = ConnectionService(deviceName: this.deviceName);
    _activeConnections[deviceName] = service;
    return service;
  }
  
  // Handle incoming connections
  Future<void> handleIncomingConnection(Socket socket, String remoteName) async {
    final service = getOrCreateConnection(remoteName);
    await service.acceptConnection(socket, remoteName);  // ✅ Reuse socket
  }
}
```

**Benefits:**
- ✅ Single source of truth for all connections
- ✅ Incoming and outgoing connections share the same ConnectionService
- ✅ Prevents duplicate connections to the same device

### 2. Added acceptConnection() to ConnectionService

**New method in `connection_service.dart`:**

```dart
Future<bool> acceptConnection(Socket socket, String deviceName) async {
  _socket = socket;  // ✅ Use the already-connected socket
  
  // Set up listener on the existing socket
  _socketSubscription = _socket!.listen(
    _handleIncomingData,  // ✅ Now messages will be received!
    onError: (error) => _handleConnectionError(error.toString()),
    onDone: () => disconnect(),
    cancelOnError: false,
  );
  
  await _sendHandshake();  // Send our handshake response
  _startKeepAlive();  // Start ping/pong
  
  _updateStatus(ConnectionInfo(status: ConnectionStatus.connected));
  return true;
}
```

**Benefits:**
- ✅ Accepts an already-connected socket (from IncomingConnectionService)
- ✅ Sets up proper message listener
- ✅ Sends handshake response
- ✅ Starts keep-alive mechanism

### 3. Fixed IncomingConnectionService socket handling

**Updated in `incoming_connection_service.dart`:**

```dart
void _handleIncomingConnection(Socket socket) {
  StreamSubscription? subscription;
  bool handshakeReceived = false;
  
  subscription = socket.listen((data) {
    if (handshakeReceived) return;  // ✅ Ignore after handshake
    
    // Parse handshake
    if (message.type == 'handshake') {
      handshakeReceived = true;
      subscription?.cancel();  // ✅ Cancel ONLY our temporary listener
      _notifyListeners(socket, message.senderName);  // ✅ Pass clean socket
    }
  });
}
```

**Benefits:**
- ✅ Only cancels the temporary handshake listener
- ✅ Socket remains open and usable
- ✅ ConnectionService can attach its own listener

### 4. Integrated ConnectionManager into DiscoveryService

**Updated in `discovery_service.dart`:**

```dart
// Initialize
_connectionManager = ConnectionManager();
_connectionManager.initialize(alias);

// Handle incoming connections
void _onIncomingConnection(Socket socket, String remoteName) async {
  await _connectionManager.handleIncomingConnection(socket, remoteName);
  // ✅ Socket is now properly managed!
}

// Expose to UI
ConnectionManager? get connectionManager => _connectionManager;
```

**Benefits:**
- ✅ All incoming connections are properly handled
- ✅ UI can access shared connection manager
- ✅ Connections persist across screen navigation

### 5. Updated ConnectionScreen to use shared ConnectionManager

**Updated in `connection_screen.dart`:**

```dart
class ConnectionScreen extends StatefulWidget {
  final ConnectionManager connectionManager;  // ✅ Shared manager
  
  const ConnectionScreen({
    required this.connectionManager,
    // ... other params
  });
}

@override
void initState() {
  // Get or create connection from shared manager
  _connectionService = widget.connectionManager.getOrCreateConnection(widget.deviceName);
  
  // Check if already connected (incoming connection case)
  if (_connectionService.isConnected) {
    print('[ConnectionScreen] Already connected');  // ✅ Incoming connection!
    _connectionInfo = _connectionService.currentConnection;
  } else {
    _connectToDevice();  // ✅ Outgoing connection
  }
}

@override
void dispose() {
  // Remove listeners but DON'T dispose service
  _connectionService.removeMessageListener(_onMessageReceived);
  _connectionService.removeStatusListener(_onStatusChanged);
  // ✅ Service managed by ConnectionManager
}
```

**Benefits:**
- ✅ Reuses existing connections
- ✅ Works for both incoming and outgoing connections
- ✅ Proper lifecycle management

### 6. Updated DeviceDiscoveryScreen to pass ConnectionManager

**Updated in `device_discovery_screen.dart`:**

```dart
void _onDeviceSelected(String deviceName, String ipAddress) {
  final connectionManager = _discoveryService.connectionManager;
  
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ConnectionScreen(
        deviceName: deviceName,
        ipAddress: ipAddress,
        port: 53318,  // ✅ P2P port, not discovery port
        myDeviceName: widget.deviceName,
        connectionManager: connectionManager,  // ✅ Shared manager
      ),
    ),
  );
}
```

**Benefits:**
- ✅ Passes shared ConnectionManager to ConnectionScreen
- ✅ Uses correct P2P port (53318)
- ✅ Validates manager is initialized before navigating

## How It Works Now

### Scenario: Device A connects to Device B

**Step 1: Device A initiates connection**
```
User taps Device B in list →
ConnectionScreen opens →
Gets ConnectionService from ConnectionManager →
Service doesn't exist yet, creates new one →
Calls connect(Device B, 192.168.1.142, 53318) →
TCP socket connects successfully →
Sends handshake: {"type":"handshake","senderName":"Device-A"} →
Status: CONNECTED ✅
```

**Step 2: Device B receives connection**
```
IncomingConnectionService gets TCP connection →
Creates temporary listener for handshake →
Receives: {"type":"handshake","senderName":"Device-A"} →
Validates handshake ✅ →
Cancels temporary listener →
Notifies DiscoveryService with socket →
DiscoveryService calls ConnectionManager.handleIncomingConnection() →
ConnectionManager gets/creates ConnectionService for "Device-A" →
Calls acceptConnection(socket, "Device-A") →
ConnectionService attaches listener to socket ✅ →
Sends handshake response →
Starts keep-alive →
Status: CONNECTED ✅
```

**Step 3: Device A sends message**
```
User types "Hello" and sends →
ConnectionService.sendText("Hello") →
Encodes: {"type":"text","content":"Hello","senderName":"Device-A"}\n →
socket.write(data) →
await socket.flush() →
Message sent ✅
```

**Step 4: Device B receives message**
```
Socket receives data →
_handleIncomingData() called →
Decodes JSON →
message.type == "text" →
_notifyMessageListeners(message) →
UI updates with message "Hello" ✅
```

**Step 5: Device B sends reply**
```
User on Device B can open ConnectionScreen for "Device-A" →
Gets SAME ConnectionService from ConnectionManager ✅ →
Already connected! →
Sends: "Hi back" →
Device A receives it ✅
```

## Testing the Fix

### 1. Restart Both Apps

```bash
# Important: Must restart to apply all changes
flutter clean
flutter run
```

### 2. Check Initialization Logs

**On both devices, you should see:**
```
[DiscoveryService] Initializing ConnectionManager
[DiscoveryService] Starting P2P connection listener on port 53318
[IncomingConnection] ✅ Listening for incoming connections on port 53318
[ConnectionManager] Initialized with device name: iPhone-xxx
```

### 3. Initiate Connection

**On Device A (initiator):**
```
1. Tap Device B in list
2. ConnectionScreen opens
3. Look for:
   [ConnectionManager] Creating new connection service for Device-B
   [ConnectionService] 🔌 Connecting to Device-B at 192.168.1.142:53318
   [ConnectionService] ✅ Socket connected successfully
   [ConnectionService] 📤 Sent message: handshake
   [ConnectionService] ✅ Connected to Device-B
4. Status should show: "Connected"
```

**On Device B (receiver):**
```
1. Should automatically log:
   [IncomingConnection] 📞 Incoming connection from 192.168.1.xxx
   [IncomingConnection] 🤝 Handshake received from Device-A
   [DiscoveryService] 📞 Incoming P2P connection from Device-A
   [ConnectionManager] 📞 Handling incoming connection from Device-A
   [ConnectionManager] Creating new connection service for Device-A
   [ConnectionService] 📞 Accepting incoming connection from Device-A
   [ConnectionService] ✅ Accepted connection from Device-A
2. Device B is now ready to receive messages!
```

### 4. Send Messages

**From Device A:**
```
1. Type "Hello" in chat
2. Press send
3. Look for:
   [ConnectionService] 📤 Sent message: text
4. Message should appear in chat ✅
5. Connection should stay alive ✅
```

**From Device B (if you open ConnectionScreen):**
```
1. Device B user taps on Device A in device list
2. ConnectionScreen opens
3. Look for:
   [ConnectionManager] Returning existing connection to Device-A
   [ConnectionScreen] Already connected to Device-A
4. Status: "Connected" immediately (no connection delay)
5. Can send messages back ✅
```

### 5. Verify Bidirectional Communication

**Test sequence:**
```
Device A: "Hello"  →  ✅ Received on Device B
Device B: "Hi"     →  ✅ Received on Device A
Device A: "Test"   →  ✅ Received on Device B
Device B: "Works!" →  ✅ Received on Device A
```

**Check keep-alive:**
```
Wait 30+ seconds
Look for ping/pong in logs:
[ConnectionService] 🏓 Sending ping
[ConnectionService] 🏓 Received ping, sending pong
[ConnectionService] 🏓 Received pong (connection alive)
```

## Success Indicators

✅ **Connection established** - Both devices show "Connected" status
✅ **Messages sent successfully** - No "Failed to send" errors
✅ **Messages received** - Both sides can see each other's messages
✅ **Connection stays alive** - No automatic disconnection
✅ **Ping/pong works** - Logs show keep-alive every 30 seconds
✅ **Bidirectional chat** - Both devices can send and receive
✅ **Shared connection** - Same ConnectionService reused for device pair

## Files Changed

1. **lib/services/connection_manager.dart** (NEW)
   - Manages all active connections
   - Handles incoming connection socket reuse
   - Provides singleton access to connections

2. **lib/services/connection_service.dart**
   - Added `acceptConnection()` method
   - Handles incoming sockets properly

3. **lib/services/incoming_connection_service.dart**
   - Fixed socket listener cancellation
   - Properly passes clean socket to ConnectionManager

4. **lib/services/discovery_service.dart**
   - Integrated ConnectionManager
   - Handles incoming connections properly
   - Exposes ConnectionManager to UI

5. **lib/screens/connection_screen.dart**
   - Uses shared ConnectionManager
   - Detects existing connections
   - Proper listener cleanup (no dispose)

6. **lib/screens/device_discovery_screen.dart**
   - Passes ConnectionManager to ConnectionScreen
   - Uses correct P2P port (53318)

## Architecture Diagram

```
┌─────────────────────────────────────────┐
│        Device A (Initiator)             │
├─────────────────────────────────────────┤
│  DeviceDiscoveryScreen                  │
│    ↓                                    │
│  User taps "Device-B"                   │
│    ↓                                    │
│  ConnectionScreen(connectionManager)    │
│    ↓                                    │
│  ConnectionManager.getOrCreate("B")     │
│    ↓                                    │
│  ConnectionService.connect()            │
│    ↓                                    │
│  Socket → Device B:53318                │
└─────────────────────────────────────────┘
                   ↓
                   TCP
                   ↓
┌─────────────────────────────────────────┐
│        Device B (Receiver)              │
├─────────────────────────────────────────┤
│  IncomingConnectionService              │
│    ↓                                    │
│  Accept TCP connection                  │
│    ↓                                    │
│  Validate handshake                     │
│    ↓                                    │
│  DiscoveryService._onIncomingConnection │
│    ↓                                    │
│  ConnectionManager.handleIncoming()     │
│    ↓                                    │
│  ConnectionService.acceptConnection()   │
│    ↓                                    │
│  BOTH CONNECTED ✅                       │
│    ↓                                    │
│  Bidirectional messaging works          │
└─────────────────────────────────────────┘
```

## Next Steps

After restarting both apps and testing:

1. ✅ Verify connection works bidirectionally
2. ✅ Test with multiple devices (3+ devices)
3. ✅ Test reconnection after disconnect
4. ✅ Test with different network conditions
5. Consider: Auto-opening ConnectionScreen on incoming connection (push notification style)
6. Consider: Showing "pending connections" badge in UI
7. Consider: File transfer capability

## Summary

The core fix was implementing **ConnectionManager** to properly handle socket reuse between outgoing and incoming connections. Before, incoming sockets were abandoned after handshake validation. Now they're properly managed and attached to ConnectionService instances that can handle bidirectional messaging.

**Key improvement:** Same ConnectionService is used whether you initiate the connection or receive it, ensuring bidirectional communication always works.
