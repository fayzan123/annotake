@testable import AnnotakeApp
import AnnotakeCore
import Foundation
import Testing

struct PillTextTests {
    @Test func holdText() {
        #expect(PillText.recording(mode: .hold, elapsed: 4, frames: 3, maxFrames: 20, trigger: .rightCommand)
                == "● 0:04 · 3 frames · release ⌘ to stop")
    }

    @Test func handsFreeText() {
        #expect(PillText.recording(mode: .handsFree, elapsed: 12, frames: 5, maxFrames: 20, trigger: .rightCommand)
                == "● 0:12 · 5 frames · double-tap ⌘ to stop · ⌘Esc cancels")
    }

    @Test func pastTheCapItKeepsTheBest() {
        #expect(PillText.recording(mode: .hold, elapsed: 34, frames: 27, maxFrames: 20, trigger: .rightCommand)
                == "● 0:34 · best 20 of 27 · release ⌘ to stop")
    }

    @Test func atTheCapItCountsNormally() {
        #expect(PillText.recording(mode: .hold, elapsed: 4, frames: 20, maxFrames: 20, trigger: .rightCommand)
                == "● 0:04 · 20 frames · release ⌘ to stop")
    }

    @Test func singularFrame() {
        #expect(PillText.recording(mode: .hold, elapsed: 1, frames: 1, maxFrames: 20, trigger: .rightCommand)
                == "● 0:01 · 1 frame · release ⌘ to stop")
    }

    @Test func optionAndFnTriggers() {
        #expect(PillText.recording(mode: .hold, elapsed: 4, frames: 3, maxFrames: 20, trigger: .rightOption)
                == "● 0:04 · 3 frames · release ⌥ to stop")
        #expect(PillText.recording(mode: .handsFree, elapsed: 12, frames: 5, maxFrames: 20, trigger: .rightOption)
                == "● 0:12 · 5 frames · double-tap ⌥ to stop · ⌥Esc cancels")
        #expect(PillText.recording(mode: .hold, elapsed: 4, frames: 3, maxFrames: 20, trigger: .fn)
                == "● 0:04 · 3 frames · release fn to stop")
        #expect(PillText.recording(mode: .handsFree, elapsed: 12, frames: 5, maxFrames: 20, trigger: .fn)
                == "● 0:12 · 5 frames · double-tap fn to stop · fn+Esc cancels")
    }

    @Test func messages() {
        #expect(PillText.message(.screenRecordingNeeded) == "Screen Recording permission needed")
        #expect(PillText.message(.couldNotStart) == "Couldn't start recording — try again")
        #expect(PillText.message(.cannotSave) == "Can't save to the captures folder — check the save location")
        #expect(PillText.message(.note("Window not found — recording your screen"))
                == "Window not found — recording your screen")
        #expect(PillText.message(.emailNeeded) == "Add your email to start recording")
    }

    /// The button each message offers. Open brings the email step forward; Open Settings opens System Settings.
    @Test func buttons() {
        #expect(PillButton(for: .emailNeeded) == .openEmail)
        #expect(PillButton(for: .screenRecordingNeeded) == .openSettings)
        #expect(PillButton(for: .couldNotStart) == nil)
        #expect(PillButton(for: .cannotSave) == nil)
        #expect(PillButton(for: .note("Window not found — recording your screen")) == nil)
        #expect(PillButton.openEmail.title == "Open")
        #expect(PillButton.openSettings.title == "Open Settings")
    }

    /// Open runs the action the pill was given. A pill that never shows is enough: only showMessage puts it on screen.
    @MainActor @Test func openRunsItsAction() {
        let pill = PillPanel()
        var opened = 0
        pill.onOpenEmail = { opened += 1 }
        pill.press(.openEmail)
        #expect(opened == 1)
        #expect(!pill.panel.isVisible)
    }

    /// A source file's lines, whole and trimmed, so that a line commented out doesn't count. A test looks its lines
    /// up before #expect or #require sees them, so that a failure names what's missing instead of printing the file.
    static func sourceLines(_ path: String) throws -> [String] {
        let url = try EmailConsentTests.repositoryRoot().appending(path: path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Only SessionController's init passes the pill's Open on to the controller's onOpenEmail, which AppDelegate sets,
    /// and no test builds the controller. Without it, Open would do nothing while recording waits for an address, and
    /// every other test would still pass.
    @Test func theControllerPassesOpenOn() throws {
        let lines = try Self.sourceLines("Sources/AnnotakeApp/SessionController.swift")
        let initializer = lines.firstIndex { $0.hasPrefix("init(settingsStore: SettingsStore,") }
        let start = try #require(initializer, "SessionController declares its init")
        let end = try #require(lines[start...].firstIndex(of: "}"), "its init ends")
        let passed = lines[start..<end].contains("pill.onOpenEmail = { [weak self] in self?.onOpenEmail?() }")
        #expect(passed, "the init passes the pill's Open on")
    }

    /// Only AppDelegate's line points the pill's Open at the email step, and no test launches the app. Without it,
    /// Open would do nothing while recording waits for an address, and every other test would still pass.
    @Test func theAppPointsOpenAtTheEmailStep() throws {
        let lines = try Self.sourceLines("Sources/AnnotakeApp/AppMain.swift")
        let delegate = lines.firstIndex { $0.hasPrefix("final class AppDelegate") }
        let start = try #require(delegate, "AppMain.swift declares AppDelegate")
        let wired = lines[start...].contains("controller.onOpenEmail = { [weak onboarding] in onboarding?.showForEmail() }")
        #expect(wired, "AppDelegate points the pill's Open at the email step")
    }
}
