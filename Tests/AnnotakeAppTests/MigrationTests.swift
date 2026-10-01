@testable import AnnotakeApp
import AnnotakeExport
import Foundation
import Testing

/// Bringing Flipbook's settings and captures over (spec §3.8). Every test passes its own old domain and a
/// temporary home, so the real Flipbook settings and captures on this Mac are never read or touched.
struct MigrationTests {
    /// A temporary home with a Pictures folder, and a fresh defaults suite; both are removed afterwards.
    func withHome(_ body: (URL, UserDefaults) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "annotake-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appending(path: "Pictures"), withIntermediateDirectories: true)
        let suite = "annotake-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: home.appending(path: "Pictures").path)
            try? FileManager.default.removeItem(at: home)
        }
        try body(home, defaults)
    }

    /// Runs migration on the test's own old domain, collecting what it would log.
    @discardableResult
    func migrate(_ defaults: UserDefaults, home: URL, domain: [String: Any]?) -> (plan: MigrationPlan?, log: [String]) {
        var lines: [String] = []
        let plan = Migration.run(defaults: defaults, home: home, oldDomain: domain, report: { lines.append($0) })
        return (plan, lines)
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    /// A capture folder that Flipbook made, with only its `.flipbook` marker.
    @discardableResult
    func flipbookCapture(in root: URL, named name: String = "2026-09-24 at 10.00.00",
                         date: String = "2026-09-24T10:00:00Z") throws -> URL {
        let folder = root.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(date.utf8).write(to: folder.appending(path: ".flipbook"))
        return folder
    }

    /// Flipbook's preferences, with its settings saved where `saveLocation` says.
    func flipbookDomain(saveLocation: URL, change: (inout Settings) -> Void = { _ in }) throws -> [String: Any] {
        var settings = Settings()
        settings.saveLocation = saveLocation
        change(&settings)
        return ["settings.v1": try JSONEncoder().encode(settings)]
    }

    @Test func importsSettingsButNotFirstRunState() throws {
        try withHome { home, defaults in
            var domain = try flipbookDomain(saveLocation: home.appending(path: "Pictures/Flipbook")) {
                $0.triggerKey = .rightOption
                $0.sounds = false
            }
            domain["firstLaunch.v1"] = Data(#"{"requested":["accessibility"],"completed":true}"#.utf8)
            domain["loginItem.initialized"] = true

            let plan = try #require(Migration.plan(oldDomain: domain, alreadyDone: false, home: home,
                                                   exists: { _ in false }))
            #expect(plan.settings?.triggerKey == .rightOption)
            #expect(plan.settings?.sounds == false)
            #expect(plan.existingUser)

            migrate(defaults, home: home, domain: domain)
            let imported = SettingsStore(defaults: defaults).settings
            #expect(imported.triggerKey == .rightOption)
            #expect(!imported.sounds)
            #expect(defaults.object(forKey: "firstLaunch.v1") == nil)
            #expect(defaults.object(forKey: "loginItem.initialized") == nil)
        }
    }

    @Test func defaultSaveLocationMovesWithTheFolder() throws {
        try withHome { home, defaults in
            let old = home.appending(path: "Pictures/Flipbook")
            let new = home.appending(path: "Pictures/Annotake")
            try flipbookCapture(in: old)
            let domain = try flipbookDomain(saveLocation: old)

            let (result, log) = migrate(defaults, home: home, domain: domain)
            let plan = try #require(result)
            #expect(plan.move == FolderMove(from: old, to: new))
            #expect(plan.markerRoot == new)

            let capture = new.appending(path: "2026-09-24 at 10.00.00")
            #expect(exists(capture.appending(path: CaptureStore.markerName)))
            #expect(!exists(capture.appending(path: ".flipbook")))
            #expect(CaptureStore.readMarker(in: capture) == date("2026-09-24T10:00:00Z"))
            #expect(!exists(old))
            #expect(SettingsStore(defaults: defaults).settings.saveLocation.path == new.path)
            #expect(log == ["migration: settings imported, folder moved, 1 marker(s) renamed"])
        }
    }

    @Test func customSaveLocationStays() throws {
        try withHome { home, defaults in
            let elsewhere = home.appending(path: "Elsewhere")
            let capture = try flipbookCapture(in: elsewhere)
            try FileManager.default.createDirectory(at: elsewhere.appending(path: ".flipbook-tmp/leftover"),
                                                    withIntermediateDirectories: true)
            let domain = try flipbookDomain(saveLocation: elsewhere)

            let plan = try #require(migrate(defaults, home: home, domain: domain).plan)
            #expect(plan.move == nil)
            #expect(plan.markerRoot == elsewhere)
            #expect(SettingsStore(defaults: defaults).settings.saveLocation.path == elsewhere.path)
            #expect(exists(capture.appending(path: CaptureStore.markerName)))
            #expect(!exists(capture.appending(path: ".flipbook")))
            #expect(!exists(elsewhere.appending(path: ".flipbook-tmp")))
            #expect(!exists(home.appending(path: "Pictures/Annotake")))
        }
    }

    @Test func existingAnnotakeFolderBlocksTheMove() throws {
        try withHome { home, defaults in
            let old = home.appending(path: "Pictures/Flipbook")
            let new = home.appending(path: "Pictures/Annotake")
            let capture = try flipbookCapture(in: old)
            try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
            let domain = try flipbookDomain(saveLocation: old)

            let (result, log) = migrate(defaults, home: home, domain: domain)
            let plan = try #require(result)
            #expect(plan.move == nil)
            #expect(plan.markerRoot == nil)
            #expect(log.first == "migration: the old captures folder stays where it is, because the new one already exists")
            #expect(plan.settings?.saveLocation.path == new.path)
            #expect(exists(capture.appending(path: ".flipbook")))
            #expect(!exists(capture.appending(path: CaptureStore.markerName)))
            #expect(SettingsStore(defaults: defaults).settings.saveLocation.path == new.path)
        }
    }

    @Test func runsOnce() throws {
        try withHome { home, defaults in
            let old = home.appending(path: "Pictures/Flipbook")
            try flipbookCapture(in: old)
            var domain = try flipbookDomain(saveLocation: old) { $0.maxFrames = 12 }
            #expect(migrate(defaults, home: home, domain: domain).plan != nil)

            // Flipbook's folder and settings come back somehow; nothing moves a second time.
            let again = try flipbookCapture(in: old, named: "again")
            domain = try flipbookDomain(saveLocation: old) { $0.maxFrames = 30 }
            let second = migrate(defaults, home: home, domain: domain)
            #expect(second.plan == nil)
            #expect(second.log.isEmpty)
            #expect(exists(again.appending(path: ".flipbook")))
            #expect(SettingsStore(defaults: defaults).settings.maxFrames == 12)
        }
    }

    @Test func freshMacIsNotAnExistingUser() throws {
        try withHome { home, defaults in
            let plan = try #require(Migration.plan(oldDomain: nil, alreadyDone: false, home: home,
                                                   exists: { _ in false }))
            #expect(!plan.existingUser)
            #expect(plan.move == nil)
            #expect(plan.settings == nil)

            migrate(defaults, home: home, domain: nil)
            #expect(defaults.bool(forKey: Migration.doneKey))
            #expect(defaults.data(forKey: SettingsStore.key) == nil)
        }
    }

    @Test func anyOldPreferenceMeansAnExistingUser() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let plan = Migration.plan(oldDomain: ["loginItem.initialized": true], alreadyDone: false, home: home,
                                  exists: { _ in false })
        #expect(plan?.existingUser == true)
        #expect(plan?.settings == nil)
        let folderOnly = Migration.plan(oldDomain: nil, alreadyDone: false, home: home,
                                        exists: { $0.path == "/Users/someone/Pictures/Flipbook" })
        #expect(folderOnly?.existingUser == true)
        #expect(folderOnly?.move == FolderMove(from: home.appending(path: "Pictures/Flipbook"),
                                               to: home.appending(path: "Pictures/Annotake")))
    }

    /// When the folder can't be moved, recordings keep going to it, so its captures stay listed and cleaned up.
    @Test func failedMoveKeepsTheOldFolder() throws {
        try withHome { home, defaults in
            let pictures = home.appending(path: "Pictures")
            let old = pictures.appending(path: "Flipbook")
            let capture = try flipbookCapture(in: old)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: pictures.path)

            let (result, log) = migrate(defaults, home: home, domain: nil)
            let plan = try #require(result)
            #expect(plan.move == nil)
            #expect(plan.markerRoot == old)
            #expect(log.first?.hasPrefix("migration: the captures folder couldn't be moved") == true)
            #expect(exists(old))
            #expect(SettingsStore(defaults: defaults).settings.saveLocation.path == old.path)
            #expect(exists(capture.appending(path: CaptureStore.markerName)))
        }
    }

    @Test func retiresOnlyInstalledCopies() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let own = URL(fileURLWithPath: "/Applications/Annotake.app")
        func retires(_ url: URL) -> Bool {
            LegacyApp.shouldRetire(appURL: url, ownBundleURL: own, home: home)
        }
        #expect(retires(URL(fileURLWithPath: "/Applications/Flipbook.app")))
        #expect(retires(home.appending(path: "Applications/Flipbook.app")))
        #expect(!retires(home.appending(path: "Documents/GitHub/annotake/build/Flipbook.app")))
        #expect(!retires(own))
    }
}
