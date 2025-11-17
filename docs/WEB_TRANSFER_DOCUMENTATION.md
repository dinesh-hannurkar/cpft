# Web Browser File Transfer Feature

## Overview
The CPFT app now supports **browser-based file transfers**, allowing users to send files to the app without installing it. This is perfect for:
- Quick one-time transfers
- Sharing with people who don't have the app
- Cross-platform transfers (any device with a web browser)
- Public kiosks or shared computers

## How It Works

### Architecture
```
┌─────────────────┐         HTTP/WebSocket         ┌──────────────────┐
│  Web Browser    │◄──────────────────────────────►│  Flutter App     │
│  (Any Device)   │      Port 8080                 │  (Your Phone)    │
└─────────────────┘                                 └──────────────────┘
        │                                                    │
        │  1. User visits http://192.168.1.100:8080        │
        │  2. Drag & drop files to upload                   │
        │  3. Files sent via HTTP POST                      │
        │  4. WebSocket sends real-time status             │
        └──────────────────────────────────────────────────┘
                    Same Wi-Fi Network
```

### Components

#### 1. **WebServer** (`lib/services/web_server.dart`)
- HTTP server running on port 8080
- Serves a beautiful HTML5 page with drag-and-drop interface
- Handles file uploads via `multipart/form-data`
- WebSocket support for real-time progress updates
- Saves files to Downloads directory

Key endpoints:
- `GET /` - Serves HTML interface
- `POST /upload` - Receives file uploads
- `WS /ws` - WebSocket for real-time updates

#### 2. **DiscoveryService Integration**
Extended with web server management:
```dart
await discoveryService.startWebServer(port: 8080);  // Start server
final link = await discoveryService.getWebLink();   // Get shareable link
await discoveryService.stopWebServer();             // Stop server
```

#### 3. **UI Integration** (`device_discovery_screen.dart`)
- Floating action button "Web Link" in discovery screen
- Dialog showing shareable URL
- Copy to clipboard functionality
- Start/stop web server on demand

## Usage Instructions

### For the App User (Receiver)

1. **Open the CPFT app** on your phone/tablet
2. Tap the **"Web Link"** button (bottom-right)
3. **Share the displayed link** with the sender via:
   - Text message
   - Email
   - QR code (coming soon)
   - Verbally (for same room)

Example link: `http://192.168.1.100:8080`

### For the Sender (Browser User)

1. **Open the shared link** in any web browser
2. **Drag & drop files** onto the page, or click to select
3. **Wait for upload** to complete
4. Files are saved to the receiver's Downloads folder

### Supported Browsers
- ✅ Chrome/Edge (Desktop & Mobile)
- ✅ Firefox (Desktop & Mobile)
- ✅ Safari (Desktop & Mobile)
- ✅ Any modern browser with HTML5 support

## Web Interface Features

### Design
- **Beautiful gradient UI** (purple gradient background)
- **Real-time status indicators** (animated connection dot)
- **Drag-and-drop support** with visual feedback
- **Progress tracking** with percentage
- **File history** showing all uploaded files
- **Responsive design** works on mobile & desktop browsers

### User Experience
1. Visual feedback when dragging files over drop zone
2. Automatic file size formatting (bytes → KB → MB → GB)
3. Success confirmation with green checkmark
4. Error handling with user-friendly messages
5. Upload history with file names and sizes

## Security Considerations

⚠️ **Important Security Notes:**

### Current Implementation
- **No authentication** - anyone with the link can upload
- **No encryption** - files sent over HTTP (not HTTPS)
- **Same network only** - requires WiFi/LAN connection
- **No file size limits** - can cause memory issues

### Recommendations
1. **Only use on trusted networks** (home WiFi, not public WiFi)
2. **Stop server when not needed** (use "Stop & Close" button)
3. **Don't share link publicly** (only with trusted contacts)
4. **Check uploaded files** before opening

### Future Enhancements (TODO)
- [ ] Add password/PIN protection
- [ ] HTTPS support with self-signed certificates
- [ ] File size limits and validation
- [ ] File type restrictions
- [ ] Upload rate limiting
- [ ] Session timeouts
- [ ] QR code generation for easy sharing

## Technical Details

### Network Requirements
- Both devices must be on **same Wi-Fi network**
- Router must allow **device-to-device communication**
- Port **8080** must not be blocked by firewall
- App needs **local network permissions**

### File Handling
```dart
// Upload flow:
1. Browser sends POST /upload with multipart/form-data
2. Server extracts filename and binary data
3. Saves to Downloads directory with conflict resolution
4. Broadcasts "file_received" event via WebSocket
5. Confirms success to browser
```

