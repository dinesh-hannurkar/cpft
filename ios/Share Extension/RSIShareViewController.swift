//
//  RSIShareViewController.swift
//  receive_sharing_intent
//
//  Created by Kasem Mohamed on 2024-01-25.
//

import UIKit
import Social
import MobileCoreServices
import Photos
import UniformTypeIdentifiers

public let kSchemePrefix = "ShareMedia"
public let kUserDefaultsKey = "ShareKey"
public let kUserDefaultsMessageKey = "ShareMessageKey"
public let kAppGroupIdKey = "AppGroupId"

public class SharedMediaFile: Codable {
    var path: String
    var mimeType: String?
    var thumbnail: String? // video thumbnail
    var duration: Double? // video duration in milliseconds
    var message: String? // post message
    var type: SharedMediaType
    
    
    public init(
        path: String,
        mimeType: String? = nil,
        thumbnail: String? = nil,
        duration: Double? = nil,
        message: String?=nil,
        type: SharedMediaType) {
            self.path = path
            self.mimeType = mimeType
            self.thumbnail = thumbnail
            self.duration = duration
            self.message = message
            self.type = type
        }
}

public enum SharedMediaType: String, Codable, CaseIterable {
    case image
    case video
    case text
//     case audio
    case file
    case url

    public var toUTTypeIdentifier: String {
        if #available(iOS 14.0, *) {
            switch self {
            case .image:
                return UTType.image.identifier
            case .video:
                return UTType.movie.identifier
            case .text:
                return UTType.text.identifier
    //         case .audio:
    //             return UTType.audio.identifier
            case .file:
                return UTType.fileURL.identifier
            case .url:
                return UTType.url.identifier
            }
        }
        switch self {
        case .image:
            return "public.image"
        case .video:
            return "public.movie"
        case .text:
            return "public.text"
//         case .audio:
//             return "public.audio"
        case .file:
            return "public.file-url"
        case .url:
            return "public.url"
        }
    }
}

@available(swift, introduced: 5.0)
open class RSIShareViewController: SLComposeServiceViewController {
    var hostAppBundleIdentifier = ""
    var appGroupId = ""
    var sharedMedia: [SharedMediaFile] = []

    /// Override this method to return false if you don't want to redirect to host app automatically
    /// Default is true
    open func shouldAutoRedirect() -> Bool {
        return true
    }
    
    open override func isContentValid() -> Bool {
        return true
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        // load group and app id from build info
        loadIds()
    }
    
    // Redirect to host app when user click on Post
    open override func didSelectPost() {
        saveAndRedirect(message: contentText)
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("RSIShareViewController: viewDidAppear called")
        
        // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
        if let content = extensionContext!.inputItems[0] as? NSExtensionItem {
            print("RSIShareViewController: Processing NSExtensionItem")
            if let contents = content.attachments {
                print("RSIShareViewController: Found \(contents.count) attachments")
                for (index, attachment) in (contents).enumerated() {
                    print("RSIShareViewController: Processing attachment \(index)")
                    for type in SharedMediaType.allCases {
                        if attachment.hasItemConformingToTypeIdentifier(type.toUTTypeIdentifier) {
                            print("RSIShareViewController: Attachment matches type \(type)")
                            attachment.loadItem(forTypeIdentifier: type.toUTTypeIdentifier) { [weak self] data, error in
                                print("RSIShareViewController: Loaded item for type \(type), error: \(error?.localizedDescription ?? "none")")
                                guard let this = self, error == nil else {
                                    self?.dismissWithError()
                                    return
                                }
                                switch type {
                                case .text:
                                    if let text = data as? String {
                                        this.handleMedia(forLiteral: text,
                                                         type: type,
                                                         index: index,
                                                         content: content)
                                    }
                                case .url:
                                    if let url = data as? URL {
                                        this.handleMedia(forLiteral: url.absoluteString,
                                                         type: type,
                                                         index: index,
                                                         content: content)
                                    }
                                default:
                                    if let url = data as? URL {
                                        this.handleMedia(forFile: url,
                                                         type: type,
                                                         index: index,
                                                         content: content)
                                    }
                                    else if let image = data as? UIImage {
                                        this.handleMedia(forUIImage: image,
                                                         type: type,
                                                         index: index,
                                                         content: content)
                                    }
                                }
                            }
                            break
                        }
                    }
                }
            }
        }
    }
    
