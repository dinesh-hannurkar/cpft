# Troubleshooting: Connection Refused Error

## Error Message
```
SocketException: Connection refused (OS Error: Connection refused, errno = 61)
```

## What This Means

The device you're trying to connect to **is not listening** on port 53318. This happens when:

1. ❌ The other device hasn't been updated with the new code
2. ❌ The other device's app hasn't been restarted
3. ❌ A firewall is blocking port 53318
4. ❌ The devices are on different networks

## Quick Fix (Most Common)

### ✅ Solution: Restart Both Apps

The P2P connection listener (port 53318) only starts when the app launches. If you updated the code, you **must restart both apps**.

**Steps**:

1. **Stop both apps completely**:
   - iOS: Swipe up and force close
   - Android: Recent apps → Swipe away
   - Or use IDE: Stop button (⬛)

2. **Rebuild and run**:
   ```bash
   # On the device you're developing on
   flutter run
   
   # Or rebuild and install
   flutter clean
   flutter pub get
   flutter run
   ```

3. **For the other device**:
   - If it's Android, rebuild APK:
     ```bash
     flutter build apk
     ```
   - Then install: `adb install build/app/outputs/flutter-apk/app-release.apk`
   
   - If it's iOS, run from Xcode or:
     ```bash
     flutter run -d <device-id>
     ```

4. **Wait for discovery** (5-10 seconds)

5. **Try connecting again**

## Detailed Troubleshooting

### 1. Verify Incoming Connection Service is Running

**Check the logs when the app starts**. You should see:

```
[DiscoveryService] Starting P2P connection listener on port 53318
[IncomingConnection] ✅ Listening for incoming connections on port 53318
```

**If you DON'T see this**:
- ❌ The app wasn't updated properly
- ❌ Need to restart the app
- Solution: Force close and restart

### 2. Check Network Connectivity

**Verify devices are on the same network**:

```bash
# On macOS/Linux
ping 192.168.1.142

# Should show responses like:
# 64 bytes from 192.168.1.142: icmp_seq=0 ttl=64 time=2.3 ms
```

**If ping fails**:
- Check WiFi settings
- Ensure both devices are on the same network
- Try forgetting and reconnecting to WiFi

### 3. Check Port Availability

