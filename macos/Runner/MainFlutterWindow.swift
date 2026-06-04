import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    if #available(macOS 10.14, *) {
      appearance = NSAppearance(named: .darkAqua)
    }

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    if let screenFrame = NSScreen.main?.visibleFrame {
      self.setFrame(screenFrame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
