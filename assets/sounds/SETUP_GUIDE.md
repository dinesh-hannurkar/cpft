# Quick Sound Setup Guide

## Option 1: Download Free Sound Packs

Visit these sites and download short notification sounds:
- **Mixkit**: https://mixkit.co/free-sound-effects/notification/
- **Freesound**: https://freesound.org/ (search for "notification", "beep", "ding")
- **Zapsplat**: https://www.zapsplat.com/sound-effect-category/notifications/

## Option 2: Use System Sounds (For Testing)

For quick testing, you can use the same sound file for all events. Just duplicate one MP3 file 11 times with different names:

```bash
cd assets/sounds

# If you have one sound file called 'sound.mp3', run:
cp sound.mp3 device_discovered.mp3
cp sound.mp3 connection_request.mp3
cp sound.mp3 connection_success.mp3
cp sound.mp3 connection_failed.mp3
cp sound.mp3 transfer_start.mp3
cp sound.mp3 transfer_complete.mp3
cp sound.mp3 transfer_failed.mp3
cp sound.mp3 disconnect.mp3
cp sound.mp3 notification.mp3
cp sound.mp3 message_sent.mp3
cp sound.mp3 message_received.mp3
```

## Option 3: Generate Simple Tones

Use online tone generators:
1. Visit https://onlinetonegenerator.com/
2. For each sound type, generate different frequencies:
   - Success sounds: 800-1000 Hz (pleasant)
   - Failure sounds: 400-500 Hz (lower)
   - Notifications: 600-800 Hz (neutral)
3. Keep duration under 1 second
4. Export as MP3 and save with appropriate filenames

## Recommended Sound Characteristics

| Event | Tone | Duration | Volume |
|-------|------|----------|--------|
| Device Discovered | Short ping | 0.3s | Medium |
| Connection Request | Attention beep | 0.8s | High |
| Connection Success | Pleasant chime | 1.0s | Medium |
| Connection Failed | Low tone | 0.5s | Low |
| Transfer Start | Swoosh | 0.5s | Medium |
| Transfer Complete | Success ding | 1.0s | Medium |
| Transfer Failed | Error beep | 0.5s | Low |
| Disconnect | Subtle beep | 0.5s | Low |
| Notification | Generic beep | 0.5s | Medium |
| Message Sent | Quick whoosh | 0.3s | Low |
| Message Received | Gentle notification | 0.5s | Medium |

## Installing Sounds

1. Place all 11 MP3 files in `assets/sounds/` directory
2. Run `flutter pub get` to ensure assets are recognized
3. Restart the app

## Testing Sounds

After adding sound files:
1. Run the app
2. Check logs for any sound loading errors
3. Test each event:
   - Device discovery: Wait for a device to appear on radar
   - Connection: Try connecting to a device
   - Transfer: Send/receive a file
   - Messages: Send/receive text messages
   - Disconnect: Disconnect from a device

## Disabling Sounds

Sounds can be enabled/disabled via:
```dart
await SoundService().setSoundsEnabled(false); // Disable
await SoundService().setSoundsEnabled(true);  // Enable
```

You can add a settings toggle in the app's settings screen to let users control this preference.
