//
//  ShareViewController.swift
//  Share Extension
//
//  Uses receive_sharing_intent's RSIShareViewController for robust handling
//  of saving content to the App Group and auto-opening the host app.

import Foundation
import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    private var processedItems = 0
    private var totalItems = 0

    private var appGroupId: String {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String
        return (fromPlist?.isEmpty == false) ? fromPlist! : "group.com.example.cpft.share"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NSLog("[ShareExt] ShareViewController appeared")
    }

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        NSLog("[ShareExt] didSelectPost")
        handleSharedContent()
    }

    override func configurationItems() -> [Any]! {
        let openItem = SLComposeSheetConfigurationItem()
        openItem?.title = "Open CPFT App"
        openItem?.tapHandler = { [weak self] in
            self?.handleSharedContent()
        }
        if let item = openItem { return [item] }
        return []
    }

    private func handleSharedContent() {
        guard let ctx = extensionContext else {
            completeRequest()
            return
        }

        let attachments = ctx.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        totalItems = attachments.count
        NSLog("[ShareExt] attachments count = \(totalItems)")

        if totalItems == 0 {
            // No attachments, still try to open app (for text-only cases)
            openMainApp()
            return
        }

        for attachment in attachments {
            processAttachment(attachment)
        }
    }

    private func processAttachment(_ attachment: NSItemProvider) {
        if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            loadItem(attachment, type: UTType.image.identifier) { [weak self] data in
                if let url = data as? URL { self?.copyFile(url: url, asType: "image") }
                else if let img = data as? UIImage { self?.saveImage(img) }
            }
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            loadItem(attachment, type: UTType.movie.identifier) { [weak self] data in
                if let url = data as? URL { self?.copyFile(url: url, asType: "video") }
            }
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            loadItem(attachment, type: UTType.fileURL.identifier) { [weak self] data in
                if let url = data as? URL { self?.copyFile(url: url, asType: "file") }
            }
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            loadItem(attachment, type: UTType.url.identifier) { [weak self] data in
                if let url = data as? URL { self?.saveToDefaults(text: url.absoluteString, type: "url") }
            }
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            loadItem(attachment, type: UTType.text.identifier) { [weak self] data in
                if let text = data as? String { self?.saveToDefaults(text: text, type: "text") }
            }
        } else {
            itemProcessed()
        }
    }

    private func loadItem(_ provider: NSItemProvider, type: String, handler: @escaping (NSSecureCoding?) -> Void) {
        provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] (data, error) in
            if let error = error { NSLog("[ShareExt] loadItem error: \(error.localizedDescription)") }
            handler(data)
            self?.itemProcessed()
        }
    }

    private func saveImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        let fileName = "shared_image_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
        guard let dest = containerURL?.appendingPathComponent(fileName) else { return }
        do {
            try data.write(to: dest)
            NSLog("[ShareExt] saved image: \(dest.path)")
            saveToDefaults(text: dest.path, type: "image")
        } catch {
            NSLog("[ShareExt] saveImage error: \(error.localizedDescription)")
        }
    }

    private func copyFile(url: URL, asType type: String) {
        let fileName = "shared_\(type)_\(Int(Date().timeIntervalSince1970 * 1000))_\(url.lastPathComponent)"
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
        guard let dest = containerURL?.appendingPathComponent(fileName) else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: url, to: dest)
            NSLog("[ShareExt] copied file: \(dest.path)")
            saveToDefaults(text: dest.path, type: type)
        } catch {
            NSLog("[ShareExt] copyFile error: \(error.localizedDescription)")
        }
    }

    private func saveToDefaults(text: String, type: String) {
        let defaults = UserDefaults(suiteName: appGroupId)
        if type == "text" || type == "url" { defaults?.set(text, forKey: "sharedText") }
        else { defaults?.set(text, forKey: "sharedFileURL") }
        defaults?.set(type, forKey: "sharedType")
        defaults?.set(Date(), forKey: "sharedTimestamp")
        defaults?.synchronize()
    }

    private func itemProcessed() {
        processedItems += 1
        if processedItems >= totalItems {
            openMainApp()
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func openMainApp() {
        // Try ShareMedia-<bundleId> then fallback to cpft://share
        let extBundleId = Bundle.main.bundleIdentifier ?? ""
        let hostBundleIdGuess = extBundleId.replacingOccurrences(of: ".Share-Extension", with: "")
        let hostBundleId = hostBundleIdGuess.isEmpty ? "com.example.cpft" : hostBundleIdGuess

        let candidates = [
            "ShareMedia-\(hostBundleId)://",
            "cpft://share"
        ]

        func tryOpen(_ urlString: String, completion: @escaping (Bool) -> Void) {
            guard let url = URL(string: urlString) else { completion(false); return }
            NSLog("[ShareExt] opening URL: \(urlString)")
            if #available(iOS 13.0, *) {
                extensionContext?.open(url, completionHandler: { success in
                    NSLog("[ShareExt] opening URL completion: \(urlString) success=\(success)")
                    completion(success)
                })
            } else {
                var responder: UIResponder? = self as UIResponder
                let selector = #selector(openURL(_:))
                var performed = false
                while responder != nil {
                    if let r = responder, r.responds(to: selector) && r !== self {
                        let res = r.perform(selector, with: url)
                        performed = (res != nil)
                        break
                    }
                    responder = responder?.next
                }
                NSLog("[ShareExt] responder openURL performed=\(performed) for \(urlString)")
                completion(performed)
            }
        }

        func openNext(_ index: Int) {
            guard index < candidates.count else {
                // No open succeeded; finish extension gracefully
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.completeRequest()
                }
                return
            }
            tryOpen(candidates[index]) { success in
                if success {
                    // Delay completion a bit to allow app to foreground
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.completeRequest()
                    }
                } else {
                    openNext(index + 1)
                }
            }
        }

        openNext(0)
    }

    @objc private func openURL(_ url: URL) {}
}
