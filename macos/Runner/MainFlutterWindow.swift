import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    // Phone-shaped window: 405x720 logical (9:16), min enforced so the UI
    // always looks like the mobile app (also fixes store screenshots).
    self.minSize = NSSize(width: 405, height: 720)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // Apply phone frame after autosaved-frame restoration wins the race
    DispatchQueue.main.async {
      self.setFrame(NSRect(origin: self.frame.origin, size: NSSize(width: 405, height: 720)), display: true, animate: false)
    }
  }
}
