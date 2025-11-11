import 'dart:convert';

/// Data Transfer Object for UDP multicast announcements
class MulticastDto {
  final String alias;
  final String fingerprint;
  final int port;
  final String deviceModel;
  final bool announce; // true = announcement, false = response

  const MulticastDto({
    required this.alias,
    required this.fingerprint,
    required this.port,
    required this.deviceModel,
    required this.announce,
  });

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'fingerprint': fingerprint,
        'port': port,
        'deviceModel': deviceModel,
        'announce': announce,
      };

  factory MulticastDto.fromJson(Map<String, dynamic> json) => MulticastDto(
        alias: json['alias'] as String,
        fingerprint: json['fingerprint'] as String,
        port: json['port'] as int,
        deviceModel: json['deviceModel'] as String? ?? 'Unknown',
        announce: json['announce'] as bool? ?? false,
      );

  String toJsonString() => jsonEncode(toJson());
  
  factory MulticastDto.fromJsonString(String jsonString) =>
      MulticastDto.fromJson(jsonDecode(jsonString));
}

/// Data Transfer Object for HTTP registration
class RegisterDto {
  final String alias;
  final String fingerprint;
  final int port;
  final String deviceModel;

  const RegisterDto({
    required this.alias,
    required this.fingerprint,
    required this.port,
    required this.deviceModel,
  });

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'fingerprint': fingerprint,
        'port': port,
        'deviceModel': deviceModel,
      };

  factory RegisterDto.fromJson(Map<String, dynamic> json) => RegisterDto(
        alias: json['alias'] as String,
        fingerprint: json['fingerprint'] as String,
        port: json['port'] as int,
        deviceModel: json['deviceModel'] as String? ?? 'Unknown',
      );

  String toJsonString() => jsonEncode(toJson());
  
  factory RegisterDto.fromJsonString(String jsonString) =>
      RegisterDto.fromJson(jsonDecode(jsonString));
}

/// Data Transfer Object for HTTP info response
class InfoDto {
  final String alias;
  final String fingerprint;
  final int port;
  final String deviceModel;

  const InfoDto({
    required this.alias,
    required this.fingerprint,
    required this.port,
    required this.deviceModel,
  });

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'fingerprint': fingerprint,
        'port': port,
        'deviceModel': deviceModel,
      };

  factory InfoDto.fromJson(Map<String, dynamic> json) => InfoDto(
        alias: json['alias'] as String,
        fingerprint: json['fingerprint'] as String,
        port: json['port'] as int,
        deviceModel: json['deviceModel'] as String? ?? 'Unknown',
      );

  String toJsonString() => jsonEncode(toJson());
  
  factory InfoDto.fromJsonString(String jsonString) =>
      InfoDto.fromJson(jsonDecode(jsonString));
}
