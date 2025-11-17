# Android Multicast Fix

## Problem
On Android, you were getting this error after some time:
```
SocketException: Send failed (OS Error: Operation not permitted, errno = 1)
```

This happens because **Android requires a WiFi Multicast Lock** to send and receive multicast packets. Without this lock, the system blocks multicast operations to save battery.

## Solution Implemented

### 1. **Native Android Code** (MainActivity.kt)
Added a method channel to acquire/release the multicast lock:
- Acquires `WifiManager.MulticastLock` to enable multicast packets
- Acquires `PowerManager.WakeLock` to prevent device sleep during discovery
- Automatically releases locks when app is destroyed

### 2. **Dart Platform Helper** (multicast_platform_helper.dart)
Created a Dart service to communicate with the native Android code:
- `acquireMulticastLock()` - Acquires the lock on Android
- `releaseMulticastLock()` - Releases the lock on Android
- Does nothing on iOS/macOS (not needed)

### 3. **Updated Discovery Service**
Modified `DiscoveryService.initialize()` to:
- Acquire multicast lock before starting discovery on Android
- Release lock in `dispose()` method

### 4. **Improved Multicast Service**
Enhanced `MulticastService` with:
- Better network interface selection (prefers WiFi addresses like 192.168.x.x)
- Android-specific socket configuration
- Detailed error logging with troubleshooting tips
- Better handling of VPN and virtual interfaces

### 5. **Added Permissions**
Added to AndroidManifest.xml:
```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

## How It Works

### Before Fix:
1. App starts → Tries to send UDP multicast
2. Android blocks it → SocketException thrown
3. Discovery fails

### After Fix:
1. App starts → Acquires multicast lock via native code
2. Android allows multicast packets
3. UDP announcements sent successfully
4. Discovery works! 🎉

## Testing

1. **Run on Android device or emulator**:
   ```bash
   flutter run
   ```

2. **Watch for these logs**:
   ```
   [DiscoveryService] Acquiring Android multicast lock...
   MulticastLock acquired
   WakeLock acquired
   [MulticastService] Sent announcement: <device-name> (XXX bytes)
   ```

3. **On second device**, you should see:
   ```
   [MulticastService] Received announcement from <device-name> (IP:PORT)
   ```

## Key Points

✅ **Multicast lock is REQUIRED on Android** for UDP multicast to work
✅ **Wake lock keeps device awake** during discovery (10 min timeout)
✅ **Automatic cleanup** - locks released when app is destroyed
✅ **Works on WiFi only** - multicast doesn't work on mobile data
✅ **Location permission** still required on Android for WiFi scanning

## Troubleshooting

If discovery still doesn't work on Android:

1. **Check WiFi connection**:
   - Must be connected to WiFi (not mobile data)
   - Both devices on same network

2. **Grant permissions**:
   - Location permission (required for WiFi on Android)
   - Go to Settings → Apps → cpft → Permissions

3. **Check logs** for:
   - "MulticastLock acquired" ✅
   - "Sent announcement: X bytes" ✅
   - "Operation not permitted" ❌ (means lock not acquired)

4. **Network restrictions**:
   - Some corporate/public WiFi networks block multicast
   - Try on home WiFi network
   - Some Android devices/ROMs have multicast bugs

5. **Restart app** if lock fails to acquire

## Technical Details

**WifiManager.MulticastLock**:
- Allows app to receive WiFi multicast packets
- Increases battery usage (why Android requires explicit lock)
- Must be released when not in use

**PowerManager.WakeLock**:
- Prevents CPU from sleeping
- Ensures discovery continues in background
- 10-minute timeout to prevent battery drain
- Partial wake lock (screen can turn off)

**Method Channel**:
- Flutter → Kotlin communication
- Channel: `com.example.cpft/multicast`
- Methods: `acquireMulticastLock`, `releaseMulticastLock`
