import Cocoa
import FlutterMacOS
import CoreWLAN

public class WifiConnectorPlugin: NSObject, FlutterPlugin {
  var wifiService = WifiService()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "wifi_connector", binaryMessenger: registrar.messenger)
    let instance = WifiConnectorPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "scan":
      let networks = wifiService.scanNetworks()
      result(networks)
    case "connect":
      guard let args = call.arguments as? [String: Any],
            let ssid = args["ssid"] as? String,
            let password = args["password"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "SSID or password missing", details: nil))
        return
      }
      let success = wifiService.connect(withSSID: ssid, password: password)
      result(success)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
