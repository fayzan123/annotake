import AppKit

/// The app's main menu. Annotake is menu-bar-only (`.accessory`), so it never shows, but a text field gets ⌘X, ⌘C,
/// ⌘V, ⌘A, ⌘Z, and ⇧⌘Z only through the main menu's key equivalents: without these items, pasting an address into the
/// email step with ⌘V would do nothing. Each item goes to the first responder, the field's editor while one is typed
/// in; with nothing there to take it, the key does nothing, as before.
enum EditMenu {
    @MainActor static func make() -> NSMenu {
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

        let main = NSMenu()
        // The application menu, first in every main menu; this one holds nothing.
        let application = NSMenuItem()
        application.submenu = NSMenu()
        main.addItem(application)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
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
