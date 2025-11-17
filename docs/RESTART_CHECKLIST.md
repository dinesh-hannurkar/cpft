# Quick Restart and Test Checklist

## ⚠️ IMPORTANT: You MUST restart both apps!

The changes we made won't work with hot reload. You need to fully restart.

## Steps to Fix

### 1. Stop All Running Apps

On **BOTH devices**:
- Force close the app completely
- Or stop from your IDE/terminal

### 2. Clean Build (Important!)

```bash
flutter clean
flutter pub get
```

### 3. Rebuild and Run

```bash
flutter run
```

### 4. Wait for Initialization

On **BOTH devices**, you should see these logs:

```
[DiscoveryService] Initializing ConnectionManager
[ConnectionManager] Initialized with device name: iPhone-xxx
[IncomingConnection] ✅ Listening for incoming connections on port 53318
```

**If you don't see these logs, the fix isn't active!**

### 5. Test Connection

1. **Device A**: Tap on Device B
2. **Wait for "Connected" status**
3. **Send a message**: Type "Test" and send

### 6. Check Device B Logs

On Device B, you should see:

```
[IncomingConnection] 📞 Incoming connection from 192.168.1.xxx
[IncomingConnection] 🤝 Handshake received from Device-A  
[DiscoveryService] 📞 Incoming P2P connection from Device-A
[ConnectionManager] 📞 Handling incoming connection from Device-A
[ConnectionManager] Creating new connection service for Device-A
[ConnectionService] 📞 Accepting incoming connection from Device-A
[ConnectionService] ✅ Accepted connection from Device-A
```

**If you don't see "[ConnectionManager]" logs, Device B hasn't been restarted properly!**

## Current Error Analysis

Your error shows:
```
flutter: [ConnectionService] ✅ Socket connected successfully
flutter: [ConnectionService] 📤 Sent message: handshake
flutter: [ConnectionService] ✅ Connected to iPhone-Dineshs-Mac-mini-0952
flutter: [ConnectionService] 📤 Sent message: ping
flutter: [ConnectionService] ❌ Socket error: SocketException: Connection reset by peer (errno = 54)
```

**This means:**
- ✅ Device A connected successfully
- ✅ Device A sent handshake
- ✅ Device A thinks it's connected
- ✅ Device A sent ping
- ❌ **Device B reset the connection**

**Why Device B would reset:**
1. **Most likely:** Device B app wasn't restarted, so it doesn't have the ConnectionManager/acceptConnection code
2. The IncomingConnectionService closed the socket after handshake (old behavior)
3. No listener was attached to handle the incoming ping message
4. Socket died → Connection reset

## What to Look For on Device B

If Device B logs show **ONLY**:
```
[IncomingConnection] 📞 Incoming connection
[IncomingConnection] 🤝 Handshake received
[DiscoveryService] 📞 Incoming P2P connection
```

**And NOTHING about ConnectionManager**, then Device B wasn't restarted!

You need to see:
```
[ConnectionManager] 📞 Handling incoming connection from Device-A
[ConnectionManager] Creating new connection service for Device-A
[ConnectionService] 📞 Accepting incoming connection from Device-A
```

## Quick Test Command

Run this to ensure clean restart:

```bash
# Kill all flutter processes
killall flutter dart

# Clean and rebuild
flutter clean
rm -rf build/
flutter pub get
flutter run
```

## After Restart - Expected Flow

### Device A (Initiator):
```
[UI] 🔌 Device selected: iPhone-xxx
[ConnectionManager] Creating new connection service for iPhone-xxx
[ConnectionService] 🔌 Connecting to iPhone-xxx at 192.168.1.179:53318
[ConnectionService] ✅ Socket connected successfully
[ConnectionService] 📤 Sent message: handshake
[ConnectionService] 📥 Received message: handshake from iPhone-xxx  <-- SHOULD SEE THIS
[ConnectionService] ✅ Connected to iPhone-xxx
```

### Device B (Receiver):
```
[IncomingConnection] 📞 Incoming connection from 192.168.1.xxx
[IncomingConnection] 🤝 Handshake received from Android-xxx
[DiscoveryService] 📞 Incoming P2P connection from Android-xxx
[ConnectionManager] 📞 Handling incoming connection from Android-xxx  <-- MUST SEE THIS
[ConnectionManager] Creating new connection service for Android-xxx
[ConnectionService] 📞 Accepting incoming connection from Android-xxx
[ConnectionService] 📤 Sent message: handshake  <-- Sends handshake back
[ConnectionService] ✅ Accepted connection from Android-xxx
```

## If Still Failing After Restart

If you restart both apps and still get "Connection reset by peer":

1. Check Device B actually shows ConnectionManager logs
2. Add this temporary debug code to see what's happening:

In `lib/services/incoming_connection_service.dart`, line ~109:

```dart
// Before notifying listeners
print('[IncomingConnection] 🎯 About to notify listeners with socket');
print('[IncomingConnection] 🎯 Socket is open: ${!socket.isClosed}');

_notifyListeners(socket, message.senderName);

print('[IncomingConnection] 🎯 Listeners notified');
```

3. Share both Device A and Device B complete logs from startup to error

## Success Indicators

✅ Both devices show ConnectionManager initialization logs
✅ Device B shows "Accepting incoming connection" logs  
✅ Device A receives handshake response from Device B
✅ Messages send without "Connection reset" error
✅ Connection stays alive for 30+ seconds
✅ Ping/pong messages exchange successfully

## TL;DR

**The error you're seeing is because Device B (iPhone-Dineshs-Mac-mini) doesn't have the new ConnectionManager code running.**

**Solution: Force close and fully restart the app on the iPhone!**

Then test again.
