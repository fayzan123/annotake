import AnnotakeExport
import AppKit

/// The old app's names, used only to bring its data over (design §3.1). This file, its tests, and the
/// installer are the only places the code names Flipbook.
enum LegacyFlipbook {
    static let bundleID = "com.fayzanmalik.flipbook"
    /// Under ~/Pictures.
    static let folderName = "Flipbook"
    static let tempFolderName = ".flipbook-tmp"
    /// The only key that's copied: the first-run state stays behind, because macOS asks for the
    /// permissions again under the new signature and bundle id.
    static let settingsKey = "settings.v1"
    static let appBundleName = "Flipbook.app"
    /// The first run's two lines about the old app (spec §3.7).
    static let replacedNote = "Flipbook was moved to the Trash. Annotake replaces it."
    static let askAgainNote = "Annotake replaces Flipbook, so macOS asks for these again."
}

struct FolderMove: Equatable {
    var from: URL
    var to: URL
}

/// What migration does at Annotake's first launch (spec §3.8).
struct MigrationPlan: Equatable {
    /// Written to the new domain; nil means nothing to import.
    var settings: Settings?
    /// ~/Pictures/Flipbook → ~/Pictures/Annotake.
    var move: FolderMove?
    /// Where legacy markers get renamed: the effective save location.
    var markerRoot: URL?
    /// Flipbook was used on this Mac.
    var existingUser: Bool
}

/// Brings Flipbook's settings and captures over, once (spec §3.8).
enum Migration {
    static let doneKey = "migration.flipbook.v1"

    /// Pure. Nil when it has already run.
    static func plan(oldDomain: [String: Any]?, alreadyDone: Bool, home: URL,
                     exists: (URL) -> Bool) -> MigrationPlan? {
        guard !alreadyDone else { return nil }
        let old = oldFolder(home: home)
        let new = Settings.defaultSaveLocation(home: home)
        var settings = (oldDomain?[LegacyFlipbook.settingsKey] as? Data)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }?
            .clamped()
        let oldLocation = settings?.saveLocation ?? old
        var plan = MigrationPlan(settings: nil, move: nil, markerRoot: nil,
                                 existingUser: settings != nil || exists(old) || !(oldDomain?.isEmpty ?? true))
        if oldLocation.standardizedFileURL.path == old.standardizedFileURL.path {
            // The default location moves with its folder, unless Annotake's folder is already there.
            if exists(old) && !exists(new) {
                plan.move = FolderMove(from: old, to: new)
                plan.markerRoot = new
            }
            settings?.saveLocation = new
        } else if exists(oldLocation) {
            plan.markerRoot = oldLocation
        }
        plan.settings = settings
        return plan
    }

    /// Glue: runs the plan for Flipbook's preferences (`oldDomain`, read from its domain unless a test passes
    /// one), sets `doneKey`, and logs counts only, to `report` (the log unless a test passes one). Returns the
    /// plan it ran.
    ///
    /// When the folder can't be moved, it stays the save location, so its captures stay in Recent Captures
    /// and cleanup.
    @discardableResult
    static func run(defaults: UserDefaults, home: URL,
                    oldDomain: [String: Any]? = UserDefaults.standard.persistentDomain(forName: LegacyFlipbook.bundleID),
                    report: (String) -> Void = { log($0) }) -> MigrationPlan? {
        let files = FileManager.default
        guard var plan = plan(oldDomain: oldDomain, alreadyDone: defaults.bool(forKey: doneKey), home: home,
                              exists: { files.fileExists(atPath: $0.path) })
        else { return nil }

        let imported = plan.settings != nil
        var moved = false
        if let move = plan.move {
            do {
                try files.moveItem(at: move.from, to: move.to)
                moved = true
            } catch {
                report("migration: the captures folder couldn't be moved (error \((error as NSError).code)); "
                    + "it stays the save location")
                var settings = plan.settings ?? Settings()
                settings.saveLocation = move.from
                plan.settings = settings
                plan.move = nil
                plan.markerRoot = move.from
            }
        } else {
            let new = Settings.defaultSaveLocation(home: home)
            let usesDefault = (plan.settings?.saveLocation ?? new).path == new.path
            if usesDefault, files.fileExists(atPath: oldFolder(home: home).path), files.fileExists(atPath: new.path) {
                report("migration: the old captures folder stays where it is, because the new one already exists")
            }
        }
        if let settings = plan.settings {
            SettingsStore(defaults: defaults).settings = settings
        }
        let renamed = plan.markerRoot.map(renameMarkers(in:)) ?? 0
        defaults.set(true, forKey: doneKey)
        report("migration: \(imported ? "settings imported" : "no settings to import"), "
            + "\(moved ? "folder moved" : "no folder moved"), \(renamed) marker(s) renamed")
        return plan
    }

    /// `<home>/Pictures/Flipbook`
    static func oldFolder(home: URL) -> URL {
        home.appending(path: "Pictures").appending(path: LegacyFlipbook.folderName)
    }

    /// Renames `.flipbook` to `.annotake` (same contents) in each direct subfolder that has no `.annotake` yet,
    /// and deletes `<root>/.flipbook-tmp`. Returns how many it renamed.
    static func renameMarkers(in root: URL) -> Int {
        let files = FileManager.default
        try? files.removeItem(at: root.appending(path: LegacyFlipbook.tempFolderName))
        let folders = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                       options: .skipsHiddenFiles)) ?? []
        var renamed = 0
        for folder in folders {
            let legacy = folder.appending(path: CaptureStore.legacyMarkerName)
            let current = folder.appending(path: CaptureStore.markerName)
            guard files.fileExists(atPath: legacy.path), !files.fileExists(atPath: current.path) else { continue }
            if (try? files.moveItem(at: legacy, to: current)) != nil { renamed += 1 }
        }
        return renamed
    }
}

