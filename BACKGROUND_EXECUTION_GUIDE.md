# Background Execution Guide

## Changes Made

### 1. Wake Lock Management
- **P2P Chat Screen**: Added wake lock that activates when connected and releases when disconnected
- **WebRTC Chat Screen**: Already had wake lock implementation
- Wake locks keep the CPU active even when the screen is off

### 2. Foreground Service Configuration
- Updated notification channel importance from LOW to DEFAULT for better visibility
- Enabled `allowWakeLock` and `allowWifiLock` in foreground task options
- Service automatically starts when first device connects
- Service stops when all devices disconnect

### 3. Connection Manager
- Already configured to start foreground service on first connection
- Stops foreground service when no connections remain
- Updates notification with connection count

## User Instructions for Best Performance

### Android Battery Optimization Settings

To ensure the app works properly in the background, users should:

1. **Disable Battery Optimization for CPFT**
   - Go to: Settings → Apps → CPFT → Battery
   - Select "Unrestricted" battery usage
   - Or: Settings → Battery → Battery Optimization → Select "All apps" → Find CPFT → Select "Don't optimize"

2. **Allow Background Activity**
   - Settings → Apps → CPFT → Battery → Background restriction
   - Select "Unrestricted"

3. **Disable Adaptive Battery (Optional)**
   - Settings → Battery → Adaptive Battery → Turn OFF
   - Or allow CPFT specifically

4. **Lock App in Recent Apps (Some Manufacturers)**
   - Open Recent Apps
   - Find CPFT
   - Tap the lock icon (if available)

### Manufacturer-Specific Settings

#### Samsung
- Settings → Apps → CPFT → Battery → Optimize battery usage → All → CPFT → Turn OFF
- Settings → Device care → Battery → App power management → Apps that won't be put to sleep → Add CPFT

#### Xiaomi/MIUI
- Settings → Apps → Manage apps → CPFT
- Enable "Autostart"
- Battery saver → Choose apps → CPFT → No restrictions
- Permissions → Other permissions → Display pop-up windows while running in background

#### Huawei/EMUI
- Settings → Apps → Apps → CPFT → Battery
- App launch → Manage manually
- Enable "Auto-launch", "Secondary launch", "Run in background"

#### OnePlus/OxygenOS
- Settings → Apps → CPFT → Battery → Battery optimization → Don't optimize
- Settings → Battery → Battery optimization → CPFT → Don't optimize

#### Oppo/ColorOS
- Settings → Battery → Power Saving Mode → Turn OFF (or add CPFT to exceptions)
- Settings → Additional Settings → Privacy → Special app access → Battery optimization → CPFT → Don't optimize

## Technical Details

### How It Works

1. **Foreground Service**: Displays a persistent notification and keeps the app process alive
2. **Wake Lock**: Keeps the CPU active even when screen is off
3. **WiFi Lock**: Maintains WiFi connection when screen is off
4. **Background Service**: Runs every 5 seconds to update notification and keep connections alive

### What Gets Protected

- ✅ Active P2P connections remain open
- ✅ File transfers continue when screen is off
- ✅ Message delivery works in background
- ✅ WebRTC connections stay active
- ✅ Network discovery continues running

### Limitations

- Background execution may still be limited by aggressive battery savers
- Some manufacturers require manual exemption
- Doze mode may still affect app on some devices (but foreground service minimizes impact)
- Users must grant necessary permissions

## Testing

To verify background execution works:

1. Connect to another device
2. Verify foreground service notification appears
3. Lock the device or turn screen off
4. Send a file from the other device
5. Check if transfer completes successfully
6. Unlock device and verify file was received

## Future Improvements

- Add in-app prompt to guide users to disable battery optimization
- Implement battery optimization check on app start
- Show warning if battery optimization is enabled
- Add documentation link in settings screen
