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
    @discardableResult
    func add(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(ClosureTarget.run), keyEquivalent: "")
        let target = ClosureTarget(action)
        item.target = target
        item.representedObject = target  // keeps the target alive
        menu.insertItem(item, at: menu.numberOfItems - 2)
        return item
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
let triggerItem = spikeMenu.add("Trigger spike") {
    triggerSpike.toggle()
    triggerItem.state = triggerSpike.isOn ? .on : .off
}
spikeMenu.add("Request Accessibility prompt") { triggerSpike.requestAccessibility() }
let axItem = spikeMenu.add("AX spike") {
    axSpike.toggle()
    axItem.state = axSpike.isOn ? .on : .off
}
spikeMenu.add("Enable AX in Chrome/Electron") { axSpike.enableWebAX() }
spikeMenu.add("Capture spike (10 s)") { captureSpike.start() }
spikeMenu.add("Drag card spike") { dragSpike.show() }
captureSpike.showPill()
log("spike launched")
app.run()
