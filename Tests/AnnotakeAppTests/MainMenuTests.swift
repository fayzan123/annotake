import AppKit
@testable import AnnotakeApp
import Carbon.HIToolbox
import SwiftUI
import Testing

/// The main menu: the application menu, Edit, and Window. It shows only while Annotake is in the Dock (DockPresence),
/// but a text field gets ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z, and ⇧⌘Z only from its key equivalents: without them, ⌘V in the email step
/// does nothing.
@MainActor
struct MainMenuTests {
    /// A menu sends its item's action through NSApp, which the app always has. A test process has none until something
    /// makes it, and with none the action goes nowhere, though the key still counts as handled. (A test process may
    /// never activate: nothing shows.)
    init() {
        _ = NSApplication.shared
    }

    /// Records the actions sent to it.
    final class Recorder: NSObject {
        var actions: [String] = []
        @objc func undo(_ sender: Any?) { actions.append("undo:") }
        @objc func redo(_ sender: Any?) { actions.append("redo:") }
        @objc func cut(_ sender: Any?) { actions.append("cut:") }
        @objc func copy(_ sender: Any?) { actions.append("copy:") }
        @objc func paste(_ sender: Any?) { actions.append("paste:") }
        @objc func selectAll(_ sender: Any?) { actions.append("selectAll:") }
    }

    static func edit(_ menu: NSMenu) throws -> NSMenu {
        try #require(menu.items.first { $0.title == "Edit" }?.submenu)
    }

