import Flutter
import UIKit
import Foundation
import NetworkExtension

enum SharedMediaType: String {
    case image
    case video
    case text
    case file
    case url
    
    static func fromString(_ string: String) -> SharedMediaType? {
        return SharedMediaType(rawValue: string)
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var netServiceBrowser: NetServiceBrowser?
  private var currentResolveResult: FlutterResult?
  private var messengerRef: FlutterBinaryMessenger?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NSLog("[Fylooo] App didFinishLaunchingWithOptions")
    // Diagnostic: verify App Group access from main app
    let groupId = "group.com.omnity.fylooo.share"
    let defaults = UserDefaults(suiteName: groupId)
    let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    NSLog("[Fylooo][Diag] containerURL nil? \(container == nil) path=\(container?.path ?? "<nil>")")
    defaults?.set("ok", forKey: "diag_ping")
    let val = defaults?.string(forKey: "diag_ping") ?? "<nil>"
    NSLog("[Fylooo][Diag] defaults write/read diag_ping=\(val)")
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up mDNS hostname resolution channel (avoid relying on rootViewController)
    let messenger: FlutterBinaryMessenger = {
      if let vc = self.window?.rootViewController as? FlutterViewController {
        return vc.binaryMessenger
      }
      if let reg = self.registrar(forPlugin: "fylooo-messenger") {
        return reg.messenger()
      }
      // Fallback (may be nil in rare cases)
      return (self.window?.rootViewController as! FlutterViewController).binaryMessenger
    }()
    // Keep a reference for later use (deep link notifications)
    self.messengerRef = messenger

    let mdnsChannel = FlutterMethodChannel(name: "com.omnity.fylooo/mdns",
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
    let wifiChannel = FlutterMethodChannel(name: "com.omnity.fylooo/wifi",
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
    let shareChannel = FlutterMethodChannel(name: "com.omnity.fylooo/share",
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

  // Handle fylooo:// deep links (including from Share Extension)
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    NSLog("[Fylooo] application open url: \(url.absoluteString)")
    // Handle both custom scheme and ShareMedia-<bundle id>
    guard let scheme = url.scheme?.lowercased() else { return false }
    let isFylooo = (scheme == "fylooo")
    let isShareMedia = scheme.hasPrefix("sharemedia-")
    guard isFylooo || isShareMedia else {
      NSLog("[Fylooo] Unknown scheme: \(scheme)")
      return false
    }

    // If this is a ShareMedia URL, try to read shared data directly
    if isShareMedia {
      readAndSendSharedData()
    }

    // Bring app to foreground if needed
    // Flutter will already be running; shared content will be picked up by polling.
    // Optionally, post a notification to trigger immediate check.
    NotificationCenter.default.post(name: Notification.Name("fyloooDeepLinkOpened"), object: nil)
    NSLog("[Fylooo] fylooo:// handled and notification posted")

    // Immediately notify Flutter to fetch shared content now
    if let messenger = self.messengerRef {
      let shareEvents = FlutterMethodChannel(name: "com.omnity.fylooo/share-events", binaryMessenger: messenger)
      shareEvents.invokeMethod("shareOpened", arguments: nil)
      NSLog("[Fylooo] invoked share-events: shareOpened")
    } else {
      NSLog("[Fylooo] messengerRef nil; cannot invoke share-events")
    }
    return true
  }
  
  private func readAndSendSharedData() {
    // Read shared data from app group UserDefaults
    // Use the same app group ID as configured in entitlements
    let appGroupId = "group.com.omnity.fylooo.share"
    let userDefaults = UserDefaults(suiteName: appGroupId)
    
    NSLog("[Fylooo] Reading shared data from app group: \(appGroupId)")
    
    // Debug: check if UserDefaults suite exists
    if userDefaults == nil {
      NSLog("[Fylooo] ERROR: UserDefaults suite is nil for app group \(appGroupId)")
      return
    }
    
    // Debug: list all keys in UserDefaults
    if let dict = userDefaults?.dictionaryRepresentation() {
      NSLog("[Fylooo] UserDefaults contents: \(dict.keys)")
    }
    
    let jsonData = userDefaults?.data(forKey: "ShareKey")
    let message = userDefaults?.string(forKey: "ShareMessageKey")
    
    NSLog("[Fylooo] ShareKey data exists: \(jsonData != nil), message exists: \(message != nil)")
    
    guard let jsonData = jsonData else {
      NSLog("[Fylooo] No shared data found in UserDefaults")
      return
    }
    
    // Parse the JSON data (simplified version of what receive_sharing_intent does)
    do {
      if let jsonArray = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] {
        var sharedFiles: [[String: Any]] = []
        
        for item in jsonArray {
          if let path = item["path"] as? String,
             let typeString = item["type"] as? String,
             let type = SharedMediaType.fromString(typeString) {
            
            var processedItem: [String: Any] = [
              "path": path,
              "type": typeString
            ]
            
            if let mimeType = item["mimeType"] as? String {
              processedItem["mimeType"] = mimeType
            }
            
            if let thumbnail = item["thumbnail"] as? String {
              processedItem["thumbnail"] = thumbnail
            }
            
            if let duration = item["duration"] as? Double {
              processedItem["duration"] = duration
            }
            
            if let itemMessage = item["message"] as? String {
              processedItem["message"] = itemMessage
            } else if let message = message, !message.isEmpty {
              processedItem["message"] = message
            }
            
            // For text and URL types, use path directly
            // For file types, try to resolve the path
            if type == .text || type == .url {
              // Use path as-is
            } else {
              // Try to get the actual file path
              if let resolvedPath = getAbsolutePath(for: path) {
                processedItem["path"] = resolvedPath
              }
            }
            
            sharedFiles.append(processedItem)
          }
        }
        
        // Send the data to Flutter
        if let messenger = self.messengerRef {
          let shareChannel = FlutterMethodChannel(name: "com.omnity.fylooo/share-events", binaryMessenger: messenger)
          NSLog("[Fylooo] About to send sharedDataReceived with \(sharedFiles.count) files")
          for (index, file) in sharedFiles.enumerated() {
            NSLog("[Fylooo] File \(index): \(file)")
          }
          shareChannel.invokeMethod("sharedDataReceived", arguments: sharedFiles)
          NSLog("[Fylooo] Sent \(sharedFiles.count) shared files to Flutter")
        }
      }
    } catch {
      NSLog("[Fylooo] Error parsing shared data: \(error)")
    }
  }
  
  private func getAbsolutePath(for identifier: String?) -> String? {
    guard let identifier = identifier else { return nil }
    
    if identifier.hasPrefix("file://") {
      return identifier.replacingOccurrences(of: "file://", with: "")
    }
    
    // For PHAsset identifiers, we can't easily resolve them here
    // The receive_sharing_intent plugin handles this
    return identifier
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
    NSLog("[Fylooo] getSharedContent invoked")
    let sharedDefaults = UserDefaults(suiteName: "group.com.omnity.fylooo.share")

    var type: String?
    var timestamp: Date?
    var content: String?
    var fileURLString: String?

    // First try to get data from the metadata file (primary method for share extension)
    if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.omnity.fylooo.share") {
      let metadataURL = containerURL.appendingPathComponent("shared_metadata.plist")

      if let data = try? Data(contentsOf: metadataURL),
         let metadata = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {

        type = metadata["type"] as? String
        timestamp = metadata["timestamp"] as? Date
        if let text = metadata["text"] as? String {
          if type == "text" || type == "url" {
            content = text
          } else {
            fileURLString = text
          }
        }

        // Clean up the metadata file
        try? FileManager.default.removeItem(at: metadataURL)
        NSLog("[Fylooo] Loaded data from metadata file (primary source)")
      }
    }

    // If metadata file doesn't have data, try UserDefaults as fallback
    if type == nil || timestamp == nil {
      NSLog("[Fylooo] Metadata file empty, trying UserDefaults as fallback")
      type = sharedDefaults?.string(forKey: "sharedType")
      timestamp = sharedDefaults?.object(forKey: "sharedTimestamp") as? Date
      content = sharedDefaults?.string(forKey: "sharedText")
      fileURLString = sharedDefaults?.string(forKey: "sharedFileURL")
    }

    guard let finalType = type, let finalTimestamp = timestamp else {
      NSLog("[Fylooo] No shared data found in UserDefaults or metadata file")
      result(nil)
      return
    }

    var sharedData: [String: Any] = [
      "type": finalType,
      "timestamp": Int(finalTimestamp.timeIntervalSince1970)
    ]

    if finalType == "text" || finalType == "url" {
      if let finalContent = content {
        sharedData["content"] = finalContent
      } else {
        NSLog("[Fylooo] No content found for type \(finalType)")
      }
    } else if finalType == "image" || finalType == "video" || finalType == "file" {
      if let finalFileURLString = fileURLString, let fileURL = URL(string: finalFileURLString) {

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
          NSLog("[Fylooo] Copied shared file to: \(destinationURL.path)")
        } catch {
          print("Error copying shared file: \(error)")
          result(nil)
          return
        }
      } else {
        NSLog("[Fylooo] No fileURL found for type \(finalType)")
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
