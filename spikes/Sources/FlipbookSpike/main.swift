import AppKit

final class SpikeMenu: NSObject {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()

    override init() {
        super.init()
        statusItem.button?.title = "FB"
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    /// Later tasks add their experiments above the separator and Quit.
    func add(_ title: String, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(ClosureTarget.run), keyEquivalent: "")
        let target = ClosureTarget(action)
        item.target = target
        item.representedObject = target  // keeps the target alive
        menu.insertItem(item, at: menu.numberOfItems - 2)
    }
}

final class ClosureTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let spikeMenu = SpikeMenu()
log("spike launched")
app.run()
