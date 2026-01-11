#include "include/wifi_connector/wifi_connector_plugin.h"
#include "include/wifi_connector/wifi_service.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

namespace wifi_connector {

// static
void WifiConnectorPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "wifi_connector",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<WifiConnectorPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

WifiConnectorPlugin::WifiConnectorPlugin() {}

WifiConnectorPlugin::~WifiConnectorPlugin() {}

void WifiConnectorPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("scan") == 0) {
    try {
      WifiService wifi_service;
      auto networks = wifi_service.ScanNetworks();
      flutter::EncodableList network_list;
      for (const auto& ssid : networks) {
          network_list.push_back(flutter::EncodableValue(std::string(ssid.begin(), ssid.end())));
      }
      result->Success(network_list);
    } catch (const std::exception& e) {
      result->Error("SCAN_ERROR", e.what());
    }
  } else if (method_call.method_name().compare("connect") == 0) {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      auto ssid_it = args->find(flutter::EncodableValue("ssid"));
      auto password_it = args->find(flutter::EncodableValue("password"));
      if (ssid_it != args->end() && password_it != args->end()) {
        std::string ssid_str = std::get<std::string>(ssid_it->second);
        std::string password_str = std::get<std::string>(password_it->second);
        std::wstring ssid(ssid_str.begin(), ssid_str.end());
        std::wstring password(password_str.begin(), password_str.end());
        try {
          WifiService wifi_service;
          bool success = wifi_service.Connect(ssid, password);
          result->Success(flutter::EncodableValue(success));
        } catch (const std::exception& e) {
          result->Error("CONNECT_ERROR", e.what());
        }
      } else {
        result->Error("INVALID_ARGUMENTS", "SSID or password missing");
      }
    } else {
      result->Error("INVALID_ARGUMENTS", "Arguments must be a map");
    }
  } else {
    result->NotImplemented();
  }
}

}  // namespace wifi_connector
