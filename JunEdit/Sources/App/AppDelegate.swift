import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Validate saved blog directory — must contain build.py
        if let saved = BlogSettings.shared.blogDirectory {
            if !FileManager.default.fileExists(atPath: saved.appendingPathComponent("build.py").path) {
                NSLog("JunEdit: Saved directory invalid (\(saved.path)), resetting")
                BlogSettings.shared.blogDirectory = nil
            }
        }

        // Auto-detect blog directory if not set
        if BlogSettings.shared.blogDirectory == nil {
            let defaultPath = "/Users/hejun/Documents/_Xcode/Blog/junhe"
            let url = URL(fileURLWithPath: defaultPath)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("build.py").path) {
                NSLog("JunEdit: Auto-detected blog directory: \(defaultPath)")
                BlogSettings.shared.blogDirectory = url
            }
        }

        let controller = MainWindowController()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        mainWindowController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
