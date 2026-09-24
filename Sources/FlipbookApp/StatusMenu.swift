import AppKit

/// The menu-bar icon and its menu (spec §3.5). The menu is rebuilt each time it opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    static let idleSymbol = "photo.stack"
    static let recordingSymbol = "record.circle.fill"

    struct Actions {
        var startStop: () -> Void
        var openFolder: () -> Void
        /// Titles for Recent Captures, newest first, and what choosing one does.
        var recentCaptures: () -> [(title: String, open: () -> Void)]
    }

    let statusItem: NSStatusItem
    private let actions: Actions
    private var recording = false
    private var targets: [ButtonTarget] = []

    init(actions: Actions) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        setRecording(false)
    }

    func setRecording(_ recording: Bool) {
        self.recording = recording
        let symbol = recording ? Self.recordingSymbol : Self.idleSymbol
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Flipbook")
        if recording {
            image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }
        statusItem.button?.image = image
    }

    /// The status item's window, for keeping the icon out of frames on macOS 26.
    var windowNumber: Int? { statusItem.button?.window?.windowNumber }

    /// The icon's frame in global points, top-left origin.
    var globalFrame: CGRect? {
        guard let frame = statusItem.button?.window?.frame, let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: frame.minX, y: primary.frame.height - frame.maxY, width: frame.width, height: frame.height)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        targets = []
        menu.addItem(item(recording ? "Stop Recording" : "Start Recording", actions.startStop))

        let recent = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let captures = actions.recentCaptures()
        if captures.isEmpty {
            let none = NSMenuItem(title: "No Captures Yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        }
        for capture in captures {
            submenu.addItem(item(capture.title, capture.open))
        }
        recent.submenu = submenu
        menu.addItem(recent)

        menu.addItem(item("Open Captures Folder", actions.openFolder))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Flipbook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let target = ButtonTarget()
        target.action = action
        targets.append(target)
        let item = NSMenuItem(title: title, action: #selector(ButtonTarget.run), keyEquivalent: "")
        item.target = target
        return item
    }
}
