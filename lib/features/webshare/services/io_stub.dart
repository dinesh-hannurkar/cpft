/// Stub implementations for dart:io types when running on web
/// This file is used when dart:io is not available (web platform)

class WebSocket {
  static Future<WebSocket> connect(String url) {
    throw UnsupportedError('WebSocket is not supported on web');
  }
  
  void add(String data) {
    throw UnsupportedError('WebSocket is not supported on web');
  }
  
  Stream<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    throw UnsupportedError('WebSocket is not supported on web');
  }
  
  void close() {}
}

class HttpServer {
  static Future<HttpServer> bind(dynamic address, int port) {
    throw UnsupportedError('HttpServer is not supported on web');
  }
  
  Stream<HttpRequest> listen(
    void Function(HttpRequest)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    throw UnsupportedError('HttpServer is not supported on web');
  }
  
  Future<void> close({bool force = false}) {
    throw UnsupportedError('HttpServer is not supported on web');
  }
}

class HttpRequest {
  Uri get uri => Uri();
  HttpResponse get response => HttpResponse();
}

class HttpResponse {
  int statusCode = 200;
  
  Future<void> close() async {}
}

class WebSocketTransformer {
  static bool isUpgradeRequest(HttpRequest request) {
    throw UnsupportedError('WebSocketTransformer is not supported on web');
  }
  
  static Future<WebSocket> upgrade(HttpRequest request) {
    throw UnsupportedError('WebSocketTransformer is not supported on web');
  }
}

class HttpStatus {
  static const int ok = 200;
  static const int notFound = 404;
  static const int internalServerError = 500;
}

// Stub for RandomAccessFile (not available on web)
class RandomAccessFile {
  Future<void> writeFrom(List<int> buffer, [int start = 0, int? end]) async {
    throw UnsupportedError('RandomAccessFile is not supported on web');
  }
  
  Future<void> flush() async {
    throw UnsupportedError('RandomAccessFile is not supported on web');
  }
  
  Future<void> close() async {}
}

// Stub for FileMode (not available on web)
class FileMode {
  static const FileMode write = FileMode._();
  const FileMode._();
}
class NetworkInterface {
  static Future<List<NetworkInterface>> list({InternetAddressType? type, bool includeLinkLocal = false}) {
    return Future.value([]);
  }
  
  String get name => '';
  List<InternetAddress> get addresses => [];
}

class InternetAddress {
  static final InternetAddress anyIPv4 = InternetAddress._('0.0.0.0');
  
  final String _address;
  
  InternetAddress._(this._address);
  
  String get address => _address;
  bool get isLoopback => false;
}

enum InternetAddressType {
  IPv4,
  IPv6,
  any,
}

class SocketException implements Exception {
  final String message;
  final OSError? osError;
  
  SocketException(this.message, {this.osError});
  
  @override
  String toString() => 'SocketException: $message';
}

class OSError {
  final int errorCode;
  final String message;
  
  OSError(this.errorCode, this.message);
}

class TimeoutException implements Exception {
  final String message;
  
  TimeoutException(this.message);
  
  @override
  String toString() => 'TimeoutException: $message';
}

class Platform {
  static String get operatingSystem => 'web';
  static String get operatingSystemVersion => 'browser';
  static bool get isAndroid => false;
  static bool get isIOS => false;
}

class File {
  final String path;
  
  File(this.path);
  
  // Synchronous variants used in codepaths that are not executed on web
  bool existsSync() {
    throw UnsupportedError('File.existsSync() is not supported on web');
  }
  
  int lengthSync() {
    throw UnsupportedError('File.lengthSync() is not supported on web');
  }

  Future<bool> exists() {
    throw UnsupportedError('File.exists() is not supported on web');
  }
  
  Future<int> length() {
    throw UnsupportedError('File.length() is not supported on web');
  }
  
  Future<List<int>> readAsBytes() {
    throw UnsupportedError('File.readAsBytes() is not supported on web');
  }
  
  Future<File> writeAsBytes(List<int> bytes) {
    throw UnsupportedError('File.writeAsBytes() is not supported on web');
  }
}
