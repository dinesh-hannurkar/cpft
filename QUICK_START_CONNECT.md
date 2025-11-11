# Quick Start Guide: Using the Connect Feature

## 🚀 How to Use

### Step 1: Launch the App on Multiple Devices

Run the app on at least 2 devices:

```bash
# On your development machine
flutter run

# Or build and install APK on Android
flutter build apk
# Install the APK on Android devices

# For iOS, run from Xcode or
flutter run -d <device-id>
```

### Step 2: Discover Devices

Both devices should appear in each other's discovery list within a few seconds.

**You'll see**:
```
┌────────────────────────────────┐
│ 📱 This Device                │
│    iPhone-MyiPhone-1234        │
└────────────────────────────────┘

Found 2 devices:

🤖 Android Device
   Android  🔐 5678
   📶 192.168.1.142

💻 MacBook Pro
   macOS    🔐 9012
   📶 192.168.1.143
```

### Step 3: Connect to a Device

**Tap on any device card** → The connection screen opens

**You'll see**:
```
╔══════════════════════════════╗
║ Android Device               ║
║ Connecting...                ║
╚══════════════════════════════╝

[Connecting banner]
🔄 Connecting to Android Device...
```

### Step 4: Wait for Connection

After ~1 second, you should see:

```
╔══════════════════════════════╗
║ Android Device               ║
║ 192.168.1.142 • Connected    ║
╚══════════════════════════════╝

✅ Connected to Android Device

[Empty chat state]
💬 No messages yet
   Send a message to start the conversation
```

### Step 5: Send Messages

Type in the message box at the bottom and press Enter or tap Send.

**Your message appears**:
```
                    ┌───────────────┐
                    │ Hello there!  │
                    │ 12:34         │
                    └───────────────┘
```

**Their reply appears**:
```
┌───────────────┐
│ Hi! How are   │
│ you?          │
│ 12:35         │
└───────────────┘
```

### Step 6: Disconnect

- Tap the **X** button in the top-right corner
- Or press the **Back** button
- The app sends a goodbye message and closes the connection

## 📱 UI Elements Explained

### Device Discovery Screen

| Element | Description |
|---------|-------------|
| **This Device Card** | Shows your device's unique name (what others see) |
| **Status Badges** | Green "Discovering" when active, Orange "Initializing" when starting |
| **Device Cards** | Tap to connect, shows platform, ID, and IP |
| **Refresh Button** | Re-scan for devices (top-right) |

### Connection Screen

| Element | Description |
|---------|-------------|
| **Status Banner** | Blue = Connecting, Green = Connected, Red = Failed |
| **Message Bubbles** | Left = Received (gray), Right = Sent (blue) |
| **Message Input** | Type and press Enter or tap Send |
| **Disconnect Button** | X button in top-right |

## 🎯 What to Test

### ✅ Basic Flow
1. Launch on 2 devices
2. See both devices in discovery list
3. Tap one device
4. See "Connected" status
5. Send messages back and forth
6. Disconnect

### ✅ Error Handling
1. Turn off WiFi on one device → "Connection Failed"
2. Tap Retry → Should reconnect
3. Close app on one device while chatting → "Disconnected"

### ✅ Multiple Messages
1. Type quickly and send multiple messages
2. All should appear in order
3. Auto-scroll to latest message

## 🐛 Troubleshooting

### Device Not Appearing

**Problem**: Other device doesn't show up in the list

**Solutions**:
- ✅ Check both devices are on the same WiFi network
- ✅ Tap the refresh button (top-right)
- ✅ Wait 5-10 seconds (multicast announcement interval)
- ✅ Restart the app on both devices

**On iOS specifically**:
- ✅ Go to Settings → Privacy → Local Network
- ✅ Find "cpft" and toggle it ON
- ✅ Restart the app

### Connection Fails

**Problem**: "Connection failed" banner appears

**Solutions**:
- ✅ Check the device is still in the discovery list
- ✅ Tap "Retry" button
- ✅ Make sure the other device's app is still running
- ✅ Check firewall settings (allow port 53317)

### Messages Not Delivered

