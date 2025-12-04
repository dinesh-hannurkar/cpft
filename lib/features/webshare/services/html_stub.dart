/// Stub implementations for dart:html types when not running on web
/// This file is used when dart:html is not available (mobile platforms)

class Location {
  String get href => '';
}

class Window {
  Location get location => Location();
}

final Window window = Window();