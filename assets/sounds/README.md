# Sound Assets

This directory contains sound effects used throughout the app.

## Required Sound Files

Place the following MP3 sound files in this directory:

1. **device_discovered.mp3** - Plays when a new device appears on the radar
   - Suggested: Short, pleasant "ping" or "pop" sound
   - Duration: ~0.5 seconds

2. **connection_request.mp3** - Plays when receiving a connection request
   - Suggested: Attention-grabbing but not alarming sound
   - Duration: ~0.8 seconds

3. **connection_success.mp3** - Plays when connection is successfully established
   - Suggested: Positive, uplifting sound (e.g., soft chime)
   - Duration: ~1 second

4. **connection_failed.mp3** - Plays when connection fails or is rejected
   - Suggested: Subtle error sound (not harsh)
   - Duration: ~0.5 seconds

5. **transfer_start.mp3** - Plays when a file transfer begins
   - Suggested: Swoosh or transition sound
   - Duration: ~0.5 seconds

6. **transfer_complete.mp3** - Plays when file transfer completes successfully
   - Suggested: Success chime or ding
   - Duration: ~1 second

7. **transfer_failed.mp3** - Plays when file transfer fails
   - Suggested: Gentle error tone
   - Duration: ~0.5 seconds

8. **disconnect.mp3** - Plays when disconnecting from a device
   - Suggested: Subtle disconnect sound
   - Duration: ~0.5 seconds

9. **notification.mp3** - Generic notification sound
   - Suggested: Neutral notification tone
   - Duration: ~0.5 seconds

10. **message_sent.mp3** - Plays when sending a text message
    - Suggested: Quick send sound (swoosh)
    - Duration: ~0.3 seconds

11. **message_received.mp3** - Plays when receiving a text message
    - Suggested: Gentle notification
    - Duration: ~0.5 seconds

## Creating Placeholder Sounds

If you don't have custom sounds ready, you can:

1. Use royalty-free sound effects from:
   - https://freesound.org/
   - https://mixkit.co/free-sound-effects/
   - https://www.zapsplat.com/

2. Generate simple tones using online tools:
   - https://www.beepberry.com/
   - https://onlinetonegenerator.com/

3. For testing, create silent placeholder files or use the same sound for all events.

## File Format Requirements

- Format: MP3 (recommended for cross-platform compatibility)
- Sample Rate: 44.1kHz or 48kHz
- Bit Rate: 128kbps or higher
- Channels: Mono or Stereo
- Keep file sizes small (<50KB per sound) for app size optimization

## User Control

Users can enable/disable sounds in the app settings. The SoundService respects this preference.
