# Debugging "Connection Reset by Peer" Error

## Current Status

**Error on Device A:**
```
[ConnectionService] 📤 Sent message: text
[ConnectionService] ❌ Socket error: Connection reset by peer (errno = 54)
[ConnectionService] 🔌 Socket closed by remote
```

**This means:** Device B (iPhone at 192.168.1.179) is actively closing/resetting the socket.

## Critical: Need Device B Logs

To diagnose this, we MUST see what's happening on Device B (the iPhone). Please share the complete logs from the iPhone showing:

### What to Look For on Device B

#### 1. Startup - Is ConnectionManager Initialized?

**MUST SEE:**
```
[DiscoveryService] Initializing ConnectionManager
[ConnectionManager] Initialized with device name: iPhone-xxx
[IncomingConnection] ✅ Listening for incoming connections on port 53318
```

**If you DON'T see this:** The app wasn't restarted properly. Stop and restart it.

#### 2. Incoming Connection - Is It Being Received?

**MUST SEE:**
```
[IncomingConnection] 📞 Incoming connection from 192.168.1.xxx
[IncomingConnection] 🤝 Handshake received from Android-xxx
[IncomingConnection] 🔄 Canceling temporary handshake listener
[IncomingConnection] 🎯 Notifying listeners with clean socket
```

**If you DON'T see this:** The connection isn't reaching Device B at all.

#### 3. Connection Acceptance - Is It Working?

**MUST SEE:**
```
[ConnectionManager] 📞 Handling incoming connection from Android-xxx
[ConnectionManager] 🔍 Got ConnectionService for Android-xxx
[ConnectionManager] 🔄 Calling acceptConnection...
[ConnectionService] 📞 Accepting incoming connection from Android-xxx
[ConnectionService] 🎧 Setting up socket listener...
[ConnectionService] ✅ Socket listener attached successfully
[ConnectionService] 📤 Sending handshake response...
[ConnectionService] ✅ Accepted connection from Android-xxx
```

**If you see errors here:** That's where the problem is.

#### 4. Message Reception - Can It Receive?

When Device A sends "text" message, Device B should show:
```
[ConnectionService] 📥 Received message: text from Android-xxx
```

**If you DON'T see this:** The socket listener isn't working.

## Possible Scenarios

### Scenario 1: Device B Not Restarted

**Symptoms:**
- Device A connects successfully
- Sends ping
- Gets "Connection reset"

**Logs Device B Would Show:**
```
[IncomingConnection] 📞 Incoming connection
[IncomingConnection] 🤝 Handshake received
[DiscoveryService] 📞 Incoming P2P connection
```
**But NO ConnectionManager logs!**

**Solution:** Restart Device B app completely.

### Scenario 2: Stream Listener Issue Persists

**Symptoms:**
- ConnectionManager logs appear
- Error: "Stream has already been listened to"

**Logs Device B Would Show:**
```
[ConnectionManager] 📞 Handling incoming connection
[ConnectionService] ❌ Failed to accept connection: Bad state: Stream has already been listened to
```

**Solution:** The 50ms delay might not be enough. Try increasing it.

### Scenario 3: Crash on Device B

**Symptoms:**
- Connection starts
- Device B crashes or throws unhandled exception
- Socket gets closed

**Logs Device B Would Show:**
```
[ConnectionManager] 📞 Handling incoming connection
[Some error or crash]
```

**Solution:** Check for stack traces on Device B.

### Scenario 4: Double Handshake Conflict

**Symptoms:**
- Both devices send handshakes
- Causes confusion or error

**Logs Would Show:**
```
[ConnectionService] 📥 Received message: handshake
[ConnectionService] 📥 Received message: handshake (again?)
```

**Solution:** Just implemented - handshakes are now filtered out.

## Debug Steps

### Step 1: Verify Device B Initialization

On Device B (iPhone), immediately after app starts, check logs for:
```bash
[DiscoveryService] Initializing ConnectionManager
```

**If missing:** App not restarted. Force close and restart.

### Step 2: Clear Logs and Try Connection

1. Clear logs/terminal on BOTH devices
2. Device A: Tap Device B in list
3. Immediately check Device B logs
4. Share the complete output

### Step 3: Add More Debug Logging

If needed, add this to `connection_service.dart` in `_handleIncomingData`:

