import AppKit
import Carbon.HIToolbox
import CoreGraphics
import FlipbookCore
import Synchronization

/// Detecting the trigger key from flag-change events (design §5).
public enum TriggerKeys {
    /// NX_DEVICERCMDKEYMASK: the right ⌘ key is down.
    static let rightCommandDeviceBit: UInt64 = 0x10
    /// NX_DEVICERALTKEYMASK: the right ⌥ key is down.
    static let rightOptionDeviceBit: UInt64 = 0x40

    public static func keycode(for key: TriggerKey) -> Int64 {
        switch key {
        case .rightCommand: Int64(kVK_RightCommand)
        case .rightOption: Int64(kVK_RightOption)
        case .fn: Int64(kVK_Function)
        }
    }

    /// Whether the key is down, from the event flags' device bits (or the secondary-fn flag).
    public static func isDown(_ key: TriggerKey, flags: CGEventFlags) -> Bool {
        switch key {
        case .rightCommand: flags.rawValue & rightCommandDeviceBit != 0
        case .rightOption: flags.rawValue & rightOptionDeviceBit != 0
        case .fn: flags.contains(.maskSecondaryFn)
        }
    }

    /// The modifier the trigger adds to other events: what click cleanup strips.
    public static func modifierFlag(for key: TriggerKey) -> CGEventFlags {
        switch key {
        case .rightCommand: .maskCommand
        case .rightOption: .maskAlternate
        case .fn: .maskSecondaryFn
        }
    }

    /// Right ⌘, ⌘, ⇧, Caps Lock, ⌥, ⌃, right ⇧, right ⌥, right ⌃, fn.
    public static let modifierKeycodes: Set<Int64> = Set(Int64(kVK_RightCommand)...Int64(kVK_Function))
}

/// The unmodified character a key produces in a keyboard layout; nil or "" when it has none.
public protocol KeyboardLayout: Sendable {
    func character(forKeycode keycode: UInt16) -> String?
}

/// The current keyboard layout. The Text Input Sources calls must run on the main thread, so the layout
/// is read there, at first use and whenever the input source changes, and translated from anywhere.
public struct CurrentKeyboardLayout: KeyboardLayout {
    /// Create it on the main thread.
    public init() {
        MainActor.assumeIsolated { LayoutCache.shared.startIfNeeded() }
    }

    public func character(forKeycode keycode: UInt16) -> String? {
        LayoutCache.shared.character(forKeycode: keycode)
    }
}

/// The current layout's `uchr` data and keyboard type, shared across threads under a lock.
private final class LayoutCache: Sendable {
    static let shared = LayoutCache()
    private static let maxCharacters = 4

    private struct Layout {
        var data: Data?
        var keyboardType: UInt32
    }

    private let layout = Mutex<Layout?>(nil)

