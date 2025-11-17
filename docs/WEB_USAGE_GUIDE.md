# How to Send and Receive Files via Web Browser

## Quick Start Guide

### Receiving Files from Browser → App

1. **Open CPFT app** on your phone/tablet
2. **Tap "Web Link"** button (floating button at bottom)
3. **Share the link** (e.g., `http://192.168.1.100:8080`) with sender
4. Sender **opens link in browser**
5. Sender **switches to "📥 Receive Files" tab** (uploads TO your device)
6. Sender **drags & drops files** or clicks to select
7. Files appear in your **Downloads folder**

### Sending Files from App → Browser

1. **Open CPFT app** on your phone/tablet  
2. **Tap "Web Link"** button
3. **Share the link** with receiver
4. Receiver **opens link in browser**
5. Receiver **switches to "📤 Send Files" tab** (downloads FROM your device)
6. **In the app**, you need to make files available:

**Option A: Via Connection Screen (Coming Soon)**
- Open a P2P connection
- Send files normally
- Files will automatically appear in web interface

**Option B: Direct Share (Implementation Needed)**
Currently, to send files TO web browsers, you need to:
1. Use the P2P connection to send files to another CPFT device
2. OR wait for the "Share to Web" feature (next update)

## Current Limitations

❗ **Important**: The current implementation primarily supports:
- ✅ **Receiving files FROM browsers** (upload to app)
- ⚠️ **Sending files TO browsers** (requires manual file selection in app)

##To be implemented:
- [ ] Button to add files to web share
- [ ] File picker to select files for web download
- [ ] Integration with file manager

## Workaround for Now

To share files with web users RIGHT NOW:

### Method 1: Hybrid Approach
1. Start web server (tap "Web Link")
2. Have receiver open the link  
3. Switch to "📥 Receive Files" tab in browser
4. **Receiver uploads files TO you**

### Method 2: Use P2P Mode
1. Install CPFT on both devices
2. Use normal P2P file transfer
3. Use web mode only for receiving

## Tab Explanation

### 📥 Receive Files Tab (Browser → App)
- **Purpose**: Upload files FROM browser TO the CPFT app
- **Use when**: Someone wants to send YOU files
- **Process**: Drag & drop or click to select files
- **Result**: Files saved to Downloads folder on your device

### 📤 Send Files Tab (App → Browser)  
- **Purpose**: Download files FROM the CPFT app TO browser
- **Use when**: You want to send files to SOMEONE ELSE
- **Process**: Files you share appear here for download
- **Result**: Receiver clicks download button to save files

## Next Update Features

The next version will include:
- ✅ "Share to Web" button in app
- ✅ File picker to select files for web sharing
- ✅ Real-time file list updates
- ✅ Remove files from web share
- ✅ Expiry time for shared files

## Technical Note

The web server needs to be integrated with a file sharing mechanism. Currently:
- Web server has `addFileForDownload(path, name)` method
- Need UI to call this method with selected files
- Files then appear in "📤 Send Files" tab for download