**Problem**: Sent messages don't appear on other device

**Check**:
1. Status bar says "Connected" (not "Connecting" or "Disconnected")
2. No error banners showing
3. Other device's app is in foreground

**Solutions**:
- ✅ Disconnect and reconnect
- ✅ Restart both apps
- ✅ Check console logs for errors

## 📊 Console Logs to Monitor

### Successful Connection
```
[ConnectionService] 🔌 Connecting to Android-Pixel-5678 at 192.168.1.142:53317
[ConnectionService] ✅ Socket connected successfully
[ConnectionService] 📤 Sent message: handshake
[ConnectionService] ✅ Connected to Android-Pixel-5678
```

### Message Exchange
```
[ConnectionService] 📤 Sent message: text
[ConnectionService] 📥 Received message: text from Android-Pixel-5678
```

### Disconnect
```
[ConnectionService] 🔌 Disconnecting...
[ConnectionService] ✅ Disconnected
```

## 🎨 Example Chat Session

```
Device A (iPhone)              Device B (Android)
─────────────────              ──────────────────

Tap "Android-Pixel-5678"
                               
Connecting... 🔄
                               Incoming connection
                               from 192.168.1.141
✅ Connected
                               ✅ Connected

Type: "Hello!"
Send →
                    Hello! →
                               ← Hello!
                               
                               Type: "Hi there!"
                               Send →
← Hi there!
Hi there! ←

Type: "How are you?"
Send →
                    How are you? →
                               ← How are you?

                               Type: "I'm good!"
                               Send →
← I'm good!
I'm good! ←

Tap X button
🔌 Disconnecting...
                               ⚠️ Disconnected
✅ Back to discovery
```

## 💡 Tips

1. **Keep Screen On**: The app uses WakeLock to keep the screen on during discovery

2. **Battery Usage**: Active connections use minimal battery, but continuous discovery uses more

3. **Background**: Currently, connections close when app goes to background (add background handling for production)

4. **Network Switching**: If you switch WiFi networks, restart the app

5. **Firewall**: Some networks block multicast or custom ports - use a home/trusted network

## 🔧 Advanced Usage

### Custom Messages

You can extend the message types:

```dart
// Send custom message type
final message = DeviceMessage(
  type: 'file_transfer',
  content: 'document.pdf',
  senderName: myDeviceName,
  metadata: {
    'fileSize': 1024000,
    'mimeType': 'application/pdf',
  },
);
await connectionService.sendMessage(message);
```

### Connection Listeners

```dart
// Listen to connection status changes
connectionService.addStatusListener((info) {
  if (info.status == ConnectionStatus.connected) {
    print('Connected at ${info.connectedAt}');
  } else if (info.status == ConnectionStatus.failed) {
    print('Failed: ${info.error}');
  }
});

// Listen to incoming messages
connectionService.addMessageListener((message) {
  if (message.type == 'text') {
    print('${message.senderName}: ${message.content}');
  }
});
```

## ✨ Demo Script

Perfect for showing off the feature:

1. **Setup** (30 sec)
   - Launch app on iPhone and Android
   - Show both devices discovering each other
   - Point out unique device IDs

2. **Connect** (15 sec)
   - Tap Android device from iPhone
   - Show "Connecting" → "Connected" transition
   - Point out connection status

3. **Chat** (45 sec)
   - Send "Hello!" from iPhone → appears on Android
   - Reply "Hi there!" from Android → appears on iPhone
   - Send a few more messages quickly
   - Show auto-scroll behavior

4. **Disconnect** (10 sec)
   - Tap X button
   - Show graceful disconnect
   - Back to discovery screen

**Total**: ~2 minutes for full demo!

## 📚 Next Steps

Now that connections work, you can:

1. **Add File Transfer**: Send images, documents
2. **Add Encryption**: Secure the connection with TLS
3. **Add Notifications**: Alert users of new messages
4. **Add Persistence**: Save message history
5. **Add Group Chat**: Connect to multiple devices

Check `CONNECTION_FEATURE.md` for detailed API documentation and future enhancement ideas!
