import Flutter
import UIKit
import Foundation
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var netServiceBrowser: NetServiceBrowser?
  private var currentResolveResult: FlutterResult?
  private var messengerRef: FlutterBinaryMessenger?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NSLog("[CPFT] App didFinishLaunchingWithOptions")
    // Diagnostic: verify App Group access from main app
    let groupId = "group.com.example.cpft.share"
    let defaults = UserDefaults(suiteName: groupId)
    let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    NSLog("[CPFT][Diag] containerURL nil? \(container == nil) path=\(container?.path ?? "<nil>")")
    defaults?.set("ok", forKey: "diag_ping")
    let val = defaults?.string(forKey: "diag_ping") ?? "<nil>"
    NSLog("[CPFT][Diag] defaults write/read diag_ping=\(val)")
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up mDNS hostname resolution channel (avoid relying on rootViewController)
    let messenger: FlutterBinaryMessenger = {
      if let vc = self.window?.rootViewController as? FlutterViewController {
        return vc.binaryMessenger
      }
      if let reg = self.registrar(forPlugin: "cpft-messenger") {
        return reg.messenger()
      }
      // Fallback (may be nil in rare cases)
      return (self.window?.rootViewController as! FlutterViewController).binaryMessenger
    }()
    // Keep a reference for later use (deep link notifications)
    self.messengerRef = messenger

    let mdnsChannel = FlutterMethodChannel(name: "com.example.cpft/mdns",
                                           binaryMessenger: messenger)
    
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
                         binaryMessenger: messenger)

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

      case "openWifiSettings":
        // Best-effort: try to open system Settings close to Hotspot.
        // Apple does not provide public APIs for deep-linking into Settings.
        // The following URLs are undocumented and may stop working on future iOS versions
        // and can be grounds for App Store rejection. We still attempt them as a convenience
        // with safe fallbacks to the Settings app and app-specific settings.
        NSLog("📱 openWifiSettings called")

        let candidates: [String] = [
          // Newer/undocumented variants
          "App-Prefs:root=INTERNET_TETHERING",
          "App-Prefs:root=General&path=INTERNET_TETHERING",
          "App-Prefs:root=MOBILE_DATA_SETTINGS_ID",
          "App-Prefs:root=WIFI",
          "App-Prefs:",
          // Legacy variants (may work on some devices)
          "Prefs:root=INTERNET_TETHERING",
          "Prefs:root=WIFI",
          "Prefs:root=General"
        ]

        var opened = false
        for raw in candidates {
          if let url = URL(string: raw), UIApplication.shared.canOpenURL(url) {
            NSLog("📱 Attempting to open: \(raw)")
            UIApplication.shared.open(url, options: [:]) { success in
              NSLog("📱 Open result for \(raw): \(success)")
              result(success)
            }
            opened = true
            break
          } else {
            NSLog("⚠️ Cannot open: \(raw)")
          }
        }

        if !opened {
          // Fallback 1: Try to open Settings root (may or may not work)
          if let rootUrl = URL(string: "App-Prefs:"), UIApplication.shared.canOpenURL(rootUrl) {
            NSLog("📱 Fallback to Settings root")
            UIApplication.shared.open(rootUrl, options: [:]) { success in
              NSLog("📱 Open result for Settings root: \(success)")
              result(success)
            }
          } else if let legacyRoot = URL(string: "Prefs:"), UIApplication.shared.canOpenURL(legacyRoot) {
            NSLog("📱 Fallback to legacy Settings root")
            UIApplication.shared.open(legacyRoot, options: [:]) { success in
              NSLog("📱 Open result for legacy Settings root: \(success)")
              result(success)
            }
          } else if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            // Fallback 2: Open app-specific settings (always allowed)
            NSLog("📱 Fallback to app settings")
            UIApplication.shared.open(appSettings, options: [:]) { success in
              NSLog("📱 Open result for app settings: \(success)")
              result(success)
            }
          } else {
            NSLog("❌ No valid Settings URL could be constructed")
            result(false)
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Register custom share channel handler
    let shareChannel = FlutterMethodChannel(name: "com.example.cpft/share",
                         binaryMessenger: messenger)
    shareChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "getSharedContent" {
        self.getSharedContent(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle cpft:// deep links (including from Share Extension)
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    NSLog("[CPFT] application open url: \(url.absoluteString)")
    // Handle both custom scheme and ShareMedia-<bundle id>
    guard let scheme = url.scheme?.lowercased() else { return false }
    let isCpft = (scheme == "cpft")
    let isShareMedia = scheme.hasPrefix("sharemedia-")
    guard isCpft || isShareMedia else {
      NSLog("[CPFT] Unknown scheme: \(scheme)")
      return false
    }

    // Bring app to foreground if needed
    // Flutter will already be running; shared content will be picked up by polling.
    // Optionally, post a notification to trigger immediate check.
    NotificationCenter.default.post(name: Notification.Name("CPFTDeepLinkOpened"), object: nil)
    NSLog("[CPFT] cpft:// handled and notification posted")

    // Immediately notify Flutter to fetch shared content now
    if let messenger = self.messengerRef {
      let shareEvents = FlutterMethodChannel(name: "com.example.cpft/share-events", binaryMessenger: messenger)
      shareEvents.invokeMethod("shareOpened", arguments: nil)
      NSLog("[CPFT] invoked share-events: shareOpened")
    } else {
      NSLog("[CPFT] messengerRef nil; cannot invoke share-events")
    }
    return true
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

  private func getSharedContent(result: @escaping FlutterResult) {
    NSLog("[CPFT] getSharedContent invoked")
    let sharedDefaults = UserDefaults(suiteName: "group.com.example.cpft.share")

    guard let type = sharedDefaults?.string(forKey: "sharedType"),
          let timestamp = sharedDefaults?.object(forKey: "sharedTimestamp") as? Date else {
      NSLog("[CPFT] No sharedType or sharedTimestamp found")
      result(nil)
      return
    }

    var sharedData: [String: Any] = [
      "type": type,
      "timestamp": Int(timestamp.timeIntervalSince1970)
    ]

    if type == "text" || type == "url" {
      if let content = sharedDefaults?.string(forKey: "sharedText") {
        sharedData["content"] = content
      } else {
        NSLog("[CPFT] No sharedText found for type \(type)")
      }
    } else if type == "image" || type == "video" || type == "file" {
      if let fileURLString = sharedDefaults?.string(forKey: "sharedFileURL"),
         let fileURL = URL(string: fileURLString) {

        // Copy the file to the app's documents directory
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        let fileName = fileURL.lastPathComponent
        let destinationURL = documentsDirectory.appendingPathComponent("shared_files").appendingPathComponent(fileName)

        do {
          // Create shared_files directory if it doesn't exist
          let sharedDir = destinationURL.deletingLastPathComponent()
          try fileManager.createDirectory(at: sharedDir, withIntermediateDirectories: true, attributes: nil)

          // Copy the file
          try fileManager.copyItem(at: fileURL, to: destinationURL)
          sharedData["filePath"] = destinationURL.path
          NSLog("[CPFT] Copied shared file to: \(destinationURL.path)")
        } catch {
          print("Error copying shared file: \(error)")
          result(nil)
          return
        }
      } else {
        NSLog("[CPFT] No sharedFileURL found for type \(type)")
      }
    }

    // Clear the shared data after processing
    sharedDefaults?.removeObject(forKey: "sharedText")
    sharedDefaults?.removeObject(forKey: "sharedFileURL")
    sharedDefaults?.removeObject(forKey: "sharedType")
    sharedDefaults?.removeObject(forKey: "sharedTimestamp")
    sharedDefaults?.synchronize()

    result(sharedData)
  }
}