```dart
void _handleIncomingData(List<int> data) {
  print('[ConnectionService] 📦 Raw data received: ${data.length} bytes');
  try {
    final text = utf8.decode(data);
    print('[ConnectionService] 📝 Decoded text: ${text.substring(0, min(100, text.length))}');
    // ... rest of the method
  } catch (e, stackTrace) {
    print('[ConnectionService] ❌ Error in _handleIncomingData: $e');
    print('[ConnectionService] Stack trace: $stackTrace');
  }
}
```

### Step 4: Test Minimal Connection

Try this simple test:

1. Device A: Tap Device B
2. Wait for "Connected" status
3. DON'T send message yet
4. Wait 35 seconds (for keep-alive ping)
5. Check if connection survives

**If ping causes disconnect:** Issue is in message handling
**If connection stays:** Issue is specific to text messages

### Step 5: Check for Firewall/Network Issues

On Device B (if macOS):
```bash
# Check if port is listening
lsof -i :53318

# Should show:
# Runner  PID  USER  ... (LISTEN)

# Check firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

## Quick Test Commands

### On Device B (iPhone/Mac), run these diagnostics:

```bash
# 1. Check if app is listening on correct port
lsof -i :53318

# 2. Check for any errors in system log (macOS)
log stream --predicate 'process == "Runner"' --level debug

# 3. Monitor network connections
netstat -an | grep 53318
```

## What I Need From You

Please provide the following:

### 1. Device B Complete Logs (Critical!)

From app startup to when the error occurs, showing:
- ConnectionManager initialization
- Incoming connection handling
- Any errors or exceptions

### 2. Device A Logs (You already provided)

```
[ConnectionService] 📤 Sent message: text
[ConnectionService] ❌ Socket error: Connection reset by peer (errno = 54)
```

### 3. Confirmation Checklist

- [ ] Device B app was force-closed and restarted
- [ ] Device B shows "ConnectionManager Initialized" log
- [ ] Device B shows "Listening on port 53318" log
- [ ] Both devices on same WiFi network
- [ ] No VPN active on either device
- [ ] Firewall allows connections (if applicable)

## Temporary Workaround Test

To isolate the issue, let's try commenting out the handshake response:

In `connection_service.dart`, `acceptConnection` method:

```dart
// Send handshake response
// print('[ConnectionService] 📤 Sending handshake response...');
// await _sendHandshake();  // COMMENT THIS OUT TEMPORARILY
```

This will test if the handshake response is causing the socket reset.

## Next Steps

1. **Restart Device B app completely**
2. **Share Device B logs** from startup through connection attempt
3. **Try the minimal connection test** (connect but don't send message)
4. **Check if keep-alive ping works** (wait 35 seconds)

Once I see Device B logs, I can pinpoint exactly where it's failing.

## Expected Working Logs

For reference, here's what SHOULD happen:

**Device B (receiver):**
```
[App starts]
[DiscoveryService] Initializing ConnectionManager
[ConnectionManager] Initialized with device name: iPhone-localhost-0952
[IncomingConnection] ✅ Listening for incoming connections on port 53318

[Device A connects]
[IncomingConnection] 📞 Incoming connection from 192.168.1.xxx
[IncomingConnection] 🤝 Handshake received from Android-xxx
[IncomingConnection] 🔄 Canceling temporary handshake listener
[IncomingConnection] 🎯 Notifying listeners with clean socket
[ConnectionManager] 📞 Handling incoming connection from Android-xxx
[ConnectionManager] 🔍 Socket details - Address: 192.168.1.xxx, Port: 12345
[ConnectionManager] 🔍 Got ConnectionService for Android-xxx
[ConnectionManager] 🔄 Calling acceptConnection...
[ConnectionService] 📞 Accepting incoming connection from Android-xxx
[ConnectionService] 🔍 Socket info: 192.168.1.xxx:12345
[ConnectionService] ✅ Socket options configured
[ConnectionService] 🎧 Setting up socket listener...
[ConnectionService] ✅ Socket listener attached successfully
[ConnectionService] 📤 Sending handshake response...
[ConnectionService] 📤 Sent message: handshake
[ConnectionService] ✅ Accepted connection from Android-xxx
[ConnectionManager] ✅ Incoming connection from Android-xxx accepted

[Device A sends message]
[ConnectionService] 📦 Raw data received: XX bytes
[ConnectionService] 📥 Received message: text from Android-xxx
```

**NO "Connection reset" errors!**

## Summary

The "Connection reset by peer" error means Device B is closing the socket. Without Device B's logs, I can't tell why. Please share them so we can fix this!
