# Connection Feature Architecture

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         CPFT App Architecture                    │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────────┐                    ┌──────────────────────┐
│   Device Discovery   │                    │  Device Discovery    │
│      Screen          │                    │       Screen         │
│  ┌────────────────┐  │                    │  ┌────────────────┐  │
│  │ Found Devices  │  │                    │  │ Found Devices  │  │
│  │  - Android     │◄─┼────────────────────┼─►│  - iPhone      │  │
│  │  - Mac         │  │   UDP Multicast    │  │  - Mac         │  │
│  │  - iPhone      │  │    224.0.0.167     │  │  - Android     │  │
│  └────────────────┘  │      :53317        │  └────────────────┘  │
│         │             │                    │         │            │
│         │ Tap Device  │                    │         │ Tap Device │
│         ▼             │                    │         ▼            │
│  ┌────────────────┐  │                    │  ┌────────────────┐  │
│  │  Connection    │  │    TCP Socket      │  │  Connection    │  │
│  │    Screen      │◄─┼────────────────────┼─►│    Screen      │  │
│  │                │  │     :53317         │  │                │  │
│  │  [Chat UI]     │  │                    │  │  [Chat UI]     │  │
│  │  - Send msg    │  │  ┌──────────────┐  │  │  - Receive msg │  │
│  │  - Receive msg │  │  │  Message     │  │  │  - Send msg    │  │
│  └────────────────┘  │  │  {type, ...} │  │  └────────────────┘  │
└──────────────────────┘  └──────────────┘  └──────────────────────┘
   Device A (iPhone)                            Device B (Android)
```

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  DeviceDiscoveryScreen          ConnectionScreen            │
│  - Display devices              - Chat interface            │
│  - Refresh button               - Send/receive messages     │
│  - Navigate to connect          - Status indicators         │
│                                                              │
└─────────────────┬───────────────────────┬───────────────────┘
                  │                       │
         ┌────────▼────────┐     ┌───────▼───────────┐
         │                 │     │                    │
         │ DiscoveryService│     │ ConnectionService  │
         │                 │     │                    │
         │ - Initialize    │     │ - Connect()        │
         │ - Announce()    │     │ - SendMessage()    │
         │ - Listeners     │     │ - Disconnect()     │
         │                 │     │ - Message buffer   │
         └────────┬────────┘     └──────────┬─────────┘
                  │                         │
      ┌───────────┼─────────────┐           │
      │           │             │           │
┌─────▼─────┐ ┌──▼────────┐ ┌──▼────────┐ │
│           │ │           │ │           │ │
│ Multicast │ │  Bonjour  │ │   HTTP    │ │
│  Service  │ │  Service  │ │  Server   │ │
│           │ │  (iOS)    │ │  Service  │ │
│ UDP       │ │ mDNS      │ │ Shelf     │ │
│ 224.0...  │ │ _cpft._tcp│ │ :53317    │ │
│           │ │           │ │           │ │
└───────────┘ └───────────┘ └───────────┘ │
                                           │
                    ┌──────────────────────┘
                    │
          ┌─────────▼──────────┐
          │                    │
          │ IncomingConnection │
          │     Service        │
          │                    │
          │ - Listen on :53317 │
          │ - Accept sockets   │
          │ - Validate handshake│
          │                    │
          └────────────────────┘
```

## Data Flow: Connection & Messaging

```
┌──────────────────────────────────────────────────────────────────┐
│                    Connection Establishment                       │
└──────────────────────────────────────────────────────────────────┘

Device A                                          Device B
────────                                          ────────

1. User taps device
   │
   ├─► ConnectionService.connect()
   │   - Create TCP socket
   │   - Connect to IP:53317 ──────────────────► IncomingConnection
   │                                              - Accept socket
   │                                              - Wait for handshake
   │
   ├─► Send handshake message ───────────────────► Validate handshake
   │   {"type":"handshake", ...}                  - Check format
   │                                              - Notify listeners
   │                                              │
   │                                              ├─► Create response
   │   ◄─────────────────────────────────────────┘   (if needed)
   │
   ├─► Update status: Connected
   │   - Notify UI
   │   - Show toast
   │
   └─► Ready for messages

┌──────────────────────────────────────────────────────────────────┐
│                      Message Exchange                             │
└──────────────────────────────────────────────────────────────────┘

Device A                                          Device B
────────                                          ────────

User types "Hello"
   │
   ├─► ConnectionService.sendText()
   │   - Create DeviceMessage
   │   - JSON encode
   │   - Add newline delimiter
   │   - Socket.write() ──────────────────────────► Socket.listen()
   │                                                 - Receive data
   │                                                 - Buffer data
   │                                                 - Split by '\n'
   │                                                 - Parse JSON
   │                                                 - Create DeviceMessage
   │                                                 │
   │                                                 ├─► Notify listeners
   │                                                 │
   │                                                 └─► UI updates
   │                                                     - Add to messages[]
   │                                                     - setState()
   │                                                     - Auto-scroll
   │
   └─► UI updates
       - Add to messages[]
       - setState()
       - Auto-scroll


User types "How are you?"
                                                    │
                            Socket.listen() ◄───────┼─── Socket.write()
                            - Receive data          │   - JSON encode
                            - Parse message         │   - Add delimiter
                            │                       │
                            ├─► Notify listeners    │
                            │                       └─► UI updates
                            └─► UI updates
                                - Add message
                                - Auto-scroll

┌──────────────────────────────────────────────────────────────────┐
│                         Disconnection                             │
└──────────────────────────────────────────────────────────────────┘

Device A                                          Device B
────────                                          ────────

User taps X
   │
   ├─► ConnectionService.disconnect()
   │   - Send goodbye message ─────────────────────► Receive goodbye
   │     {"type":"goodbye", ...}                     - Show in UI
   │                                                 │
   │   - Cancel subscription                         ├─► Socket closed event
   │   - Close socket ──────────────────────────────►│   - Update status
   │   - Update status: Disconnected                 │   - Show toast
   │   - Notify listeners                            │
   │                                                 └─► UI updates
   └─► Navigate back to discovery
```

