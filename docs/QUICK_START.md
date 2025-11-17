# Quick Start Guide - Testing LocalSend Discovery

## ✅ Implementation Complete!

Your app now uses **LocalSend's discovery architecture**:
- ✅ UDP Multicast for announcements
- ✅ HTTP Server for registration
- ✅ HTTP Client for responding to announcements
- ✅ Unified DiscoveryService combining all components

## 🎯 Testing Right Now

### Option 1: Test with Two Real Devices (RECOMMENDED)

**Best for real-world testing:**

1. **On Terminal 1 - Run on iPhone/Android:**
   ```bash
   # Wait for device list, then choose your phone
   # Type number and press Enter
   ```

2. **On Terminal 2 - Open new terminal and run:**
   ```bash
   cd /Users/dineshhannurkar/Development/cpft/cpft
   flutter run
   # Choose your second device (Android phone, or another iPhone)
   ```

3. **Expected Result:**
   - Both apps start
   - Both show "Initializing LocalSend-style discovery..."
   - After 5-10 seconds, devices appear in each other's list
   - You'll see logs showing announcements and registrations

### Option 2: Test with macOS (Quick Test)

**For immediate testing on one machine:**

1. **Run on macOS** (option 3 in the terminal)
2. **Open second terminal and run again** on macOS
   - Flutter allows running multiple instances
   - They'll discover each other via localhost

### Option 3: Test on Real Device + macOS

1. **Run on your physical phone** (iPhone or Pixel)
2. **Run on macOS**
3. **Make sure Mac and phone are on SAME WiFi network**

## 📱 Current Terminal Status

Your terminal is waiting for device selection. Choose:
- **[3] macOS** - For quick local testing (can run 2 instances)
- **[2] iPhone 16e** - For iOS testing (need 2nd device)
- **[1] Android Emulator** - Not recommended (emulator IPs don't work for multicast)

## 🔍 What to Look For

### In Terminal Logs:
```
✅ [DiscoveryService] Initializing...
✅ [HttpServer] Server started on port 53317
✅ [MulticastService] Listening on 224.0.0.167:53317
✅ [MulticastService] Sent announcement: cpft-...
✅ [MulticastService] Received announcement from cpft-...
✅ [HttpClient] Registering with 192.168.x.x:53317...
✅ [HttpServer] Registered device: cpft-...
✅ UI updated: Device discovered - cpft-... at 192.168.x.x:53317
```

### In App UI:
- "Using LocalSend-style discovery" info banner (blue)
- "Available Devices" section
- Device names appearing in the list
- Refresh button works to re-announce

## 🚨 Important Notes

### Network Requirements:
- ✅ Same WiFi network (192.168.x.x or 10.x.x.x)
- ❌ NO VPN active
- ❌ NO mobile data (WiFi only)
- ✅ Both devices awake and app in foreground

### Why Android Emulator Won't Work:
- Emulator IP is `10.0.2.15` (NAT network)
- Multicast doesn't cross NAT boundaries
- Use real devices for testing

### macOS Testing:
- macOS can run multiple Flutter instances
- They'll use localhost (127.0.0.1)
- Perfect for quick functionality testing
- Won't test real network multicast

## 🎬 Quick Test Steps (macOS)

1. **Terminal 1 - Already running, select [3] macOS**
2. **Terminal 2 - New terminal:**
   ```bash
   cd /Users/dineshhannurkar/Development/cpft/cpft
   flutter run -d macos
   ```
3. **Watch logs** - You'll see both instances discover each other
4. **Check UI** - Each app shows the other in device list

## 📊 Monitoring

### Good Signs:
- "Server started on port 53317" ✓
- "Sent announcement" every 5 seconds ✓
- "Received announcement" from other device ✓
- "Registered device" in server logs ✓
- Devices appearing in UI list ✓

### Bad Signs:
- "Error binding socket" → Port in use, restart app
- "Network is unreachable" → Check WiFi
- No "Received announcement" → Devices on different networks
- "Self-discovered" (normal, ignored) → Device found itself

## 🐛 If Discovery Not Working

1. **Check Network:**
   ```bash
   # On Mac
   ifconfig | grep "inet "
   # Should show 192.168.x.x or 10.x.x.x
   ```

2. **Disable VPN** on all devices

3. **Firewall:**
   - macOS: System Settings → Network → Firewall
   - Allow incoming connections on port 53317

4. **Restart App:**
   - Press `q` in terminal
   - Run `flutter run` again

## 📝 Next Steps After Testing

Once discovery works:
1. ✅ Verify devices appear on both sides
2. ✅ Test refresh button
3. ✅ Test with 2 real devices on same WiFi
4. 📝 Implement file transfer (next feature)
5. 📝 Add device favorites
6. 📝 Improve UI with device icons

## 🎉 You're Ready!

The implementation is complete. Choose a device in the terminal and start testing!

For detailed explanation of how it works, see `LOCALSEND_IMPLEMENTATION.md`.
