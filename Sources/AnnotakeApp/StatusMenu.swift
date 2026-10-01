import AppKit

/// The menu's items, in order (spec §3.5). "Fix permissions…" shows only while one is missing.
enum MenuModel {
    enum Item: Equatable {
        case fixPermissions, startRecording, stopRecording, recent([String]), openFolder, settings, checkForUpdates,
             quit
    }

    static func items(missingPermission: Bool, recording: Bool, recentTitles: [String]) -> [Item] {
        (missingPermission ? [.fixPermissions] : [])
            + [recording ? .stopRecording : .startRecording, .recent(recentTitles), .openFolder, .settings,
               .checkForUpdates, .quit]
    }
}

/// The menu-bar icon and its menu. The menu is rebuilt from MenuModel each time it opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    static let idleSymbol = "photo.stack"
    static let recordingSymbol = "record.circle.fill"

    struct Actions {
        var fixPermissions: () -> Void
        var startStop: () -> Void
        var isRecording: () -> Bool
        var openFolder: () -> Void
        var settings: () -> Void
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

    /// The icon: a template stack of photos, or a red record symbol while recording.
    func setRecording(_ recording: Bool) {
        var image = NSImage(systemSymbolName: recording ? Self.recordingSymbol : Self.idleSymbol,
                            accessibilityDescription: "Annotake")
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
