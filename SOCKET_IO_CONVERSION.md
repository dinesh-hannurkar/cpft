# WebRTC Socket.IO Conversion

## Summary
Successfully converted the WebRTC file transfer implementation from WebSocket to Socket.IO client to match your Node.js signaling server.

## Changes Made

### 1. Dependencies (`pubspec.yaml`)
- ❌ Removed: `web_socket_channel: ^3.0.1`
- ✅ Added: `socket_io_client: ^2.0.3+1`

### 2. WebRTC Service (`webrtc_file_transfer_service.dart`)

#### Architecture Changes
- **Before**: WebSocket-based with peer-to-peer ID exchange
- **After**: Socket.IO-based with room-based architecture

#### Key Modifications

**Class Fields:**
```dart
// Old
WebSocketChannel? _signalingChannel;
String? _peerId;

// New
IO.Socket? _socket;
String? _roomId;
String? _mySocketId;
```

**Connection Method:**
```dart
// Old: connectToSignalingServer() - No parameters, peer ID assigned
// New: connectToSignalingServer(String roomId) - Room-based joining
```

**Socket.IO Events Implemented:**
- `connect` - Get socket ID and join room
- `existing-peers` - Handle peers already in room
- `peer-joined` - Create offer when new peer joins
- `offer` - Receive and handle offer from peer
- `answer` - Receive and handle answer from peer
- `ice-candidate` - Exchange ICE candidates
- `peer-left` - Clean up when peer leaves
- `disconnect` - Handle disconnection

**Signal Sending:**
```dart
// Old: WebSocket JSON encoding
_signalingChannel!.sink.add(jsonEncode(payload));

// New: Socket.IO emit
_socket?.emit('offer', {
  'room': _roomId,
  'offer': offer.toMap(),
});
```

**Automatic Negotiation:**
- When joining a room with existing peers → automatically create offer
- When a new peer joins → automatically create offer
- Both peers can initiate connection (bidirectional)

### 3. UI Changes (`webshare_screen.dart`)

**WebRTCConnectionDialog:**
- ❌ Removed: Peer ID display and copy functionality
- ✅ Changed: Input from "Peer ID" to "Room ID"
- ✅ Updated: Helper text explains both devices must use same room
- ✅ Simplified: Removed signaling stream subscription logic

**Connection Flow:**
```dart
// Old: Initialize → Get Peer ID → Exchange IDs → Connect
// New: Enter Room ID → Join Room → Auto-connect
```

**Methods Updated:**
- `initialize()` → `initialize(String roomId)` - Now requires room ID
- Removed manual offer/answer/ICE candidate handling from UI
- All signaling now handled internally by service via Socket.IO events

## How to Use

### 1. Ensure Node.js Signaling Server is Running
```bash
# Your server should be running at:
http://192.168.1.179:3000
```

### 2. Connect from Both Devices
1. Tap "Connect WebRTC" button
2. Both devices enter the **same room ID** (e.g., "my-room")
3. Tap "Join Room"
4. Connection established automatically

### 3. Send Files
Once connected, use the file picker to select and send files via WebRTC data channel.

## Server URL
Signaling server URL is set in the service:
```dart
final String signalingServerUrl = 'http://192.168.1.179:3000';
```

To change it, edit `lib/features/webshare/services/webrtc_file_transfer_service.dart`

## Event Flow

### Initial Connection (Device A joins empty room)
1. Device A: `socket.emit('join-room', 'my-room')`
2. Server: `socket.emit('existing-peers', [])` // Empty array
3. Device A: Waits for peer

### Second Device Joins (Device B joins room with Device A)
1. Device B: `socket.emit('join-room', 'my-room')`
2. Server → Device B: `socket.emit('existing-peers', [deviceA_socketId])`
3. Device B: Creates offer for Device A
4. Device B: `socket.emit('offer', {room, offer})`
5. Server → Device A: `socket.emit('offer', {from, offer})`
6. Device A: Creates answer
7. Device A: `socket.emit('answer', {room, answer})`
8. Server → Device B: `socket.emit('answer', {from, answer})`
9. Both exchange ICE candidates via `ice-candidate` events
10. WebRTC connection established

### Alternative Flow (Device A creates offer when B joins)
1. Server → Device A: `socket.emit('peer-joined', deviceB_socketId)`
2. Device A: Creates offer for Device B
3. (Same as steps 4-10 above)

## Benefits of Room-Based Architecture

1. **Simpler UX**: No need to copy/paste peer IDs
2. **Flexible**: Multiple devices can join same room (though current implementation uses first peer)
3. **Reliable**: Server manages room membership
4. **Bidirectional**: Either peer can initiate connection
5. **Automatic**: Connection happens without manual steps

## Troubleshooting

### "Connection timeout" error
- Verify signaling server is running: `curl http://192.168.1.179:3000`
- Check both devices are on same network
- Ensure port 3000 is not blocked

### Devices don't connect
- Make sure both devices use **exact same room ID** (case-sensitive)
- Check logs for Socket.IO connection status
- Verify server logs show both devices joining same room

### File transfer fails
- Connection established but data channel might not be ready
- Check WebRTC connection state in logs
- Ensure STUN server is accessible (stun.l.google.com:19302)

## Next Steps

If you need to:
- Change signaling server URL → Edit `signalingServerUrl` in service
- Support multiple peers → Modify `existing-peers` handler to loop through all peers
- Add encryption → Implement DTLS-SRTP or application-level encryption
- Persist rooms → Add server-side room persistence

## Files Modified

1. `pubspec.yaml` - Dependencies
2. `lib/features/webshare/services/webrtc_file_transfer_service.dart` - Complete rewrite
3. `lib/features/webshare/presentation/webshare_screen.dart` - UI updates

All changes are backward compatible with your file transfer logic. Only the signaling mechanism changed.
