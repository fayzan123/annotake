@testable import AnnotakeApp
import AnnotakeCore
import Foundation
import Testing

struct SettingsTests {
    /// A store on a fresh defaults suite; `body` gets the suite name so it can open a second store on it.
    func withStore(_ body: (SettingsStore, String) throws -> Void) rethrows {
        let suite = "annotake-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(SettingsStore(defaults: defaults), suite)
    }

    @Test func defaultsMatchSpec() {
        let settings = Settings()
        #expect(settings.triggerKey == .rightCommand)
        #expect(settings.sounds)
        #expect(settings.launchAtLogin)
        #expect(settings.recordTarget == .cursorScreen)
        #expect(settings.maxFrames == 20)
        #expect(!settings.compactFrames)
        #expect(settings.captionStrip)
        #expect(settings.clickMarkers)
        #expect(settings.saveLocation.path == NSHomeDirectory() + "/Pictures/Annotake")
        #expect(settings.retention == .days30)
        #expect(settings.holdThreshold == 0.25)
        #expect(settings.holdReveal == 0.8)
        #expect(settings.doubleTapWindow == 0.3)
        #expect(!settings.saveRawSessions)
    }

    @Test func clampsValues() {
        func clamped(_ change: (inout Settings) -> Void) -> Settings {
            var settings = Settings()
            change(&settings)
            return settings.clamped()
        }
        #expect(clamped { $0.maxFrames = 1 }.maxFrames == 2)
        #expect(clamped { $0.maxFrames = 60 }.maxFrames == 50)
        #expect(clamped { $0.holdThreshold = 0.1 }.holdThreshold == 0.15)
        #expect(clamped { $0.holdThreshold = 0.7 }.holdThreshold == 0.5)
        #expect(clamped { $0.holdThreshold = 0.25; $0.holdReveal = 0.3 }.holdReveal == 0.45)
        #expect(clamped { $0.holdThreshold = 0.25; $0.holdReveal = 2.0 }.holdReveal == 1.5)
        #expect(clamped { $0.doubleTapWindow = 0.1 }.doubleTapWindow == 0.2)
        #expect(clamped { $0.doubleTapWindow = 0.9 }.doubleTapWindow == 0.5)
    }

    @Test func storeRoundTrips() {
        withStore { store, suite in
            var settings = store.settings
            settings.maxFrames = 7
            settings.recordTarget = .window(windowID: 42, title: "Doc")
            store.settings = settings

            let reopened = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
            #expect(reopened.settings.maxFrames == 7)
            #expect(reopened.settings.recordTarget == .window(windowID: 42, title: "Doc"))
        }
    }

    @Test func unreadableValueFallsBack() {
        withStore { store, suite in
            UserDefaults(suiteName: suite)!.set(Data("junk".utf8), forKey: SettingsStore.key)
            #expect(store.settings == Settings())
        }
    }

    @Test func gestureConfigMapsTimings() {
        var settings = Settings()
        settings.holdThreshold = 0.3
        settings.holdReveal = 0.9
        settings.doubleTapWindow = 0.25
        let config = settings.gestureConfig
        #expect(config.holdThreshold == 0.3)
        #expect(config.holdReveal == 0.9)
        #expect(config.doubleTapWindow == 0.25)
    }

    @Test func longEdgeFollowsCompact() {
        var settings = Settings()
        #expect(settings.longEdge == 1920)
        settings.compactFrames = true
        #expect(settings.longEdge == 1568)
    }

    @Test func retentionDays() {
        #expect(Settings.Retention.days7.days == 7)
        #expect(Settings.Retention.days30.days == 30)
        #expect(Settings.Retention.forever.days == nil)
    }
}
