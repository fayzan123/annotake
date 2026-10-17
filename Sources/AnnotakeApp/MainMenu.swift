import AppKit

/// The app's main menu. A text field gets ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z, and ⇧⌘Z only through the main menu's key equivalents:
/// without the Edit items, pasting an address into the email step with ⌘V would do nothing. Each item goes to the first
/// responder, the field's editor while one is typed in; with nothing there to take it, the key does nothing.
///
/// While the first run or Settings puts Annotake in the Dock (DockPresence), the menu bar shows this menu, so it also
/// holds the application menu (About, Settings…, Quit) and Window's Close. Otherwise it's an empty application menu and
/// Edit alone: the filmstrip and the frame viewer take keys without making Annotake the active app, so the menu bar
/// shows another app's menus, and ⌘Q there must not quit Annotake. Settings… reaches AppDelegate, at the responder
/// chain's end.
enum MainMenu {
    @MainActor static func make(inDock: Bool = false) -> NSMenu {
        let application = NSMenu()
        if inDock {
            application.addItem(item("About Annotake",
                                     #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""))
            application.addItem(.separator())
            application.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ","))
            application.addItem(.separator())
            application.addItem(item("Quit Annotake", #selector(NSApplication.terminate(_:)), "q"))
        }

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        // A capital, as ⇧⌘Z reports it (charactersIgnoringModifiers keeps Shift), and as Apple's own main menu has it:
        // AppKit matches a lowercase "z" with Shift only for an event that carries its keyboard layout.
        edit.addItem(item("Redo", Selector(("redo:")), "Z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        var menus = [edit]
        if inDock {
            // ⌘W closes the first run or Settings, as in any app.
            let window = NSMenu(title: "Window")
            window.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
            menus.append(window)
        }

        let main = NSMenu()
        // The application menu, first in every main menu, which macOS titles with the app's name whatever its own.
        let applicationItem = NSMenuItem(title: "Annotake", action: nil, keyEquivalent: "")
        applicationItem.submenu = application
        main.addItem(applicationItem)
        for menu in menus {
            let menuItem = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            menuItem.submenu = menu
            main.addItem(menuItem)
        }
        return main
    }

    /// No target: the action goes to the first responder.
    @MainActor private static func item(_ title: String, _ action: Selector, _ key: String,
                                        _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
