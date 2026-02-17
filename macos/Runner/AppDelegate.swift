import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Status bar (tray) item
  var statusItem: NSStatusItem?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // Try to load `assets/icon.ico` from the bundled flutter assets at runtime.
    // If successful, use it for Dock/app icon, window document icon and status bar.
    if let resourcePath = Bundle.main.resourcePath {
      let iconURL = URL(fileURLWithPath: resourcePath).appendingPathComponent("flutter_assets/assets/icon.ico")
      if let image = NSImage(contentsOf: iconURL) {
        NSApplication.shared.applicationIconImage = image
        if let window = NSApp.windows.first {
          window.standardWindowButton(.documentIconButton)?.image = image
        }

        // Create a status bar (tray) icon + simple menu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = image
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Posti", action: #selector(showWindow(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
      }
    }
  }

  @objc func showWindow(_ sender: Any?) {
    if let window = NSApp.windows.first {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
