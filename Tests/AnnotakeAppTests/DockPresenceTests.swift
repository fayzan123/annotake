import AppKit
@testable import AnnotakeApp
import Testing

/// Annotake is in the Dock and ⌘-Tab only while the first run or Settings is open, so a window behind another app can be
/// found again (Checkpoint 5).
@MainActor
struct DockPresenceTests {
    /// The policies a DockPresence sets, in order.
    final class Policies {
        var set: [NSApplication.ActivationPolicy] = []
    }

    static func dock() -> (DockPresence, Policies) {
        let policies = Policies()
        return (DockPresence(apply: { policies.set.append($0) }), policies)
    }

    @Test func theFirstWindowShownPutsAnnotakeInTheDock() {
        let (dock, policies) = Self.dock()
        dock.shown(NSObject())
        #expect(policies.set == [.regular])
    }

    @Test func anotherWindowOrTheSameOneAgainChangesNothing() {
        let (dock, policies) = Self.dock()
        let first = NSObject(), second = NSObject()
        dock.shown(first)
        dock.shown(first)
        dock.shown(second)
        #expect(policies.set == [.regular])
    }

    @Test func onlyTheLastWindowClosedTakesItOut() {
        let (dock, policies) = Self.dock()
        let first = NSObject(), second = NSObject()
        dock.shown(first)
        dock.shown(second)
        dock.closed(first)
        #expect(policies.set == [.regular])
        dock.closed(second)
        #expect(policies.set == [.regular, .accessory])
    }

    @Test func aWindowNeverShownChangesNothingAsItCloses() {
        let (dock, policies) = Self.dock()
        dock.closed(NSObject())
        #expect(policies.set.isEmpty)
    }

    @Test func aWindowShownAgainPutsItBack() {
        let (dock, policies) = Self.dock()
        let window = NSObject()
        dock.shown(window)
        dock.closed(window)
        dock.shown(window)
        #expect(policies.set == [.regular, .accessory, .regular])
    }

    /// Only the app's own DockPresence changes NSApp, which no test may: it swaps the main menu with the policy, so
    /// ⌘Q, ⌘W, and ⌘, work only while Annotake is in the Dock (MainMenuTests).
    @Test func theAppsDockPresenceSwapsTheMainMenuToo() throws {
        let lines = try PillTextTests.sourceLines("Sources/AnnotakeApp/DockPresence.swift")
        #expect(lines.contains("NSApp.mainMenu = MainMenu.make(inDock: policy == .regular)"))
        #expect(lines.contains("NSApp.setActivationPolicy(policy)"))
    }

    /// Only the two window controllers tell the Dock, and no test opens their windows. Without these lines, Annotake
    /// would never be in the Dock, and every other test would still pass.
    @Test func theFirstRunAndSettingsTellTheDock() throws {
        for path in ["Sources/AnnotakeApp/Onboarding.swift", "Sources/AnnotakeApp/SettingsWindow.swift"] {
            let lines = try PillTextTests.sourceLines(path)
            #expect(lines.contains("if let window { DockPresence.shared.shown(window) }"), "\(path) shows its window")
            #expect(lines.contains("if let window { DockPresence.shared.closed(window) }"), "\(path) closes it")
        }
    }
}
