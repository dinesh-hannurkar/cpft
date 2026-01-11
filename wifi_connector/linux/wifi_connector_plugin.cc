#include "wifi_connector_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>
#include <string>
#include <vector>
#include <iostream>
#include <memory>
#include <cstdio>
#include <stdexcept>
#include <array>

#define WIFI_CONNECTOR_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), wifi_connector_plugin_get_type(), \
                              WifiConnectorPlugin))

struct _WifiConnectorPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(WifiConnectorPlugin, wifi_connector_plugin, g_object_get_type())

static std::string exec(const char* cmd) {
    std::array<char, 128> buffer;
    std::string result;
    std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(cmd, "r"), pclose);
    if (!pipe) {
        throw std::runtime_error("popen() failed!");
    }
    while (fgets(buffer.data(), buffer.size(), pipe.get()) != nullptr) {
        result += buffer.data();
    }
    return result;
}

static FlValue* scan_networks() {
    try {
        std::string result = exec("nmcli -t -f SSID dev wifi");
        auto response = fl_value_new_list();
        std::stringstream ss(result);
        std::string line;
        while (std::getline(ss, line, '\n')) {
            fl_value_append_string(response, line.c_str());
        }
        return response;
    } catch (const std::exception& e) {
        return nullptr;
    }
}

static FlValue* connect_to_network(const gchar* ssid, const gchar* password) {
    try {
        std::string cmd = "nmcli dev wifi connect \"" + std::string(ssid) + "\" password \"" + std::string(password) + "\"";
        std::string result = exec(cmd.c_str());
        if (result.find("Error") != std::string::npos) {
            return fl_value_new_bool(false);
        }
        return fl_value_new_bool(true);
    } catch (const std::exception& e) {
        return fl_value_new_bool(false);
    }
}

static void wifi_connector_plugin_handle_method_call(
    WifiConnectorPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "scan") == 0) {
    auto networks = scan_networks();
    if (networks) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(networks));
    } else {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("SCAN_ERROR", "Failed to scan networks", nullptr));
    }
  } else if (strcmp(method, "connect") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* ssid = fl_value_get_string(fl_value_lookup_string(args, "ssid"));
    const gchar* password = fl_value_get_string(fl_value_lookup_string(args, "password"));
    auto result = connect_to_network(ssid, password);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void wifi_connector_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(wifi_connector_plugin_parent_class)->dispose(object);
}

static void wifi_connector_plugin_class_init(WifiConnectorPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = wifi_connector_plugin_dispose;
}

static void wifi_connector_plugin_init(WifiConnectorPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  WifiConnectorPlugin* plugin = WIFI_CONNECTOR_PLUGIN(user_data);
  wifi_connector_plugin_handle_method_call(plugin, method_call);
}

void wifi_connector_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  WifiConnectorPlugin* plugin = WIFI_CONNECTOR_PLUGIN(
      g_object_new(wifi_connector_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "wifi_connector", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