/// The installed Flipbook: quit and moved to the Trash at Annotake's first launch, so only Annotake answers
/// the trigger key (spec §3.8).
enum LegacyApp {
    /// How long a running Flipbook gets to quit before it's forced to.
    static let quitTimeout: TimeInterval = 2
    static let quitPollInterval: TimeInterval = 0.05

    /// Pure: an installed copy of the old app (inside /Applications or ~/Applications) that isn't this app.
    static func shouldRetire(appURL: URL, ownBundleURL: URL, home: URL) -> Bool {
        appURL.standardizedFileURL.path != ownBundleURL.standardizedFileURL.path
            && LoginItemPolicy.canRegister(bundleURL: appURL, home: home)
    }

    /// Glue: quits a running Flipbook (terminate, then forceTerminate after `quitTimeout`), then moves each copy
    /// that `shouldRetire` accepts to the Trash. True if it retired one.
    @MainActor
    static func retire() -> Bool {
        quitRunningCopies()
        let home = FileManager.default.homeDirectoryForCurrentUser
        var retired = false
        for url in copies(home: home)
        where shouldRetire(appURL: url, ownBundleURL: Bundle.main.bundleURL, home: home) {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                retired = true
                log("the old app was moved to the Trash")
            } catch {
                log("the old app couldn't be moved to the Trash (error \((error as NSError).code))")
            }
        }
        return retired
    }

    @MainActor
    private static func quitRunningCopies() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: LegacyFlipbook.bundleID)
        guard !running.isEmpty else { return }
        func alive(_ app: NSRunningApplication) -> Bool {
            !app.isTerminated && kill(app.processIdentifier, 0) == 0
        }
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(quitTimeout)
        while running.contains(where: alive), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(quitPollInterval))
        }
        let stubborn = running.filter(alive)
        stubborn.forEach { $0.forceTerminate() }
        log("quit the old app\(stubborn.isEmpty ? "" : ", forced")")
    }

    /// Every copy Launch Services knows, plus the two Applications folders, without duplicates.
    private static func copies(home: URL) -> [URL] {
        var urls = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: LegacyFlipbook.bundleID)
        for folder in [URL(fileURLWithPath: "/Applications"), home.appending(path: "Applications")] {
            let candidate = folder.appending(path: LegacyFlipbook.appBundleName)
            if Bundle(url: candidate)?.bundleIdentifier == LegacyFlipbook.bundleID { urls.append(candidate) }
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
