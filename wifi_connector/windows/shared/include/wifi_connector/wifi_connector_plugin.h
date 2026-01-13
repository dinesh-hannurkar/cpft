#ifndef FLUTTER_PLUGIN_WIFI_CONNECTOR_PLUGIN_H_
#define FLUTTER_PLUGIN_WIFI_CONNECTOR_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace wifi_connector {

class WifiConnectorPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  WifiConnectorPlugin();

  virtual ~WifiConnectorPlugin();

  // Disallow copy and assign.
  WifiConnectorPlugin(const WifiConnectorPlugin&) = delete;
  WifiConnectorPlugin& operator=(const WifiConnectorPlugin&) = delete;

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace wifi_connector

#endif  // FLUTTER_PLUGIN_WIFI_CONNECTOR_PLUGIN_H_
