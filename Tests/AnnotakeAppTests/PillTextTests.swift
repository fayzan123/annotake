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
    }

    /// The button each message offers: Open Settings opens System Settings, and only for Screen Recording.
    @Test func buttons() {
        #expect(PillButton(for: .screenRecordingNeeded) == .openSettings)
        #expect(PillButton(for: .couldNotStart) == nil)
        #expect(PillButton(for: .cannotSave) == nil)
        #expect(PillButton(for: .note("Window not found — recording your screen")) == nil)
        #expect(PillButton.openSettings.title == "Open Settings")
    }

    /// A source file's lines, whole and trimmed, so that a line commented out doesn't count. A test looks its lines
    /// up before #expect or #require sees them, so that a failure names what's missing instead of printing the file.
    static func sourceLines(_ path: String) throws -> [String] {
        let url = try EmailConsentTests.repositoryRoot().appending(path: path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
