import AppKit
import FlipbookCapture
import FlipbookExport
import FlipbookInput

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
        } else if let index = arguments.firstIndex(of: "--render-ui") {
            guard index + 1 < arguments.count else {
                print("usage: Flipbook --render-ui <directory>")
                exit(2)
            }
            delegate = RenderUIDelegate(directory: URL(fileURLWithPath: arguments[index + 1]))
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

/// `--render-ui <dir>`: draws the UI to PNGs and exits. No permissions, no status item.
@MainActor
final class RenderUIDelegate: NSObject, NSApplicationDelegate {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UISnapshots.render(to: directory)
        exit(0)
    }
}

/// The app itself.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: SessionController?
    private var cards: CardController?
    private var filmstrip: FilmstripController?
    private var settingsWindow: SettingsWindowController?
    private var monitor: InputMonitor?
    private var statusMenu: StatusMenu?
    private var contentCache: ShareableContentCache?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. The log.
        log("launched")
        InputLog.setHandler { log($0) }

        // 2. Settings.
        let settingsStore = SettingsStore(defaults: .standard)
        let settings = settingsStore.settings

        // 3. Crash leftovers, then one retention pass.
        let store = CaptureStore(root: settings.saveLocation)
        store.removeLeftovers()
        let trashed = Retention.run(in: store, days: settings.retention.days, now: Date()) {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
        log("retention: \(trashed.count) capture(s) moved to the Trash")

        // 4. The screen and window list, kept fresh.
        let contentCache = ShareableContentCache()
        contentCache.refresh()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { contentCache.refresh() }
            }
        self.contentCache = contentCache

        // 5. The pill.
        let controller = SessionController(settingsStore: settingsStore, contentCache: contentCache, pill: PillPanel())
        let cards = CardController()
        let filmstrip = FilmstripController()
        cards.onOpen = { [weak cards, weak filmstrip] capture, id in
            guard let cards else { return }
            filmstrip?.toggle(capture, cardID: id, cards: cards)
        }
        filmstrip.onTrimmed = { [weak cards] capture, id in cards?.update(capture, id: id) }
        controller.cards = cards
        self.controller = controller
        self.cards = cards
        self.filmstrip = filmstrip

        // 6. The menu, and the Settings window it opens.
        let settingsWindow = SettingsWindowController(model: SettingsModel(store: settingsStore))
        self.settingsWindow = settingsWindow
        let statusMenu = StatusMenu(actions: .init(
            startStop: { [weak controller] in controller?.toggleFromMenu() },
            openFolder: { [weak controller] in
                guard let folder = controller?.settingsStore.settings.saveLocation else { return }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
            },
            settings: { [weak settingsWindow] in settingsWindow?.show() },
            recentCaptures: { [weak controller, weak cards] in
                guard let controller, let cards else { return [] }
                let store = CaptureStore(root: controller.settingsStore.settings.saveLocation)
                return RecentCaptures.latest(in: store).map { capture in
                    (title: RecentCaptures.title(for: capture), open: {
                        cards.reopen(capture, on: SessionController.screen(containing: SessionController.cursorLocation()))
                    })
                }
            }))
        controller.statusMenu = statusMenu
        self.statusMenu = statusMenu

        // 7. The key.
        let monitor = InputMonitor(trigger: settings.triggerKey, gestures: settings.gestureConfig,
                                   layout: CurrentKeyboardLayout(), delegate: controller)
        controller.inputMonitor = monitor
        monitor.start()
        self.monitor = monitor

        // 8. Permissions.
        Permissions.requestMissing()
    }
}
