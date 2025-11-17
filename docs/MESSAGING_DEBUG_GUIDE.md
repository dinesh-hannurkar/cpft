# Messaging Debug Guide

## Recent Fix: Socket Listener Cancellation

### What Was Fixed

The IncomingConnectionService was canceling its socket listener after validating the handshake, which prevented the socket from being used for further communication.

**Changes Made:**

1. **incoming_connection_service.dart**: Now properly cancels the temporary handshake listener after validation, leaving the socket available for reuse

2. **connection_service.dart**: Added `acceptConnection()` method for incoming connections

### How Messaging Should Work

#### Outgoing Connection (Device A initiates):

```
1. User taps device in list
2. ConnectionScreen opens
3. ConnectionService.connect() called
   - Creates TCP socket to Device B:53318
   - Sends handshake message
   - Starts listening for responses
4. Device A Status: CONNECTED
5. User can send messages
```

#### Incoming Connection (Device B receives):

```
1. IncomingConnectionService receives TCP connection
2. Waits for handshake message
3. Validates handshake
4. Cancels temporary listener
5. Notifies DiscoveryService
6. Currently: Just logs (NO UI!)
```

### The Current Problem

**Device B (receiving side) has NO active ConnectionService or UI to handle the incoming socket!**

The socket is accepted and validated, but then it's just sitting there unused. When Device A tries to send a message:

```
Device A → Sends message through socket
Device B → Socket receives data but NO LISTENER!
Result: Message lost, connection appears dead
```

### Solution Options

#### Option 1: Auto-Accept with Notification (Recommended for testing)

```dart
// In discovery_service.dart - _onIncomingConnection()
void _onIncomingConnection(Socket socket, String remoteName) {
  // Create a ConnectionService for this incoming connection
  final connectionService = ConnectionService(deviceName: alias);
  connectionService.acceptConnection(socket, remoteName);
  
  // Store it or notify UI
  _notifyIncomingConnection(connectionService, remoteName);
}
```

#### Option 2: Pending Connections with Accept/Reject UI

```dart
// Show notification/dialog
"$remoteName wants to connect"
[Accept] [Reject]

// If accepted, open ConnectionScreen with accepted socket
```

#### Option 3: Simpler - Make connections truly bidirectional

Currently only one side has a ConnectionScreen. We could store a map of active connections in a service and allow both devices to open a ConnectionScreen for the same connection.

### Quick Test Steps

1. **Restart both apps** (to apply IncomingConnectionService fix)

2. **On Device A** (initiator):
   - Check logs for:
   ```
   [ConnectionService] 🔌 Connecting to...
   [ConnectionService] ✅ Socket connected
   [ConnectionService] 📤 Sent message: handshake
   [ConnectionService] ✅ Connected to...
   ```

3. **On Device B** (receiver):
   - Check logs for:
   ```
   [IncomingConnection] 📞 Incoming connection from...
   [IncomingConnection] 🤝 Handshake received from...
   [DiscoveryService] 📞 Incoming P2P connection from...
   ```

4. **Try sending a message from Device A**:
   - Check Device A logs:
   ```
   [ConnectionService] 📤 Sent message: text
   ```
   - Check Device B logs:
   ```
   ??? Should see incoming data but won't because no listener!
   ```

### Expected Behavior After Full Fix

**Device A sends "Hello":**
```
[ConnectionService A] 📤 Sent message: text (content: Hello)
[ConnectionService B] 📥 Received message: text from Device-A
[ConnectionScreen B] New message: Hello
```

**Device B sends "Hi back":**
```
[ConnectionService B] 📤 Sent message: text (content: Hi back)
[ConnectionService A] 📥 Received message: text from Device-B
[ConnectionScreen A] New message: Hi back
```

### Immediate Action Needed

The `_onIncomingConnection()` method in `discovery_service.dart` needs to actually USE the socket, not just log it:

```dart
void _onIncomingConnection(Socket socket, String remoteName) {
  print('[DiscoveryService] 📞 Incoming P2P connection from $remoteName');
  
  // TODO: Actually handle this connection!
  // Options:
  // 1. Store in a "pending connections" list
  // 2. Auto-accept and create ConnectionService
  // 3. Show notification to user
  
  // For now, this socket just dies because nothing is listening to it!
}
```

### Test Command

After implementing the fix, test with:

```bash
# Terminal 1 - Device A logs
flutter run --verbose

# Terminal 2 - Device B logs  
flutter run --verbose

# Then:
# 1. Device A: Click on Device B
# 2. Wait for "Connected" status
# 3. Device A: Send message "Test 1"
# 4. Check BOTH device logs
# 5. Device B should receive but currently won't show anywhere
```

### Root Cause Summary

The architecture is **one-sided**:
- ✅ Outgoing connections work (ConnectionScreen + ConnectionService)
- ❌ Incoming connections are accepted but not used (no UI, no listener)

We need to implement incoming connection handling in DiscoveryService or create a global ConnectionManager.