    /// A key press as macOS reports it: `characters` without Shift's effect under ⌘, `charactersIgnoringModifiers`
    /// with it (⇧⌘Z is "z" and "Z").
    static func press(_ characters: String, ignoring: String, _ keyCode: Int,
                      _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: ignoring, isARepeat: false,
                         keyCode: UInt16(keyCode))!
    }

    /// The application menu first, as in every main menu, then Edit, then Window. Each item goes to the first
    /// responder: NSApp takes About and Quit, the key window Close, and AppDelegate, at the chain's end, Settings….
    @Test func inTheDockItHoldsTheApplicationMenuThenEditThenWindow() throws {
        let menu = MainMenu.make(inDock: true)
        #expect(menu.items.map(\.title) == ["Annotake", "Edit", "Window"])
        let expected: [(menu: String, items: [(title: String, action: String, key: String)?])] = [
            ("Annotake", [("About Annotake", "orderFrontStandardAboutPanel:", ""), nil, ("Settings…", "showSettings:", ","),
                  nil, ("Quit Annotake", "terminate:", "q")]),
            ("Window", [("Close", "performClose:", "w")]),
        ]
        for (title, items) in expected {
            let submenu = try #require(menu.items.first { $0.title == title }?.submenu, "\(title)")
            #expect(submenu.items.count == items.count, "\(title)")
            for (item, expected) in zip(submenu.items, items) {
                guard let expected else {
                    #expect(item.isSeparatorItem)
                    continue
                }
                #expect(item.title == expected.title)
                #expect(item.action.map(NSStringFromSelector) == expected.action, "\(expected.title)")
                #expect(item.keyEquivalent == expected.key, "\(expected.title)")
                #expect(item.keyEquivalentModifierMask == .command, "\(expected.title)")
                #expect(item.target == nil, "\(expected.title) goes to the first responder")
            }
        }
        #expect(AppDelegate.instancesRespond(to: Selector(("showSettings:"))), "AppDelegate opens Settings")
    }

    /// In the menu bar alone, an empty application menu and Edit, as before Annotake was ever in the Dock. The
    /// filmstrip and the frame viewer take keys without making Annotake the active app, so the menu bar shows another
    /// app's menus: ⌘Q there must not quit Annotake, nor ⌘W or ⌘, do anything.
    @Test func inTheMenuBarAloneItHoldsEditAlone() throws {
        let menu = MainMenu.make()
        #expect(menu.items.map(\.title) == ["Annotake", "Edit"])
        #expect(try #require(menu.items.first?.submenu).items.isEmpty)
        for (name, key, keyCode) in [("⌘Q", "q", kVK_ANSI_Q), ("⌘W", "w", kVK_ANSI_W), ("⌘,", ",", kVK_ANSI_Comma)] {
            #expect(!menu.performKeyEquivalent(with: Self.press(key, ignoring: key, keyCode, .command)), "\(name)")
        }
    }

    /// Edit's items, each to the first responder.
    @Test func editHoldsTheEditingKeysForTheFirstResponder() throws {
        let menu = MainMenu.make()
        let expected: [(title: String, action: String, key: String, modifiers: NSEvent.ModifierFlags)?] = [
            ("Undo", "undo:", "z", .command),
            ("Redo", "redo:", "Z", [.command, .shift]),
            nil,
            ("Cut", "cut:", "x", .command),
            ("Copy", "copy:", "c", .command),
            ("Paste", "paste:", "v", .command),
            ("Select All", "selectAll:", "a", .command),
        ]
        let items = try Self.edit(menu).items
        #expect(items.count == expected.count)
        for (item, expected) in zip(items, expected) {
            guard let expected else {
                #expect(item.isSeparatorItem)
                continue
            }
            #expect(item.title == expected.title)
            #expect(item.action.map(NSStringFromSelector) == expected.action, "\(expected.title)")
            #expect(item.keyEquivalent == expected.key, "\(expected.title)")
            #expect(item.keyEquivalentModifierMask == expected.modifiers, "\(expected.title)")
            #expect(item.target == nil, "\(expected.title) goes to the first responder")
        }
    }

    /// Each key reaches its action, ⇧⌘Z included, and no other key reaches any: typing stays typing.
    @Test func eachKeyReachesItsActionAndNoOtherKeyDoes() throws {
        let menu = MainMenu.make()
        let recorder = Recorder()
        for item in try Self.edit(menu).items where !item.isSeparatorItem { item.target = recorder }
        let presses: [(name: String, event: NSEvent, action: String?)] = [
            ("⌘Z", Self.press("z", ignoring: "z", kVK_ANSI_Z, .command), "undo:"),
            ("⇧⌘Z", Self.press("z", ignoring: "Z", kVK_ANSI_Z, [.command, .shift]), "redo:"),
            ("⌘X", Self.press("x", ignoring: "x", kVK_ANSI_X, .command), "cut:"),
            ("⌘C", Self.press("c", ignoring: "c", kVK_ANSI_C, .command), "copy:"),
            ("⌘V", Self.press("v", ignoring: "v", kVK_ANSI_V, .command), "paste:"),
            ("⌘A", Self.press("a", ignoring: "a", kVK_ANSI_A, .command), "selectAll:"),
            ("⌘Z with Caps Lock", Self.press("z", ignoring: "z", kVK_ANSI_Z, [.command, .capsLock]), "undo:"),
            ("v", Self.press("v", ignoring: "v", kVK_ANSI_V, []), nil),
            ("⇧⌘V", Self.press("v", ignoring: "V", kVK_ANSI_V, [.command, .shift]), nil),
            ("⌥⌘V", Self.press("√", ignoring: "v", kVK_ANSI_V, [.command, .option]), nil),
            ("⌃⌘Z", Self.press("\u{1A}", ignoring: "z", kVK_ANSI_Z, [.command, .control]), nil),
        ]
        for press in presses {
            recorder.actions = []
            let handled = menu.performKeyEquivalent(with: press.event)
            #expect(handled == (press.action != nil), "\(press.name)")
            #expect(recorder.actions == (press.action.map { [$0] } ?? []), "\(press.name)")
        }
    }

    /// The email step's own field, in a window that's never shown: its editor takes Cut, Copy, Paste, and Select All,
    /// the window takes Undo and Redo, and ⌘A through the menu selects what's typed. In the app, the window is key and
    /// the items, with no target, find the editor themselves.
    @Test func theKeysReachTheEmailField() throws {
        let viewModel = OnboardingViewModelTests.viewModel(OnboardingModel.emailOnly(), signup: nil)
        viewModel.emailDraft = "sam@example.com"
        let hosting = NSHostingView(rootView: OnboardingView(viewModel: viewModel))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: OnboardingView.width, height: OnboardingView.height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let field = try #require(Self.textField(in: hosting))
        #expect(window.makeFirstResponder(field))
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.string == "sam@example.com")

        let menu = MainMenu.make()
        for item in try Self.edit(menu).items where !item.isSeparatorItem {
            let action = try #require(item.action)
            let responder: NSResponder = ["undo:", "redo:"].contains(NSStringFromSelector(action)) ? window : editor
            #expect(responder.responds(to: action), "\(item.title)")
        }

        let selectAll = try #require(try Self.edit(menu).items.first { $0.title == "Select All" })
        selectAll.target = editor
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        #expect(menu.performKeyEquivalent(with: Self.press("a", ignoring: "a", kVK_ANSI_A, .command)))
        #expect(editor.selectedRange() == NSRange(location: 0, length: editor.string.utf16.count))
    }

    /// Only AppDelegate's one line puts the menu in place, and no test launches the app, so the line is pinned in
    /// AppMain.swift's text: in AppDelegate, not --selftest's or --render-ui's delegate, and before the first run can
    /// show. Without it, ⌘V in the email step would do nothing, and every other test would still pass.
    @Test func theAppInstallsItBeforeTheFirstRunCanShow() throws {
        let url = try EmailConsentTests.repositoryRoot().appending(path: "Sources/AnnotakeApp/AppMain.swift")
        // Whole lines, trimmed, so that a line commented out doesn't count. Each index is found before #require sees
        // it, so that a failure names what's missing instead of printing the file.
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let delegate = lines.firstIndex { $0.hasPrefix("final class AppDelegate") }
        let start = try #require(delegate, "AppMain.swift declares AppDelegate")
        // From AppDelegate on: the other two delegates come before it.
        let install = lines[start...].firstIndex(of: "NSApp.mainMenu = MainMenu.make()")
        let firstRun = lines[start...].firstIndex(of: "onboarding.showIfNeeded()")
        let installed = try #require(install, "AppDelegate installs the menu")
        let shown = try #require(firstRun, "AppDelegate shows the first run")
        #expect(installed < shown, "the menu is in place before the first run can show")
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { textField(in: $0) }.first
    }
}