## State Management

```
┌────────────────────────────────────────────────────────────┐
│                   Connection States                         │
└────────────────────────────────────────────────────────────┘

         ┌─────────────────┐
    ┌───►│  Disconnected   │◄────┐
    │    └────────┬────────┘     │
    │             │               │
    │             │ connect()     │
    │             ▼               │
    │    ┌─────────────────┐     │
    │    │   Connecting    │     │
    │    └────┬────────┬───┘     │
    │         │        │          │
    │ success │        │ error    │
    │         ▼        ▼          │
    │    ┌─────────┐  ┌────────┐ │
    └────┤Connected│  │ Failed │─┘
         └─────────┘  └────────┘
              │
              │ disconnect()
              │ or error
              └──────────────────┘

Status Indicators:
- Disconnected: No banner
- Connecting: Blue banner with spinner
- Connected: Green toast, then normal UI
- Failed: Red banner with retry button
```

## Message Format

```
┌────────────────────────────────────────────────────────────┐
│                    DeviceMessage JSON                       │
└────────────────────────────────────────────────────────────┘

{
  "type": "text" | "handshake" | "goodbye",
  "content": "Message content here",
  "senderName": "iPhone-DeviceName-1234",
  "timestamp": "2025-11-11T12:34:56.789Z",
  "metadata": {
    // Optional custom fields
    "key": "value"
  }
}

Examples:

Handshake:
{
  "type": "handshake",
  "content": "Hello from iPhone-MyDevice-1234",
  "senderName": "iPhone-MyDevice-1234",
  "timestamp": "2025-11-11T10:00:00.000Z"
}

Text Message:
{
  "type": "text",
  "content": "Hello there!",
  "senderName": "Android-Pixel-5678",
  "timestamp": "2025-11-11T10:01:00.000Z"
}

Goodbye:
{
  "type": "goodbye",
  "content": "Disconnecting",
  "senderName": "iPhone-MyDevice-1234",
  "timestamp": "2025-11-11T10:05:00.000Z"
}
```

## Network Protocol

```
┌────────────────────────────────────────────────────────────┐
│              Network Communication Layers                   │
└────────────────────────────────────────────────────────────┘

Layer 7 (Application)
┌────────────────────────────────────────────┐
│ CPFT Protocol                              │
│ - JSON messages                            │
│ - Newline delimited                        │
│ - Types: text, handshake, goodbye          │
└────────────────────────────────────────────┘
                    │
Layer 4 (Transport)
┌────────────────────────────────────────────┐
│ TCP Socket                                 │
│ - Port: 53317                              │
│ - Reliable, ordered delivery               │
│ - Connection-oriented                      │
└────────────────────────────────────────────┘
                    │
Layer 3 (Network)
┌────────────────────────────────────────────┐
│ IP (IPv4)                                  │
│ - Local network only                       │
│ - 192.168.x.x or 10.x.x.x                 │
└────────────────────────────────────────────┘
                    │
Layer 2 (Data Link)
┌────────────────────────────────────────────┐
│ WiFi (802.11)                              │
│ - Same network required                    │
└────────────────────────────────────────────┘

Discovery uses separate protocol:
┌────────────────────────────────────────────┐
│ UDP Multicast (224.0.0.167:53317)         │
│ - Device announcements                     │
│ - Connectionless                           │
└────────────────────────────────────────────┘
```

## Threading Model

```
┌────────────────────────────────────────────────────────────┐
│                    Dart Isolates & Async                    │
└────────────────────────────────────────────────────────────┘

Main Isolate (UI Thread)
├── Flutter UI rendering
├── User interactions
├── setState() calls
└── Async/await for I/O

Socket I/O (Event Loop)
├── Socket.listen() callbacks
├── Message parsing
├── Buffer management
└── Listener notifications

Timer Events
├── Multicast announcements (5s interval)
├── Connection timeouts (10s)
└── Handshake timeouts (10s)

All socket operations are non-blocking and use Dart's async/await
pattern to prevent UI freezing.
```

This architecture ensures:
✅ Responsive UI (no blocking operations)
✅ Efficient network I/O (event-driven)
✅ Clean separation of concerns
✅ Easy to extend and maintain