    @MainActor
    func startIfNeeded() {
        guard layout.withLock({ $0 == nil }) else { return }
        reload()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { LayoutCache.shared.reload() }
            }
    }

    @MainActor
    private func reload() {
        let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let pointer = source.flatMap { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) }
        let data = pointer.map { Unmanaged<CFData>.fromOpaque($0).takeUnretainedValue() as Data }
        let keyboardType = UInt32(LMGetKbdType())
        layout.withLock { $0 = Layout(data: data, keyboardType: keyboardType) }
    }

    func character(forKeycode keycode: UInt16) -> String? {
        guard let current = layout.withLock({ $0 }), let data = current.data else { return nil }
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: Self.maxCharacters)
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(base, keycode, UInt16(kUCKeyActionDisplay), 0, current.keyboardType,
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, Self.maxCharacters,
                                  &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

/// What InputMonitor hands the app while recording. Points are global, top-left origin.
public enum RecordedInput: Sendable, Equatable {
    case mouseDown(globalPoint: CGPoint, button: MouseButton, clickCount: Int)
    case mouseUp(globalPoint: CGPoint)
    /// `keyTyped(field: nil)`, `keyReturn`, `keyEscape` or `shortcut`. Never the character.
    case key(InputEventKind, keycode: UInt16)
    case scroll(globalPoint: CGPoint, pointDeltaX: Double, pointDeltaY: Double)
}

/// Which keys are actions, and how shortcuts are named (spec §4.4). Only the key's kind leaves here.
public enum KeyClassifier {
    static let returnKey = UInt16(kVK_Return)
    static let keypadEnter = UInt16(kVK_ANSI_KeypadEnter)
    static let escape = UInt16(kVK_Escape)

    /// Keys that are never actions when pressed alone: arrows, navigation keys, Help and F-keys.
    static let navigationKeys: Set<UInt16> = Set([
        kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_Help,
    ].map(UInt16.init)).union(functionKeys.keys)

    static let functionKeys: [UInt16: String] = Dictionary(uniqueKeysWithValues: [
        (kVK_F1, 1), (kVK_F2, 2), (kVK_F3, 3), (kVK_F4, 4), (kVK_F5, 5), (kVK_F6, 6), (kVK_F7, 7), (kVK_F8, 8),
        (kVK_F9, 9), (kVK_F10, 10), (kVK_F11, 11), (kVK_F12, 12), (kVK_F13, 13), (kVK_F14, 14), (kVK_F15, 15),
        (kVK_F16, 16), (kVK_F17, 17), (kVK_F18, 18), (kVK_F19, 19), (kVK_F20, 20),
    ].map { (UInt16($0.0), "F\($0.1)") })

    /// Keys named by a symbol rather than their character.
    static let symbols: [UInt16: String] = Dictionary(uniqueKeysWithValues: [
        (kVK_Return, "↩"), (kVK_ANSI_KeypadEnter, "⌤"), (kVK_Tab, "⇥"), (kVK_Space, "Space"), (kVK_Delete, "⌫"),
        (kVK_ForwardDelete, "⌦"), (kVK_Escape, "⎋"), (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"),
        (kVK_DownArrow, "↓"), (kVK_UpArrow, "↑"), (kVK_Home, "↖"), (kVK_End, "↘"), (kVK_PageUp, "⇞"),
        (kVK_PageDown, "⇟"),
    ].map { (UInt16($0.0), $0.1) })

    /// Carbon's kVK_ANSI_* keys, for shortcuts on keys the layout can't name.
    static let ansi: [UInt16: String] = Dictionary(uniqueKeysWithValues: [
        (kVK_ANSI_A, "A"), (kVK_ANSI_S, "S"), (kVK_ANSI_D, "D"), (kVK_ANSI_F, "F"), (kVK_ANSI_H, "H"),
        (kVK_ANSI_G, "G"), (kVK_ANSI_Z, "Z"), (kVK_ANSI_X, "X"), (kVK_ANSI_C, "C"), (kVK_ANSI_V, "V"),
        (kVK_ANSI_B, "B"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_W, "W"), (kVK_ANSI_E, "E"), (kVK_ANSI_R, "R"),
        (kVK_ANSI_Y, "Y"), (kVK_ANSI_T, "T"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
        (kVK_ANSI_4, "4"), (kVK_ANSI_6, "6"), (kVK_ANSI_5, "5"), (kVK_ANSI_Equal, "="), (kVK_ANSI_9, "9"),
        (kVK_ANSI_7, "7"), (kVK_ANSI_Minus, "-"), (kVK_ANSI_8, "8"), (kVK_ANSI_0, "0"),
        (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_O, "O"), (kVK_ANSI_U, "U"), (kVK_ANSI_LeftBracket, "["),
        (kVK_ANSI_I, "I"), (kVK_ANSI_P, "P"), (kVK_ANSI_L, "L"), (kVK_ANSI_J, "J"), (kVK_ANSI_Quote, "'"),
        (kVK_ANSI_K, "K"), (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Comma, ","),
        (kVK_ANSI_Slash, "/"), (kVK_ANSI_N, "N"), (kVK_ANSI_M, "M"), (kVK_ANSI_Period, "."), (kVK_ANSI_Grave, "`"),
        (kVK_ANSI_KeypadDecimal, "."), (kVK_ANSI_KeypadMultiply, "*"), (kVK_ANSI_KeypadPlus, "+"),
        (kVK_ANSI_KeypadDivide, "/"), (kVK_ANSI_KeypadMinus, "-"), (kVK_ANSI_KeypadEquals, "="),
        (kVK_ANSI_Keypad0, "0"), (kVK_ANSI_Keypad1, "1"), (kVK_ANSI_Keypad2, "2"), (kVK_ANSI_Keypad3, "3"),
        (kVK_ANSI_Keypad4, "4"), (kVK_ANSI_Keypad5, "5"), (kVK_ANSI_Keypad6, "6"), (kVK_ANSI_Keypad7, "7"),
        (kVK_ANSI_Keypad8, "8"), (kVK_ANSI_Keypad9, "9"),
    ].map { (UInt16($0.0), $0.1) })

    /// The action a key press is, or nil when it isn't one: modifiers, auto-repeats, and navigation keys
    /// pressed alone. Composing keystrokes (⌥-letters, dead keys) are typing, not shortcuts.
    public static func classify(keycode: UInt16, flags: CGEventFlags, isRepeat: Bool,
                                layout: KeyboardLayout) -> InputEventKind? {
        if TriggerKeys.modifierKeycodes.contains(Int64(keycode)) || isRepeat { return nil }
        let isShortcut = flags.contains(.maskCommand) || flags.contains(.maskControl)
        if isShortcut { return .shortcut(shortcutName(keycode: keycode, flags: flags, layout: layout)) }
        switch keycode {
        case returnKey, keypadEnter: return .keyReturn
        case escape: return .keyEscape
        default: return navigationKeys.contains(keycode) ? nil : .keyTyped(field: nil)
        }
    }

    /// e.g. `⇧⌘T`: modifiers in the order ⌃⌥⇧⌘, then the key as the layout prints it, or its symbol.
    public static func shortcutName(keycode: UInt16, flags: CGEventFlags, layout: KeyboardLayout) -> String {
        var name = ""
        if flags.contains(.maskControl) { name += "⌃" }
        if flags.contains(.maskAlternate) { name += "⌥" }
        if flags.contains(.maskShift) { name += "⇧" }
        if flags.contains(.maskCommand) { name += "⌘" }
        return name + keyName(keycode, layout: layout)
    }

    private static func keyName(_ keycode: UInt16, layout: KeyboardLayout) -> String {
        if let symbol = symbols[keycode] ?? functionKeys[keycode] { return symbol }
        if let character = layout.character(forKeycode: keycode), isPrintable(character) {
            return character.uppercased()
        }
        return ansi[keycode] ?? "Key \(keycode)"
    }

    /// Not empty, and no control characters, which a layout gives for keys like Clear.
    private static func isPrintable(_ string: String) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && $0 != " " }
    }
}

/// Mouse buttons and scroll amounts.
public enum PointerClassifier {
    public static func button(for type: CGEventType) -> MouseButton? {
        switch type {
        case .leftMouseDown, .leftMouseUp: .left
        case .rightMouseDown, .rightMouseUp: .right
        case .otherMouseDown, .otherMouseUp: .other
        default: nil
        }
    }

    /// How far a scroll moved, as a fraction of the recorded area's height; the scrolled view's own
    /// height isn't known.
    public static func scrollFraction(pointDeltaX: Double, pointDeltaY: Double, targetHeightPoints: Double) -> Double {
        guard targetHeightPoints > 0 else { return 0 }
        return (pointDeltaX * pointDeltaX + pointDeltaY * pointDeltaY).squareRoot() / targetHeightPoints
    }
}
