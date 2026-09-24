import CoreGraphics
import FlipbookCore
import FlipbookInput
import Testing

/// A keyboard layout from a dictionary; missing keycodes have no character.
struct FakeLayout: KeyboardLayout {
    var characters: [UInt16: String]

    func character(forKeycode keycode: UInt16) -> String? {
        characters[keycode]
    }
}

struct KeyClassifierTests {
    let layout = FakeLayout(characters: [0: "a", 1: "s", 8: "c", 14: "e", 17: "t", 40: "k", 49: " ", 48: "\t"])

    func classify(_ keycode: UInt16, _ flags: CGEventFlags = [], isRepeat: Bool = false,
                  layout: KeyboardLayout? = nil) -> InputEventKind? {
        KeyClassifier.classify(keycode: keycode, flags: flags, isRepeat: isRepeat, layout: layout ?? self.layout)
    }

    @Test func commandS() {
        #expect(classify(1, .maskCommand) == .shortcut("⌘S"))
    }

    @Test func modifierOrder() {
        #expect(classify(40, [.maskControl, .maskAlternate, .maskShift, .maskCommand]) == .shortcut("⌃⌥⇧⌘K"))
    }

    @Test func shiftCommandT() {
        #expect(classify(17, [.maskShift, .maskCommand]) == .shortcut("⇧⌘T"))
    }

    @Test func controlC() {
        #expect(classify(8, .maskControl) == .shortcut("⌃C"))
    }

    @Test func returnAndEnter() {
        #expect(classify(36, .maskCommand) == .shortcut("⌘↩"))
        #expect(classify(36) == .keyReturn)
        #expect(classify(76) == .keyReturn)
    }

    @Test func escape() {
        #expect(classify(53) == .keyEscape)
    }

    @Test func typingKeys() {
        for keycode: UInt16 in [0, 49, 48, 51] {
            #expect(classify(keycode) == .keyTyped(field: nil), "keycode \(keycode)")
        }
    }

    @Test func optionLetterIsTyping() {
        #expect(classify(14, .maskAlternate) == .keyTyped(field: nil))
    }

    @Test func navigationIgnored() {
        #expect(classify(125) == nil)
        #expect(classify(96) == nil)
        #expect(classify(125, .maskCommand) == .shortcut("⌘↓"))
    }

    @Test func repeatsAndModifiersIgnored() {
        #expect(classify(0, isRepeat: true) == nil)
        #expect(classify(1, .maskCommand, isRepeat: true) == nil)
        #expect(classify(56) == nil)
    }

    @Test func unnamedKeyFallsBackToANSI() {
        #expect(classify(0, .maskCommand, layout: FakeLayout(characters: [:])) == .shortcut("⌘A"))
        #expect(classify(50, .maskCommand, layout: FakeLayout(characters: [50: ""])) == .shortcut("⌘`"))
        #expect(classify(93, .maskCommand, layout: FakeLayout(characters: [:])) == .shortcut("⌘Key 93"))
    }

    @Test func triggerKeyBits() {
        #expect(TriggerKeys.isDown(.rightCommand, flags: CGEventFlags(rawValue: 0x10).union(.maskCommand)))
        #expect(!TriggerKeys.isDown(.rightCommand, flags: CGEventFlags(rawValue: 0x08).union(.maskCommand)))
        #expect(TriggerKeys.isDown(.rightOption, flags: CGEventFlags(rawValue: 0x40).union(.maskAlternate)))
        #expect(!TriggerKeys.isDown(.rightOption, flags: CGEventFlags(rawValue: 0x20).union(.maskAlternate)))
        #expect(TriggerKeys.isDown(.fn, flags: .maskSecondaryFn))
        #expect(!TriggerKeys.isDown(.fn, flags: []))
        #expect([TriggerKey.rightCommand, .rightOption, .fn].map(TriggerKeys.keycode(for:)) == [54, 61, 63])
        #expect(TriggerKeys.modifierFlag(for: .rightOption) == .maskAlternate)
    }

    @Test func scrollFraction() {
        #expect(PointerClassifier.scrollFraction(pointDeltaX: 0, pointDeltaY: 450, targetHeightPoints: 900) == 0.5)
        #expect(PointerClassifier.scrollFraction(pointDeltaX: 300, pointDeltaY: 400, targetHeightPoints: 1000) == 0.5)
    }

    @Test func buttons() {
        #expect(PointerClassifier.button(for: .leftMouseDown) == .left)
        #expect(PointerClassifier.button(for: .rightMouseUp) == .right)
        #expect(PointerClassifier.button(for: .otherMouseDown) == .other)
        #expect(PointerClassifier.button(for: .keyDown) == nil)
    }
}
