import AppKit

/// The app's entry point, called from the `Flipbook` executable's main.swift. It isn't named
/// `FlipbookApp`, because a type named like its own module makes qualified names ambiguous.
public enum AppEntry {
    @MainActor public static func main() {
        let arguments = CommandLine.arguments
        let delegate: NSApplicationDelegate
        if let index = arguments.firstIndex(of: "--selftest") {
            guard index + 1 < arguments.count else {
                print("usage: Flipbook --selftest <directory>")
                exit(2)
            }
            delegate = SelfTestDelegate(directory: URL(fileURLWithPath: arguments[index + 1]))
        } else if arguments.contains("--render-ui") {
            print("not implemented")
            exit(1)
        } else {
            delegate = AppDelegate()
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

/// `--selftest <dir>`: no status item, no permission requests, no event taps. Runs the self-test and exits.
@MainActor
final class SelfTestDelegate: NSObject, NSApplicationDelegate {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            exit(await SelfTest.run(outputDirectory: directory))
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