**On the target device** (the one you're connecting TO), verify port 53318 is listening:

**macOS/Linux**:
```bash
lsof -i :53318

# Expected output:
# COMMAND   PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
# flutter  1234   user   10u  IPv4 0x123456789      0t0  TCP *:53318 (LISTEN)
```

**Android** (via ADB):
```bash
adb shell netstat -tuln | grep 53318

# Expected output:
# tcp6  0  0 :::53318  :::*  LISTEN
```

**If port is NOT listening**:
- The app hasn't started the incoming connection service
- Restart the app on that device
- Check for errors in the startup logs

### 4. Check Firewall Settings

**macOS**:
1. System Preferences → Security & Privacy → Firewall
2. Firewall Options → Find your app
3. Ensure it's set to "Allow incoming connections"

**Windows**:
1. Windows Defender Firewall → Allow an app
2. Find Flutter/Dart
3. Check both Private and Public networks

**Android**:
- Usually no firewall by default
- If using a third-party firewall app, allow port 53318

### 5. Port Conflict Check

Sometimes port 53318 might be in use by another app.

**Check if port is already taken**:
```bash
# macOS/Linux
lsof -i :53318

# If you see a different process, either:
# 1. Stop that process
# 2. Or change the P2P port in the code
```

**To change the port** (if needed):

Edit `lib/services/discovery_service.dart`:
```dart
// Change from 53318 to something else
static const int p2pPort = 53319;  // Or any free port
```

Then restart both apps.

## Step-by-Step Diagnosis

### Device A (Initiator)
```
1. Launch app
2. See discovery screen
3. Devices appear (via multicast/Bonjour)
4. Tap a device
5. See "Connection refused" error
```

### Device B (Target - the one being connected to)

**Check these in order**:

✅ **Is app running?**
```
Yes → Continue
No → Launch app, wait 5-10 seconds
```

✅ **Was app recently updated?**
```
Yes → RESTART the app (this is the issue!)
No → Continue
```

✅ **Check startup logs for**:
```
[IncomingConnection] ✅ Listening for incoming connections on port 53318
```

✅ **If NOT found**:
- Stop app completely
- Rebuild: `flutter clean && flutter pub get && flutter run`
- Restart app
- Check logs again

✅ **If FOUND but still failing**:
- Check firewall settings
- Try ping test
- Check port availability

## Common Scenarios

### Scenario 1: Just Updated Code
**Problem**: Connection worked before, now getting "Connection refused"

**Solution**:
```bash
# Stop ALL running instances
# Kill the apps on ALL devices
# Rebuild and run fresh
flutter clean
flutter pub get
flutter run
```

### Scenario 2: Works on Android, Not on iOS
**Problem**: Android devices connect fine, but iPhone won't accept connections

**iOS Specific Checks**:

1. **Local Network Permission**:
   - Settings → Privacy & Security → Local Network
   - Find "cpft" and enable it
   - Restart app

2. **Firewall**:
   - iOS has built-in firewall
   - Usually allows app connections automatically
   - Try forgetting WiFi and reconnecting

3. **Bonjour Services** (already configured):
   - Check `ios/Runner/Info.plist` has `NSBonjourServices`
   - Already added in your project ✅

### Scenario 3: Works Simulator-to-Device, Not Device-to-Device
**Problem**: Connecting from simulator to real device works, but device-to-device fails

**Possible Causes**:
- Real devices might have stricter firewall rules
- Network isolation on some WiFi networks

**Solutions**:
- Try a different WiFi network (home network usually works better)
- Check router settings (AP isolation should be OFF)
- Use a mobile hotspot for testing

## Testing Checklist

Before trying to connect, verify:

- [ ] Both apps are **freshly restarted**
- [ ] Both devices show **"Discovering"** status
- [ ] Devices appear in each other's **discovery lists**
- [ ] Both devices on **same WiFi network**
- [ ] **Logs show** incoming connection listener started
- [ ] **No firewall** blocking port 53318
- [ ] **Port 53318** is listening on target device

## Quick Test Commands

### Test 1: Verify App Started Correctly

**On each device, check logs for**:
```
✅ [DiscoveryService] Initialization complete!
✅ [IncomingConnection] ✅ Listening for incoming connections on port 53318
```

### Test 2: Verify Discovery Works

**Both devices should show**:
```
✅ [DiscoveryService] 🆕 New device discovered: <device-name>
```

### Test 3: Test Connection Attempt

**When you tap to connect, you should see**:

**On Device A (initiator)**:
```
[UI] 🔌 Device selected: iPhone-xxx at 192.168.1.142
[ConnectionService] 🔌 Connecting to iPhone-xxx at 192.168.1.142:53318
[ConnectionService] ✅ Socket connected successfully
[ConnectionService] ✅ Connected to iPhone-xxx
```

**On Device B (target)**:
```
[IncomingConnection] 📞 Incoming connection from 192.168.1.141
[IncomingConnection] 🤝 Handshake received from Android-xxx
[DiscoveryService] 📞 Incoming P2P connection from Android-xxx
```

## Error Code Reference

| Error Code | Meaning | Solution |
|------------|---------|----------|
| errno = 61 | Connection refused | Target app not listening - restart it |
| errno = 60 | Connection timeout | Network issue or firewall |
| errno = 64 | Host is down | Device offline or wrong IP |
| errno = 51 | Network unreachable | Different networks or no WiFi |

## Still Not Working?

If you've tried everything above and still getting "Connection refused":

1. **Verify code changes are applied**:
   ```bash
   # Check if IncomingConnectionService is initialized
   grep -n "IncomingConnectionService" lib/services/discovery_service.dart
   
   # Should show the initialization code around line 105-111
   ```

2. **Check for compile errors**:
   ```bash
   flutter analyze
   ```

3. **Try with 3 devices**:
   - If Device A → Device B fails
   - But Device B → Device C works
   - Then Device B's app is the problem

4. **Last resort - Clean rebuild**:
   ```bash
   # Complete clean rebuild
   flutter clean
   rm -rf .dart_tool/
   rm -rf build/
   flutter pub get
   flutter run
   ```

## Success Indicators

You know it's working when:

✅ Connection completes in < 2 seconds
✅ See "Connected" status with green toast
✅ Can send messages immediately
✅ No "Connection refused" errors
✅ Logs show successful handshake
✅ Keep-alive pings appear every 30 seconds

## Summary

**Most common cause**: The target device's app needs to be **restarted** to start the incoming connection listener on port 53318.

**Quick fix**: Force close and restart the app on **BOTH** devices, wait for discovery, then try connecting again.