### Conflict Resolution
If file exists, automatically renames:
- `document.pdf` → `document(1).pdf`
- `document(1).pdf` → `document(2).pdf`
- Preserves file extensions

### Dependencies
```yaml
dependencies:
  mime: ^1.0.5  # For multipart file parsing
```

## Code Examples

### Starting Web Server
```dart
// In your service/screen
final success = await _discoveryService.startWebServer(port: 8080);
if (success) {
  final link = await _discoveryService.getWebLink();
  print('Share this link: $link');
}
```

### Stopping Web Server
```dart
await _discoveryService.stopWebServer();
```

### Checking Status
```dart
if (_discoveryService.isWebServerRunning) {
  print('Web server is active');
}
```

## HTML Interface Code Structure

### Key Technologies
- **HTML5 Drag & Drop API** - For file selection
- **Fetch API** - For file uploads
- **WebSocket API** - For real-time updates
- **Pure CSS** - No frameworks, fast loading
- **Pure JavaScript** - No dependencies

### Features Breakdown
```javascript
// Drag & drop
uploadArea.addEventListener('drop', (e) => {
  e.preventDefault();
  uploadFiles(e.dataTransfer.files);
});

// File upload with progress
const formData = new FormData();
formData.append('file', file);
await fetch('/upload', { method: 'POST', body: formData });

// WebSocket updates
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.type === 'file_received') {
    showSuccess(data.filename);
  }
};
```

## Troubleshooting

### "Failed to start web server"
- **Cause:** Port 8080 already in use
- **Solution:** Kill other apps using port 8080, or modify port number

### "Unable to generate web link"
- **Cause:** Not connected to WiFi
- **Solution:** Connect to WiFi network

### "Upload failed"
- **Cause:** Network disconnection or large file
- **Solution:** Check connection, try smaller files

### Browser can't access link
- **Cause:** Devices on different networks
- **Solution:** Ensure both on same WiFi

### Files not appearing
- **Cause:** Permission issues
- **Solution:** Grant storage permissions to app

## Performance Notes

### Memory Usage
- Large files loaded entirely into memory
- Recommend files < 100MB for stability
- Multiple concurrent uploads may cause slowdown

### Network Speed
- Upload speed depends on WiFi strength
- Typical speeds: 5-50 MB/s on WiFi
- No chunking, so large files = longer wait

## Future Roadmap

### Phase 1 (Current)
- ✅ Basic HTTP server
- ✅ File upload
- ✅ WebSocket notifications
- ✅ Shareable link generation
- ✅ Beautiful web UI

### Phase 2 (Planned)
- [ ] QR code generation
- [ ] Password protection
- [ ] File size limits
- [ ] Upload progress bar
- [ ] Multiple file selection

### Phase 3 (Future)
- [ ] HTTPS/SSL support
- [ ] Reverse file transfer (app → browser download)
- [ ] Text message sending
- [ ] File preview in browser
- [ ] Folder uploads

## Comparison with P2P Mode

| Feature | P2P (App-to-App) | Web Browser Mode |
|---------|------------------|------------------|
| Setup Required | Install app both sides | No installation needed |
| Speed | Very fast (TCP direct) | Fast (HTTP) |
| File Size | Unlimited | Recommended < 100MB |
| Security | Handshake protocol | Open (same network) |
| Discovery | Automatic (UDP/mDNS) | Manual (share link) |
| Platform | Flutter apps only | Any browser |
| Background Transfer | Yes (with foreground service) | No |

## Best Use Cases

### Use Web Browser Mode When:
- ✅ Sender doesn't have the app
- ✅ One-time quick transfer
- ✅ Transferring to someone in same room
- ✅ Working on public/shared computer
- ✅ Cross-platform (Linux, ChromeOS, etc.)

### Use P2P Mode When:
- ✅ Both have the app
- ✅ Frequent transfers
- ✅ Large files (> 100MB)
- ✅ Need background transfers
- ✅ Maximum security needed

## Summary

The web browser file transfer feature makes CPFT accessible to anyone with a web browser, eliminating the need for app installation for senders. It's perfect for quick, casual file sharing scenarios while maintaining the beautiful UI and user experience that CPFT is known for.

**Key Advantages:**
- 📱 Universal access (any device)
- 🚀 Zero setup for sender
- 💎 Beautiful interface
- ⚡ Real-time updates
- 🔄 Easy link sharing

**Remember:** This feature complements the P2P mode - use whichever is more convenient for your situation!
