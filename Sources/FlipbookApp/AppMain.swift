import AppKit

/// The app's entry point, called from the `Flipbook` executable's main.swift. It isn't named
/// `FlipbookApp`, because a type named like its own module makes qualified names ambiguous.
public enum AppEntry {
    @MainActor public static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--selftest") || arguments.contains("--render-ui") {
            print("not implemented")
            exit(1)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("launched")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "photo.stack", accessibilityDescription: "Flipbook")
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
