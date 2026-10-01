import AppKit

/// The menu's items, in order (spec §3.5). "Fix permissions…" shows only while one is missing.
enum MenuModel {
    enum Item: Equatable {
        case fixPermissions, startRecording, stopRecording, recent([String]), openFolder, settings, sendFeedback,
             checkForUpdates, quit
    }

    static func items(missingPermission: Bool, recording: Bool, recentTitles: [String]) -> [Item] {
        (missingPermission ? [.fixPermissions] : [])
            + [recording ? .stopRecording : .startRecording, .recent(recentTitles), .openFolder, .settings,
               .sendFeedback, .checkForUpdates, .quit]
    }
}

/// The menu-bar icon: the mark (BrandMark), as a template image so it takes the menu bar's color. While recording,
/// the front reel turns red and the rest keeps the menu bar's color.
enum MenuBarIcon {
    /// In points. The mark is narrow, so it gets the full height of a menu-bar symbol like photo.stack.
    static let height: CGFloat = 18

    @MainActor
    static func image(recording: Bool) -> NSImage {
        let width = (height * BrandMark.bounds.width / BrandMark.bounds.height).rounded(.up)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // A template's color comes from its alpha, so it's drawn opaque. While recording, the ink is the label
            // color, resolved as the icon draws, so it follows the menu bar between light and dark.
            let ink = recording ? NSColor.labelColor.cgColor : NSColor.black.cgColor
            BrandMark.draw(in: context, rect: rect, ink: ink, frontReel: recording ? NSColor.systemRed.cgColor : ink)
            return true
        }
        // Redrawn every time, never from a cached bitmap in the appearance it was first drawn in.
        image.cacheMode = .never
        image.isTemplate = !recording
        image.accessibilityDescription = recording ? "Annotake, recording" : "Annotake"
        return image
    }
}

/// The menu-bar icon and its menu. The menu is rebuilt from MenuModel each time it opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    struct Actions {
        var fixPermissions: () -> Void
        var startStop: () -> Void
        var isRecording: () -> Bool
        var openFolder: () -> Void
        var settings: () -> Void
        var sendFeedback: () -> Void
        var checkForUpdates: () -> Void
        /// Recent Captures, newest first, and what choosing one does.
        var recentCaptures: () -> [(title: String, open: () -> Void)]
    }

    let statusItem: NSStatusItem
    private let actions: Actions
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

    /// The icon: the mark, its front reel red while recording.
    func setRecording(_ recording: Bool) {
        statusItem.button?.image = MenuBarIcon.image(recording: recording)
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
        let recent = actions.recentCaptures()
        let items = MenuModel.items(missingPermission: Permissions.status().anyMissing,
                                    recording: actions.isRecording(), recentTitles: recent.map(\.title))
        for entry in items {
            switch entry {
            case .fixPermissions:
                menu.addItem(item("Fix permissions…", actions.fixPermissions))
                menu.addItem(.separator())
            case .startRecording:
                menu.addItem(item("Start Recording", actions.startStop))
            case .stopRecording:
                menu.addItem(item("Stop Recording", actions.startStop))
            case .recent:
                menu.addItem(recentItem(recent))
            case .openFolder:
                menu.addItem(item("Open Captures Folder", actions.openFolder))
            case .settings:
                menu.addItem(item("Settings…", actions.settings))
            case .sendFeedback:
                menu.addItem(item("Send Feedback…", actions.sendFeedback))
            case .checkForUpdates:
                menu.addItem(item("Check for Updates…", actions.checkForUpdates))
            case .quit:
                menu.addItem(.separator())
                menu.addItem(NSMenuItem(title: "Quit Annotake", action: #selector(NSApplication.terminate(_:)),
                                        keyEquivalent: "q"))
            }
        }
    }

    private func recentItem(_ captures: [(title: String, open: () -> Void)]) -> NSMenuItem {
        let recent = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if captures.isEmpty {
            let none = NSMenuItem(title: "No Captures Yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        }
        for capture in captures {
            submenu.addItem(item(capture.title, capture.open))
        }
        recent.submenu = submenu
        return recent
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
