import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    
    // Enable key monitoring
    self.makeFirstResponder(flutterViewController.view)
    self.makeKeyAndOrderFront(nil)
    
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
  
  // Override key handling methods
  override func keyDown(with event: NSEvent) {
    if self.firstResponder?.responds(to: #selector(keyDown(with:))) ?? false {
      self.firstResponder?.keyDown(with: event)
    }
  }
  
  override func keyUp(with event: NSEvent) {
    if self.firstResponder?.responds(to: #selector(keyUp(with:))) ?? false {
      self.firstResponder?.keyUp(with: event)
    }
  }
}