    open override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }
    
    private func loadIds() {
        // Use the same app group ID as configured in entitlements
        appGroupId = "group.com.omnity.fylooo.share"
        hostAppBundleIdentifier = "com.omnity.fylooo" // main app bundle ID
    }
    
    
    private func handleMedia(forLiteral item: String, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        print("RSIShareViewController: handleMedia(forLiteral) called with item: \(item), type: \(type)")
        sharedMedia.append(SharedMediaFile(
            path: item,
            mimeType: type == .text ? "text/plain": nil,
            type: type
        ))
        print("RSIShareViewController: Added shared media item, total count: \(sharedMedia.count)")
        if index == (content.attachments?.count ?? 0) - 1 {
            if shouldAutoRedirect() {
                saveAndRedirect()
            }
        }
    }

    private func handleMedia(forUIImage image: UIImage, type: SharedMediaType, index: Int, content: NSExtensionItem){
        print("RSIShareViewController: handleMedia(forUIImage) called with image size: \(image.size)")
        let tempPath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)!.appendingPathComponent("TempImage.png")
        if self.writeTempFile(image, to: tempPath) {
            let newPathDecoded = tempPath.absoluteString.removingPercentEncoding!
            print("RSIShareViewController: Saved image to: \(newPathDecoded)")
            sharedMedia.append(SharedMediaFile(
                path: newPathDecoded,
                mimeType: type == .image ? "image/png": nil,
                type: type
            ))
            print("RSIShareViewController: Added image shared media item, total count: \(sharedMedia.count)")
        } else {
            print("RSIShareViewController: Failed to write temp image file")
        }
        if index == (content.attachments?.count ?? 0) - 1 {
            if shouldAutoRedirect() {
                saveAndRedirect()
            }
        }
    }
    
    private func handleMedia(forFile url: URL, type: SharedMediaType, index: Int, content: NSExtensionItem) {
        print("RSIShareViewController: handleMedia(forFile) called with URL: \(url.absoluteString), type: \(type)")
        let fileName = getFileName(from: url, type: type)
        let newPath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)!.appendingPathComponent(fileName)
        
        if copyFile(at: url, to: newPath) {
            print("RSIShareViewController: Successfully copied file to: \(newPath.absoluteString)")
            // The path should be decoded because Flutter is not expecting url encoded file names
            let newPathDecoded = newPath.absoluteString.removingPercentEncoding!;
            if type == .video {
                // Get video thumbnail and duration
                if let videoInfo = getVideoInfo(from: url) {
                    let thumbnailPathDecoded = videoInfo.thumbnail?.removingPercentEncoding;
                    sharedMedia.append(SharedMediaFile(
                        path: newPathDecoded,
                        mimeType: url.mimeType(),
                        thumbnail: thumbnailPathDecoded,
                        duration: videoInfo.duration,
                        type: type
                    ))
                    print("RSIShareViewController: Added video shared media item with thumbnail, total count: \(sharedMedia.count)")
                }
            } else {
                sharedMedia.append(SharedMediaFile(
                    path: newPathDecoded,
                    mimeType: url.mimeType(),
                    type: type
                ))
                print("RSIShareViewController: Added file shared media item, total count: \(sharedMedia.count)")
            }
        } else {
            print("RSIShareViewController: Failed to copy file")
        }
        
        if index == (content.attachments?.count ?? 0) - 1 {
            if shouldAutoRedirect() {
                saveAndRedirect()
            }
        }
    }
    
    
    // Save shared media and redirect to host app
    private func saveAndRedirect(message: String? = nil) {
        print("RSIShareViewController: Saving \(sharedMedia.count) shared media items")
        print("RSIShareViewController: App group ID: \(appGroupId)")
        
        let userDefaults = UserDefaults(suiteName: appGroupId)
        if userDefaults == nil {
            print("RSIShareViewController: ERROR - UserDefaults suite is nil")
            return
        }
        
        let data = toData(data: sharedMedia)
        print("RSIShareViewController: Serialized data size: \(data.count) bytes")
        
        userDefaults?.set(data, forKey: kUserDefaultsKey)
        userDefaults?.set(message, forKey: kUserDefaultsMessageKey)
        let synced = userDefaults?.synchronize() ?? false
        print("RSIShareViewController: UserDefaults synchronize returned: \(synced)")
        
        print("RSIShareViewController: Redirecting to host app")
        redirectToHostApp()
    }
    
    private func redirectToHostApp() {
        print("RSIShareViewController: redirectToHostApp called")
        // ids may not loaded yet so we need loadIds here too
        loadIds()
        let url = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share")
        print("RSIShareViewController: Opening URL: \(url?.absoluteString ?? "nil")")
        var responder = self as UIResponder?
        
        if #available(iOS 18.0, *) {
            while responder != nil {
                if let application = responder as? UIApplication {
                    print("RSIShareViewController: Found UIApplication, opening URL")
                    application.open(url!, options: [:], completionHandler: nil)
                }
                responder = responder?.next
            }
        } else {
            let selectorOpenURL = sel_registerName("openURL:")
            
            while (responder != nil) {
                if (responder?.responds(to: selectorOpenURL))! {
                    print("RSIShareViewController: Found responder that responds to openURL, calling it")
                    _ = responder?.perform(selectorOpenURL, with: url)
                }
                responder = responder!.next
            }
        }

        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
        print("RSIShareViewController: Completed request")
    }
    
    private func dismissWithError() {
        print("[ERROR] Error loading data!")
        let alert = UIAlertController(title: "Error", message: "Error loading data", preferredStyle: .alert)
        
        let action = UIAlertAction(title: "Error", style: .cancel) { _ in
            self.dismiss(animated: true, completion: nil)
        }
        
        alert.addAction(action)
        present(alert, animated: true, completion: nil)
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private func getFileName(from url: URL, type: SharedMediaType) -> String {
        var name = url.lastPathComponent
        if name.isEmpty {
            switch type {
            case .image:
                name = UUID().uuidString + ".png"
            case .video:
                name = UUID().uuidString + ".mp4"
            case .text:
                name = UUID().uuidString + ".txt"
            default:
                name = UUID().uuidString
            }
        }
        return name
    }

    private func writeTempFile(_ image: UIImage, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            let pngData = image.pngData();
            try pngData?.write(to: dstURL);
            return true;
        } catch (let error){
            print("Cannot write to temp file: \(error)");
            return false;
        }
    }
    
    private func copyFile(at srcURL: URL, to dstURL: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dstURL.path) {
                try FileManager.default.removeItem(at: dstURL)
            }
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
        } catch (let error) {
            print("Cannot copy item at \(srcURL) to \(dstURL): \(error)")
            return false
        }
        return true
    }
    
    private func getVideoInfo(from url: URL) -> (thumbnail: String?, duration: Double)? {
        let asset = AVAsset(url: url)
        let duration = (CMTimeGetSeconds(asset.duration) * 1000).rounded()
        let thumbnailPath = getThumbnailPath(for: url)
        
        if FileManager.default.fileExists(atPath: thumbnailPath.path) {
            return (thumbnail: thumbnailPath.absoluteString, duration: duration)
        }
        
        var saved = false
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        //        let scale = UIScreen.main.scale
        assetImgGenerate.maximumSize =  CGSize(width: 360, height: 360)
        do {
            let img = try assetImgGenerate.copyCGImage(at: CMTimeMakeWithSeconds(600, preferredTimescale: 1), actualTime: nil)
            try UIImage(cgImage: img).pngData()?.write(to: thumbnailPath)
            saved = true
        } catch {
            saved = false
        }
        
        return saved ? (thumbnail: thumbnailPath.absoluteString, duration: duration): nil
    }
    
    private func getThumbnailPath(for url: URL) -> URL {
        let fileName = Data(url.lastPathComponent.utf8).base64EncodedString().replacingOccurrences(of: "==", with: "")
        let path = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)!
            .appendingPathComponent("\(fileName).jpg")
        return path
    }
    
    private func toData(data: [SharedMediaFile]) -> Data {
        let encodedData = try? JSONEncoder().encode(data)
        return encodedData!
    }
}

extension URL {
    public func mimeType() -> String {
        if #available(iOS 14.0, *) {
            if let mimeType = UTType(filenameExtension: self.pathExtension)?.preferredMIMEType {
                return mimeType
            }
        } else {
            if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, self.pathExtension as NSString, nil)?.takeRetainedValue() {
                if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                    return mimetype as String
                }
            }
        }
        
        return "application/octet-stream"
    }
}
