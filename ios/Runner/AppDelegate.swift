import Flutter
import UIKit
import Foundation
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var netServiceBrowser: NetServiceBrowser?
  private var currentResolveResult: FlutterResult?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up mDNS hostname resolution channel
    let controller = window?.rootViewController as! FlutterViewController
    let mdnsChannel = FlutterMethodChannel(name: "com.example.cpft/mdns",
                                           binaryMessenger: controller.binaryMessenger)
    
    mdnsChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "resolveHostname" {
        guard let args = call.arguments as? [String: Any],
              let serviceName = args["serviceName"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "serviceName is required", details: nil))
          return
        }
        
        let serviceType = args["serviceType"] as? String ?? "_http._tcp"
        self?.resolveServiceHostname(serviceName: serviceName, serviceType: serviceType, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // WiFi connect channel (iOS: show system join dialog)
    let wifiChannel = FlutterMethodChannel(name: "com.example.cpft/wifi",
                                           binaryMessenger: controller.binaryMessenger)

    wifiChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "connectToWifi":
        guard let args = call.arguments as? [String: Any],
              let ssid = args["ssid"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "ssid is required", details: nil))
          return
        }

        let password = args["password"] as? String
        let security = (args["security"] as? String)?.uppercased() ?? "WPA2"

        // Build NEHotspotConfiguration
        let configuration: NEHotspotConfiguration
        if security == "NOPASS" || security == "OPEN" || password?.isEmpty == true {
          configuration = NEHotspotConfiguration(ssid: ssid)
        } else if security == "WEP" {
          configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password ?? "", isWEP: true)
        } else {
          configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password ?? "", isWEP: false)
        }

        // Join once = false so the system may remember the network depending on policy
        configuration.joinOnce = false

        NEHotspotConfigurationManager.shared.apply(configuration) { error in
          if let error = error as NSError? {
            if error.domain == NEHotspotConfigurationErrorDomain,
               error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
              result(["status": "already_connected", "ssid": ssid])
            } else {
              result(FlutterError(code: "WIFI_CONNECT_ERROR", message: error.localizedDescription, details: nil))
            }
          } else {
            result(["status": "connected", "ssid": ssid])
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func resolveServiceHostname(serviceName: String, serviceType: String, result: @escaping FlutterResult) {
    currentResolveResult = result
    
    // Create a NetService for resolution
    let netService = NetService(domain: "local.", type: "\(serviceType).", name: serviceName)
    netService.delegate = self
    netService.resolve(withTimeout: 5.0)
  }
}

// MARK: - NetServiceDelegate
extension AppDelegate: NetServiceDelegate {
  func netServiceDidResolveAddress(_ sender: NetService) {
    // Get the hostname from the resolved service
    let hostname = sender.hostName ?? ""
    
    var resultMap: [String: Any] = [
      "hostname": hostname,
      "host": hostname,
      "port": sender.port,
      "serviceName": sender.name
    ]
    
    // Try to get IP address from addresses
    if let addresses = sender.addresses, !addresses.isEmpty {
      for address in addresses {
        let data = address as Data
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        
        data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
          guard let sockaddr = pointer.bindMemory(to: sockaddr.self).baseAddress else { return }
          
          guard getnameinfo(sockaddr, socklen_t(data.count), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return
          }
          
          let ipAddress = String(cString: hostname)
          resultMap["hostAddress"] = ipAddress
        }
        break
      }
    }
    
    currentResolveResult?(resultMap)
    currentResolveResult = nil
    sender.stop()
  }
  
  func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
    let errorCode = errorDict[NetService.errorCode] ?? -1
    currentResolveResult?(FlutterError(code: "RESOLVE_FAILED", 
                                       message: "Failed to resolve service: errorCode=\(errorCode)", 
                                       details: nil))
    currentResolveResult = nil
    sender.stop()
  }
}
