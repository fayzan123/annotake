import AppKit
import AnnotakeCapture
import AnnotakeExport
import AnnotakeInput

/// The app's entry point, called from the `Annotake` executable's main.swift. It isn't named
/// `AnnotakeApp`, because a type named like its own module makes qualified names ambiguous.
public enum AppEntry {
    /// The normal app calls `makeUpdater` once; --selftest and --render-ui never do, so they make no
    /// network calls.
    @MainActor public static func main(makeUpdater: @escaping @MainActor () -> any Updater) {
        let arguments = CommandLine.arguments
        let delegate: NSApplicationDelegate
        if let index = arguments.firstIndex(of: "--selftest") {
            guard index + 1 < arguments.count else {
                print("usage: Annotake --selftest <directory>")
                exit(2)
            }
            delegate = SelfTestDelegate(directory: URL(fileURLWithPath: arguments[index + 1]))
        } else if let index = arguments.firstIndex(of: "--render-ui") {
            guard index + 1 < arguments.count else {
                print("usage: Annotake --render-ui <directory>")
                exit(2)
            }
            delegate = RenderUIDelegate(directory: URL(fileURLWithPath: arguments[index + 1]))
        } else {
            delegate = AppDelegate(makeUpdater: makeUpdater)
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

/// When retention runs again after launch (spec §4.1): on wake and hourly, once 24 h have passed since
/// the last run.
enum RetentionSchedule {
    static let interval: TimeInterval = 86_400
    /// How often the hourly timer checks.
    static let checkInterval: TimeInterval = 3_600
    static let lastRunKey = "retention.lastRun"

    static func isDue(lastRun: Date?, now: Date) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= interval
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
    private var firstLaunch: FirstLaunchController?
    private var settingsStore: SettingsStore?
    private var retentionTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var monitor: InputMonitor?
    private var statusMenu: StatusMenu?
    private var contentCache: ShareableContentCache?
    private var screenObserver: NSObjectProtocol?
    /// What migration brought over from the old app, and whether the old app was retired (spec §3.8).
    private var migration: MigrationPlan?
    private var retiredFlipbook = false
    private let makeUpdater: @MainActor () -> any Updater
    private var updater: (any Updater)?

    init(makeUpdater: @escaping @MainActor () -> any Updater) {
        self.makeUpdater = makeUpdater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. The log.
        log("launched Annotake \(AppVersion.current)")
        InputLog.setHandler { log($0) }

        // 2. Coming from the old app (spec §3.8): its settings and captures, once, and only Annotake answers the key.
        migration = Migration.run(defaults: .standard, home: FileManager.default.homeDirectoryForCurrentUser)
        retiredFlipbook = LegacyApp.retire()

        // 3. Settings.
        let settingsStore = SettingsStore(defaults: .standard)
        let settings = settingsStore.settings

        // 4. Crash leftovers, then retention: now, then on wake and hourly once 24 h have passed.
        self.settingsStore = settingsStore
        CaptureStore(root: settings.saveLocation).removeLeftovers()
        startRetentionSchedule()

        // 5. The screen and window list, kept fresh.
        let contentCache = ShareableContentCache()
        contentCache.refresh()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { contentCache.refresh() }
            }
        self.contentCache = contentCache

        // 6. The pill.
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

        // 7. The menu, and the Settings window it opens.
        let settingsModel = SettingsModel(store: settingsStore)
        settingsModel.onChange = { [weak self] old, new in self?.settingsChanged(from: old, to: new) }
        let settingsWindow = SettingsWindowController(
            model: settingsModel, picker: RecordPickerModel(loader: { try await contentCache.current() }))
        self.settingsWindow = settingsWindow
        let statusMenu = StatusMenu(actions: .init(
            fixPermissions: { [weak self] in self?.firstLaunch?.show() },
            startStop: { [weak controller] in controller?.toggleFromMenu() },
            isRecording: { [weak controller] in controller?.isRecording ?? false },
            openFolder: { [weak controller] in
                guard let folder = controller?.settingsStore.settings.saveLocation else { return }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
            },
            settings: { [weak settingsWindow] in settingsWindow?.show() },
            checkForUpdates: { [weak self] in self?.updater?.checkForUpdates() },
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

        // 8. The key.
        let monitor = InputMonitor(trigger: settings.triggerKey, gestures: settings.gestureConfig,
                                   layout: CurrentKeyboardLayout(), delegate: controller)
        controller.inputMonitor = monitor
        monitor.start()
        self.monitor = monitor

        // 9. First launch: the permission checklist until the first recording, and the login item.
        Permissions.logStatus()
        let firstLaunch = FirstLaunchController(trigger: settings.triggerKey, defaults: .standard)
        controller.onRecordingSaved = { [weak firstLaunch] in firstLaunch?.recordingSaved() }
        firstLaunch.showIfNeeded()
        self.firstLaunch = firstLaunch
        LoginItem.registerOnFirstLaunch(enabled: settings.launchAtLogin, defaults: .standard)

        // 10. Updates: the app's first network call, a daily check (spec §6.2).
        updater = makeUpdater()
    }

    /// Settings apply live where they can (design §7): the trigger and gesture timings once idle, sounds at
    /// once, a new save location with one retention pass. Everything else is read at the next recording.
    private func settingsChanged(from old: Settings, to new: Settings) {
        if old.triggerKey != new.triggerKey || old.gestureConfig != new.gestureConfig {
            monitor?.reconfigure(trigger: new.triggerKey, gestures: new.gestureConfig)
        }
        if old.sounds != new.sounds { controller?.setSounds(new.sounds) }
        if old.launchAtLogin != new.launchAtLogin { LoginItem.set(new.launchAtLogin) }
        if old.saveLocation != new.saveLocation { retentionPass(new) }
    }

    /// Spec §4.1: cleanup runs at every launch, then whenever 24 h have passed (checked on wake and hourly).
    private func startRetentionSchedule() {
        if let settings = settingsStore?.settings { retentionPass(settings) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runRetentionIfDue() }
            }
        retentionTimer = Timer.onMainRunLoop(interval: RetentionSchedule.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runRetentionIfDue() }
        }
    }

    private func runRetentionIfDue() {
        let lastRun = UserDefaults.standard.object(forKey: RetentionSchedule.lastRunKey) as? Date
        guard let settings = settingsStore?.settings, RetentionSchedule.isDue(lastRun: lastRun, now: Date()) else { return }
        retentionPass(settings)
    }

    /// Moves captures older than the retention period to the Trash. Logs only the count.
    private func retentionPass(_ settings: Settings) {
        let now = Date()
        let trashed = Retention.run(in: CaptureStore(root: settings.saveLocation), days: settings.retention.days, now: now) {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
        UserDefaults.standard.set(now, forKey: RetentionSchedule.lastRunKey)
        log("retention: \(trashed.count) capture(s) moved to the Trash")
    }
}
