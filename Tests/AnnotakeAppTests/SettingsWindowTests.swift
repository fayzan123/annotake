@testable import AnnotakeApp
import Foundation
import Testing

struct SettingsWindowTests {
    @Test func millisecondsFormatting() {
        #expect(SettingsText.milliseconds(0.25) == "250 ms")
        #expect(SettingsText.milliseconds(0.8) == "800 ms")
    }

    @Test func fnWarningsVerbatim() {
        #expect(SettingsText.fnWarnings == [
            #"macOS's "Press 🌐 key to" setting must be "Do Nothing"."#,
            "Dictation apps (Wispr Flow, Handy) often use fn already.",
            "Some third-party keyboards handle fn themselves and never send it to macOS, "
                + "so fn works reliably only on Apple keyboards.",
        ])
    }

    /// Every setting changed from its default.
    static let changed: Settings = {
        var settings = Settings()
        settings.triggerKey = .fn
        settings.sounds = false
        settings.launchAtLogin = false
        settings.recordTarget = .window(windowID: 7, title: "Doc")
        settings.maxFrames = 5
        settings.compactFrames = true
        settings.captionStrip = false
        settings.clickMarkers = false
        settings.saveLocation = URL(fileURLWithPath: "/tmp/elsewhere")
        settings.retention = .forever
        settings.holdThreshold = 0.26
        settings.holdReveal = 1.5
        settings.doubleTapWindow = 0.25
        settings.saveRawSessions = true
        return settings
    }()

    @Test func restoreDefaultsResetsOnlyItsTab() {
        var general = Self.changed
        general.triggerKey = .rightCommand
        general.sounds = true
        general.launchAtLogin = true
        #expect(SettingsTab.general.restoringDefaults(of: Self.changed) == general)

        var record = Self.changed
        record.recordTarget = .cursorScreen
        #expect(SettingsTab.record.restoringDefaults(of: Self.changed) == record)

        var output = Self.changed
        output.maxFrames = 20
        output.compactFrames = false
        output.captionStrip = true
        output.clickMarkers = true
        output.saveLocation = Settings.defaultSaveLocation
        output.retention = .days30
        #expect(SettingsTab.output.restoringDefaults(of: Self.changed) == output)

        var advanced = Self.changed
        advanced.holdThreshold = 0.25
        advanced.holdReveal = 0.8
        advanced.doubleTapWindow = 0.3
        advanced.saveRawSessions = false
        #expect(SettingsTab.advanced.restoringDefaults(of: Self.changed) == advanced)

        #expect(SettingsTab.permissions.restoringDefaults(of: Self.changed) == Self.changed)
    }

    /// Each setting belongs to a tab, so restoring every tab gives the defaults.
    @Test func everySettingHasATab() {
        let restored = SettingsTab.allCases.reduce(Self.changed) { $1.restoringDefaults(of: $0) }
        #expect(restored == Settings())
    }

    @Test func restoreButtonOnTabsWithSettings() {
        #expect(SettingsTab.allCases.filter(\.hasSettings) == [.general, .record, .output, .advanced])
    }

    /// The button is greyed out while its tab is at the defaults; another tab's change doesn't count.
    @Test func atDefaultsPerTab() {
        #expect(SettingsTab.allCases.allSatisfy { $0.isAtDefaults(Settings()) })
        var settings = Settings()
        settings.holdThreshold = 0.26
        #expect(!SettingsTab.advanced.isAtDefaults(settings))
        #expect(SettingsTab.general.isAtDefaults(settings))
        #expect(SettingsTab.output.isAtDefaults(settings))
    }

    /// A restore is saved and applied like any other change.
    @MainActor @Test func modelRestoresDefaults() {
        let suite = "annotake-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.settings = Self.changed
        let model = SettingsModel(store: store)
        var changes: [(Settings, Settings)] = []
        model.onChange = { changes.append(($0, $1)) }

        model.restoreDefaults(.advanced)

        #expect(store.settings == SettingsTab.advanced.restoringDefaults(of: Self.changed))
        #expect(model.settings == store.settings)
        #expect(changes.count == 1)
        #expect(changes.first?.0 == Self.changed)
        #expect(changes.first?.1 == store.settings)

        model.restoreDefaults(.advanced)
        #expect(changes.count == 1)
    }

    @Test func permissionPaneURLs() {
        #expect(PermissionPane.screenRecording.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        #expect(PermissionPane.inputMonitoring.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        #expect(PermissionPane.accessibility.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}
