@testable import AnnotakeApp
import Combine
import Foundation
import Testing

/// The Settings window's text and models. The email tests build their EmailSignup with SignupHarness, which stands in
/// for the network, so nothing here posts for real.
@Suite(.timeLimit(.minutes(1)))
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

    // MARK: - The email (email list design §3.3)

    static let sam = EmailRecord(address: "Sam@Example.com", news: true, consent: EmailConsent.id,
                                 savedAt: Date(timeIntervalSinceReferenceDate: 813_456_789), sent: true)

    /// The row's words, as the plan has them, Add… for a first address, and the Change… sheet's title.
    @Test func theEmailRowsWords() {
        #expect(SettingsText.emailRow == "Email")
        #expect(SettingsText.addEmail == "Add…")
        #expect(SettingsText.changeEmail == "Change…")
        #expect(SettingsText.noEmail == "Not set")
        #expect(SettingsText.changeEmailTitle == "Change your email")
    }

    /// General's Email row: the saved address, as it was saved, or Not set with none.
    @Test func theEmailRowShowsTheSavedAddressOrNotSet() {
        #expect(SettingsText.email(Self.sam) == "Sam@Example.com")
        #expect(SettingsText.email(nil) == "Not set")
    }

    /// With no address saved, the row's button is Add…, which opens the email step, so a first address always comes
    /// with the notice, the box, and the footer. With one, it's Change…, which opens the sheet.
    @Test func theEmailRowsButtonAddsAFirstAddressAndChangesOne() {
        #expect(EmailRowButton(record: nil) == .add)
        #expect(EmailRowButton(record: nil).title == "Add…")
        #expect(EmailRowButton(record: Self.sam) == .change)
        #expect(EmailRowButton(record: Self.sam).title == "Change…")
    }

    /// Add… runs the action General was given, which AppDelegate points at the email step; Change… opens its sheet
    /// instead. Each goes by the address saved when it's pressed.
    @MainActor @Test func addRunsItsAction() throws {
        let harness = SignupHarness()
        let model = SettingsModel(store: SettingsStore(defaults: harness.defaults))
        var added = 0
        GeneralTab(model: model, signup: harness.makeSignup(), addEmail: { added += 1 }).pressEmailButton()
        #expect(added == 1)

        try harness.store(Self.sam)
        GeneralTab(model: model, signup: harness.makeSignup(), addEmail: { added += 1 }).pressEmailButton()
        #expect(added == 1, "Change… opens the sheet")
    }

    /// The row reads the signup's record, which GeneralTab observes and the signup publishes, so it follows the signup
    /// while Settings is open: a save shows the address, and a 400 that clears it shows Not set again.
    @MainActor @Test func theEmailRowFollowsTheSignup() async {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        var rows: [String] = []
        let watching = signup.$record.sink { rows.append(SettingsText.email($0)) }
        defer { watching.cancel() }
        #expect(rows == ["Not set"])
        harness.answers = [.invalid]

        signup.save(address: "sam@example.com", news: false)
        #expect(rows.last == "sam@example.com")
        await signup.settle()

        #expect(rows.last == "Not set")
        #expect(SettingsText.email(signup.record) == "Not set")
    }

    /// GeneralTab observes the signup, rather than reading it once, so the row redraws as the record changes. Held as a
    /// plain property, the row would keep showing an address a 400 has cleared. (By the wrapper's name: importing
    /// SwiftUI here would make Settings ambiguous.)
    @MainActor @Test func generalObservesTheSignup() {
        let harness = SignupHarness()
        let tab = GeneralTab(model: SettingsModel(store: SettingsStore(defaults: harness.defaults)),
                             signup: harness.makeSignup(), addEmail: {})
        let wrappers = Mirror(reflecting: tab).children.map { String(describing: type(of: $0.value)) }
        #expect(wrappers.contains("ObservedObject<EmailSignup>"), "\(wrappers)")
    }

    /// Change… opens the field with the saved address in it, to fix in place. With none saved, the row offers Add…
    /// instead, so the sheet never starts empty.
    @Test func theChangeSheetStartsWithTheSavedAddress() {
        #expect(EmailChange(record: Self.sam).draft == "Sam@Example.com")
        #expect(EmailChange(record: nil).draft == "")
    }

    /// Save is greyed out until what's typed is an address the site takes, as the email step's Continue is.
    @Test func saveWaitsForAPlausibleAddress() {
        var change = EmailChange(record: nil)
        #expect(!change.canSave)
        change.draft = "not-an-email"
        #expect(!change.canSave)
        change.draft = "sam@example.com"
        #expect(change.canSave)
        for draft in ["", "sam", "sam@example", "sam @example.com", "sam@example.com\nbcc@example.com",
                      "  Sam@Example.COM "] {
            change.draft = draft
            #expect(change.canSave == EmailConsent.isPlausible(draft), "\(draft)")
        }
    }

    /// Save calls change(address:) with the cleaned address: it's saved at once with the choice and the wording already
    /// on file, Settings shows it, and the post goes in the background (design §3.3).
    @MainActor @Test func saveChangesToTheCleanedAddress() async throws {
        let harness = SignupHarness()
        try harness.store(Self.sam)
        let signup = harness.makeSignup()
        var changes = 0
        signup.onChange = { changes += 1 }
        harness.answers = [.sent]
        var change = EmailChange(record: signup.record)
        change.draft = "  Kim@Example.org \n"

        #expect(change.save(to: signup), "the sheet closes")

        #expect(harness.stored == EmailRecord(address: "Kim@Example.org", news: true, consent: EmailConsent.id,
                                              savedAt: harness.now, sent: false))
        #expect(SettingsText.email(signup.record) == "Kim@Example.org")
        #expect(changes == 1)
        #expect(harness.requests.isEmpty, "Save doesn't wait for the post")
        await signup.settle()
        try #require(harness.requests.count == 1)
        #expect(try EmailSignupTests.body(of: harness.requests[0])
                == .init(email: "Kim@Example.org", news: true, consent: EmailConsent.id, appVersion: "0.3.0 (120)"))
        #expect(harness.stored?.sent == true)
        #expect(harness.logged == ["email: sent"])
    }

    /// Return in the field reaches Save's action even while Save is greyed out: an address the site wouldn't take
    /// saves nothing, and the sheet stays open.
    @MainActor @Test func saveTurnsAwayAnImplausibleAddress() async throws {
        let harness = SignupHarness()
        try harness.store(Self.sam)
        let signup = harness.makeSignup()
        var change = EmailChange(record: signup.record)
        for draft in ["", "not-an-email", "kim@example", "kim@example.org\nbcc@example.org"] {
            change.draft = draft
            #expect(!change.save(to: signup), "\(draft)")
        }
        await signup.settle()
        #expect(harness.stored == Self.sam)
        #expect(SettingsText.email(signup.record) == "Sam@Example.com")
        #expect(harness.requests.isEmpty)
    }

    /// The saved address again, as it opened or in other capitals and padding, changes nothing: no store, no post, and
    /// the row keeps the address as it was saved. The sheet closes.
    @MainActor @Test func saveWithTheSameAddressChangesNothing() async throws {
        let harness = SignupHarness()
        try harness.store(Self.sam)
        let signup = harness.makeSignup()
        var changes = 0
        signup.onChange = { changes += 1 }
        var change = EmailChange(record: signup.record)
        #expect(change.save(to: signup))
        change.draft = "  sam@EXAMPLE.com "
        #expect(change.save(to: signup))
        await signup.settle()

        #expect(harness.stored == Self.sam)
        #expect(changes == 0)
        #expect(harness.requests.isEmpty)
        #expect(SettingsText.email(signup.record) == "Sam@Example.com")
    }

    /// A change back to an address the site has already taken from this Mac is saved as sent, and posts nothing, so the
    /// first run's choice is never sent again for it.
    @MainActor @Test func aChangeBackToAnAddressTheSiteHasPostsNothing() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.sent, .sent]
        signup.save(address: "sam@example.com", news: true)
        await signup.settle()
        var change = EmailChange(record: signup.record)
        change.draft = "kim@example.org"
        #expect(change.save(to: signup))
        await signup.settle()
        harness.now += 3_600

        change = EmailChange(record: signup.record)
        #expect(change.draft == "kim@example.org")
        change.draft = "Sam@Example.com"
        #expect(change.save(to: signup))
        await signup.settle()

        #expect(harness.stored == EmailRecord(address: "Sam@Example.com", news: true, consent: EmailConsent.id,
                                              savedAt: harness.now, sent: true))
        #expect(SettingsText.email(signup.record) == "Sam@Example.com")
        #expect(try EmailSignupTests.emails(harness.requests) == ["sam@example.com", "kim@example.org"])
        #expect(harness.logged == ["email: sent", "email: sent"])
    }

    /// The sheet opens only with an address saved, but a 400 can clear it while the sheet is open. Save then saves
    /// nothing, and the sheet closes, leaving Not set and Add…: a first address comes from the email step, with its
    /// notice and box, never from here under wording the person didn't see.
    @MainActor @Test func saveAfterTheAddressWasClearedSavesNothing() async throws {
        let harness = SignupHarness()
        let signup = harness.makeSignup()
        harness.answers = [.invalid]
        signup.save(address: "sam@example.com", news: true)
        var change = EmailChange(record: signup.record)
        await signup.settle()
        #expect(!signup.hasAddress, "the site refused it")
        var changes = 0
        signup.onChange = { changes += 1 }

        change.draft = "kim@example.org"
        #expect(change.save(to: signup), "the sheet closes")
        await signup.settle()

        #expect(harness.stored == nil)
        #expect(SettingsText.email(signup.record) == "Not set")
        #expect(changes == 0)
        #expect(try EmailSignupTests.emails(harness.requests) == ["sam@example.com"])
        #expect(harness.logged == ["email: invalid"])
    }

    /// The email isn't a setting: a saved address doesn't count against Restore Defaults, and restoring every tab's
    /// defaults leaves it, on the Mac and in the row.
    @MainActor @Test func restoreDefaultsLeavesTheEmail() throws {
        let harness = SignupHarness()
        try harness.store(Self.sam)
        let signup = harness.makeSignup()
        let store = SettingsStore(defaults: harness.defaults)
        #expect(SettingsTab.allCases.allSatisfy { $0.isAtDefaults(SettingsModel(store: store).settings) })

        store.settings = Self.changed
        let model = SettingsModel(store: store)
        for tab in SettingsTab.allCases { model.restoreDefaults(tab) }

        #expect(model.settings == Settings())
        #expect(harness.stored == Self.sam)
        #expect(signup.record == Self.sam)
        #expect(harness.requests.isEmpty)
    }

    // MARK: - The wiring

    /// Two lines in Sources build an EmailSignup: AppDelegate's, the app's one signup, which posts; and the UI
    /// snapshots', whose post answers retry later without a request, whose retries never fire, and which logs nothing.
    /// --render-ui runs inside the release app, so with the real post, a snapshot of a state after Save would send to
    /// annotake.app from a developer's Mac. Tests build theirs with SignupHarness, which EmailSignupTests checks.
    @Test func onlyTheAppAndTheSnapshotsBuildAnEmailSignup() throws {
        // EmailSignupTests' pattern. Its scan of Tests/ reads this file's strings too, so the expectations below hold
        // only what follows each construction's opening parenthesis.
        let construction = #/\bEmailSignup\s*(\.init\s*)?\(/#
        let sources = try EmailConsentTests.repositoryRoot().appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var built: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
                for match in line.matches(of: construction) {
                    built.append("\(url.lastPathComponent): \(line[match.range.upperBound...])")
                }
            }
        }
        #expect(built.sorted() == [
            "AppMain.swift: defaults: .standard)",
            "UISnapshots.swift: defaults: defaults, post: { _ in .retryLater }, schedule: { _, _ in }, "
                + "report: { _ in })",
        ])

        // The app's is AppDelegate's, not --selftest's or --render-ui's delegate's, which come before it.
        let lines = try PillTextTests.sourceLines("Sources/AnnotakeApp/AppMain.swift")
        let delegate = lines.firstIndex { $0.hasPrefix("final class AppDelegate") }
        let app = lines.firstIndex { $0.contains(construction) }
        let start = try #require(delegate, "AppMain.swift declares AppDelegate")
        let line = try #require(app, "AppMain.swift builds the app's signup")
        #expect(line > start, "AppDelegate builds the app's signup")
    }

    /// Only AppDelegate's call gives the Settings window the app's one signup, and no test launches the app. Given a
    /// second signup, the Email row wouldn't follow the email step's save or a 400, and a Change… while the email step's
    /// post was in flight would post the new address twice, once from each.
    @Test func theAppGivesSettingsItsSignup() throws {
        let lines = try PillTextTests.sourceLines("Sources/AnnotakeApp/AppMain.swift")
        let delegate = lines.firstIndex { $0.hasPrefix("final class AppDelegate") }
        let start = try #require(delegate, "AppMain.swift declares AppDelegate")
        let made = lines[start...].firstIndex(of: "let settingsWindow = SettingsWindowController(")
        let call = try #require(made, "AppDelegate makes the Settings window")
        let kept = lines[call...].firstIndex(of: "self.settingsWindow = settingsWindow")
        let end = try #require(kept, "AppDelegate keeps the Settings window")
        let given = lines[call..<end].contains("signup: signup)")
        #expect(given, "AppDelegate gives the Settings window the app's signup")
    }

    /// Only the Settings window passes its onAddEmail on to General's Add…, and no test opens the window. It's read
    /// when Add… is pressed, since AppDelegate sets it once the onboarding exists, after the window controller. Without
    /// these lines, Add… would do nothing, and every other test would still pass.
    @Test func theSettingsWindowPassesAddOn() throws {
        let lines = try PillTextTests.sourceLines("Sources/AnnotakeApp/SettingsWindow.swift")
        let make = lines.firstIndex { $0.hasPrefix("private func makeWindow() -> NSWindow") }
        let start = try #require(make, "SettingsWindowController makes its window")
        let made = lines[start...].contains("let addEmail: () -> Void = { [weak self] in self?.onAddEmail?() }")
        let passed = lines[start...].contains("addEmail: addEmail))")
        let general = "case .general: host(GeneralTab(model: model, signup: signup, addEmail: addEmail))"
        #expect(made, "the window reads onAddEmail when Add… is pressed")
        #expect(passed, "the window gives each tab's page that action")
        #expect(lines.contains(general), "General gets it")
    }

    /// Only AppDelegate's line points General's Add… at the email step, and no test launches the app. Without it, Add…
    /// would do nothing, and every other test would still pass.
    @Test func theAppPointsAddAtTheEmailStep() throws {
        let lines = try PillTextTests.sourceLines("Sources/AnnotakeApp/AppMain.swift")
        let delegate = lines.firstIndex { $0.hasPrefix("final class AppDelegate") }
        let start = try #require(delegate, "AppMain.swift declares AppDelegate")
        let made = lines[start...].firstIndex { $0.hasPrefix("let onboarding = OnboardingController(") }
        let onboarding = try #require(made, "AppDelegate makes the onboarding")
        let wired = lines[onboarding...].contains(
            "settingsWindow.onAddEmail = { [weak onboarding] in onboarding?.showForEmail() }")
        #expect(wired, "AppDelegate points Add… at the email step, once the onboarding exists")
    }

    /// Only AppDelegate's line sends, at launch, an address saved but not yet sent, as after an offline Continue and a
    /// quit (Review Focus 3). No test launches the app, and without the line every other test would still pass.
    @Test func theAppSendsASavedAddressAtLaunch() throws {
        let lines = try PillTextTests.sourceLines("Sources/AnnotakeApp/AppMain.swift")
        let delegate = lines.firstIndex { $0.hasPrefix("final class AppDelegate") }
        let start = try #require(delegate, "AppMain.swift declares AppDelegate")
        let resumed = lines[start...].contains("signup.resume()")
        #expect(resumed, "AppDelegate sends a saved address at launch")
    }
}
