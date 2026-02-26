/// Connection state enum
enum ConnectionStatus { disconnected, connecting, connected, failed }

/// WiFi Direct connection status
enum WifiDirectStatus { disconnected, connecting, connected, failed }

/// Connection information model
class ConnectionInfo {
  final String deviceName;
  final String? deviceId; // Added for unique identification
  final String ipAddress;
  final int port;
  final int? dataPort;
  final ConnectionStatus status;
  final DateTime? connectedAt;
  final String? error;

  ConnectionInfo({
    required this.deviceName,
    this.deviceId,
    required this.ipAddress,
    required this.port,
    this.dataPort,
    required this.status,
    this.connectedAt,
    this.error,
  });

  ConnectionInfo copyWith({
    String? deviceName,
    String? deviceId,
    String? ipAddress,
    int? port,
    int? dataPort,
    ConnectionStatus? status,
    DateTime? connectedAt,
    String? error,
  }) {
    return ConnectionInfo(
      deviceName: deviceName ?? this.deviceName,
      deviceId: deviceId ?? this.deviceId,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      dataPort: dataPort ?? this.dataPort,
      status: status ?? this.status,
      connectedAt: connectedAt ?? this.connectedAt,
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    return 'ConnectionInfo(device: $deviceName, ip: $ipAddress, status: $status)';
  }
}

/// Message model for communication
class DeviceMessage {
  final String type;
  final String content;
  final String senderName;
  final String? deviceId; // Added for unique identification
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  DeviceMessage({
    required this.type,
    required this.content,
    required this.senderName,
    this.deviceId,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'content': content,
      'senderName': senderName,
      'deviceId': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory DeviceMessage.fromJson(Map<String, dynamic> json) {
    return DeviceMessage(
      type: json['type'] as String,
      content: json['content'] as String,
      senderName: json['senderName'] as String,
      deviceId: json['deviceId'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'DeviceMessage(type: $type, from: $senderName, at: $timestamp)';
  }
}
