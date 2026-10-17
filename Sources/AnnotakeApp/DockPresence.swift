import AppKit

/// Annotake lives in the menu bar, and is in the Dock and ⌘-Tab only while the first run or Settings is open, as other
/// menu-bar apps do: a window behind another app, such as System Settings during the permissions, can then be found
/// again. The pill, the cards, and the filmstrip float above every app, so they don't count. While Annotake is in the
/// Dock, the menu bar shows its own menus, so the main menu gains the application menu and Window (MainMenu).
@MainActor
final class DockPresence {
    static let shared = DockPresence()
    private let apply: @MainActor (NSApplication.ActivationPolicy) -> Void
    /// The windows open, by identity.
    private var open: Set<ObjectIdentifier> = []

    /// `apply` stands in for NSApp in tests.
    init(apply: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { policy in
        NSApp.mainMenu = MainMenu.make(inDock: policy == .regular)
        NSApp.setActivationPolicy(policy)
    }) {
        self.apply = apply
    }

    /// A window about to show: the first puts Annotake in the Dock. One already showing changes nothing.
    func shown(_ window: AnyObject) {
        guard open.insert(ObjectIdentifier(window)).inserted, open.count == 1 else { return }
        apply(.regular)
    }

    /// A window closing: the last takes Annotake out of the Dock.
    func closed(_ window: AnyObject) {
        guard open.remove(ObjectIdentifier(window)) != nil, open.isEmpty else { return }
        apply(.accessory)
    }
}
