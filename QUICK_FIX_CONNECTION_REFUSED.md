# Quick Fix: Connection Refused Error

## 🚨 The Problem You're Seeing

```
flutter: [ConnectionService] ❌ Connection failed: SocketException: Connection refused
```

## ✅ The Solution (90% of cases)

### **RESTART BOTH APPS!**

The iPhone at `192.168.1.142` doesn't have the incoming connection listener running because it needs to be restarted with the updated code.

### Steps:

1. **On the iPhone** (192.168.1.142):
   ```
   - Force close the app (swipe up from app switcher)
   - Or stop from Xcode/IDE
   ```

2. **Rebuild and run**:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

3. **On the other device** (the one trying to connect):
   - Also restart the app

4. **Wait 5-10 seconds** for discovery to complete

5. **Check the logs** on BOTH devices for:
   ```
   [IncomingConnection] ✅ Listening for incoming connections on port 53318
   ```

6. **Try connecting again**

## 📋 Verification Checklist

Before trying to connect, verify on **BOTH devices**:

### On Each Device's Startup, You Should See:

```log
[DiscoveryService] Initializing...
[DiscoveryService] Starting P2P connection listener on port 53318
[IncomingConnection] ✅ Listening for incoming connections on port 53318
[HttpServer] Server started on port 53317
[MulticastService] Listening on 224.0.0.167:53317
[DiscoveryService] Initialization complete!
[DiscoveryService] Listening for devices...
```

### Visual Indicators in the App:

✅ **"Ready to connect"** badge should be **green**  
✅ **"Discovering"** badge should be **green**  
✅ Devices should appear in the list within 5-10 seconds

## 🔍 Why This Happens

The new code adds a **P2P connection listener** on port 53318. This listener:
- Starts when the app launches
- Accepts incoming TCP connections
- Validates handshake messages

**If the app was already running** when you updated the code, it won't have this listener active. You **must restart** to initialize it.

## 🧪 Quick Test

### Test if the listener is running:

**On macOS** (the iPhone in your case):
```bash
lsof -i :53318
```

**Expected output**:
```
COMMAND   PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
Runner   1234   user   10u  IPv4 0x123456789      0t0  TCP *:53318 (LISTEN)
```

**If you see nothing**: The app needs to be restarted!

## 📱 Platform-Specific Notes

### iOS (Your Case)
- **Must restart after code changes** - hot reload won't initialize new services
- Check for **"Local Network" permission** in Settings
- If running on **simulator**: Usually works fine
- If running on **real device**: Restart is CRITICAL

### Android
- Same issue - restart needed
- Rebuild APK if testing on physical device:
  ```bash
  flutter build apk
  adb install build/app/outputs/flutter-apk/app-release.apk
  ```

## 🎯 Success Indicators

After restarting both apps, you should see:

1. **In the logs** (on the TARGET device being connected to):
   ```
   [IncomingConnection] 📞 Incoming connection from 192.168.1.xxx
   [IncomingConnection] 🤝 Handshake received from Android-xxx
   [DiscoveryService] 📞 Incoming P2P connection from Android-xxx
   ```

2. **In the logs** (on the device initiating connection):
   ```
   [ConnectionService] 🔌 Connecting to iPhone-xxx at 192.168.1.142:53318
   [ConnectionService] ✅ Socket connected successfully
   [ConnectionService] 📤 Sent message: handshake
   [ConnectionService] ✅ Connected to iPhone-xxx
   ```

3. **In the UI**:
   - Connection screen opens
   - Status shows "Connected"
   - Green success toast appears
   - Can send messages immediately

## ⚠️ Still Not Working?

If restarting didn't work, check:

1. **Firewall blocking port 53318**
   - macOS: System Preferences → Security & Privacy → Firewall
   - Allow incoming connections for the app

2. **Different WiFi networks**
   - Both devices MUST be on the same network
   - Check Settings → WiFi

3. **Port already in use**
   ```bash
   lsof -i :53318
   # Should only show your Flutter app
   ```

4. **Check detailed troubleshooting**:
   - See `TROUBLESHOOTING_CONNECTION_REFUSED.md`

## 🚀 Quick Command Sequence

For fastest results, run this on both devices:

```bash
# Stop all running instances
# Close apps on all devices

# Clean rebuild
flutter clean
rm -rf build/
flutter pub get

# Run
flutter run

# Wait for logs:
# [IncomingConnection] ✅ Listening...

# Now try connecting!
```

## 📞 What Port 53318 Is For

- **Port 53317**: HTTP server + UDP discovery (already working)
- **Port 53318**: P2P TCP connections (NEW - needs restart)

The "Connection refused" error means port 53318 isn't listening on the target device.

## ✨ TL;DR

**Your exact situation**:
- You're trying to connect FROM some device TO iPhone (192.168.1.142)
- The iPhone shows error errno=61 (Connection refused)
- This means: **The iPhone's app needs to be restarted**

**Fix**: Restart the iPhone app, wait for "✅ Listening on port 53318" log, try again.

That's it! 🎉
