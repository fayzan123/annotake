import Carbon.HIToolbox
import CoreGraphics
import AnnotakeCore

/// What the active (event-modifying) tap does to each event while recording (spec §3.1, §6.2).
public enum ActiveTapPolicy {
    public enum Decision: Equatable, Sendable {
        case pass
        /// Click cleanup: remove the trigger's modifier so a hold-and-click stays a plain click.
        case stripModifier(CGEventFlags)
        /// The Esc of trigger + Esc: swallowed, and turned into a cancel.
        case consumeAsCancel
    }

    static let escape = Int64(kVK_Escape)
    static let pointerEvents: Set<CGEventType> = [
        .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
    ]

    public static func decide(type: CGEventType, keycode: Int64, flags: CGEventFlags, mode: RecordingMode,
                              triggerDown: Bool, trigger: TriggerKey) -> Decision {
        if type == .keyDown && keycode == escape && triggerDown {
            return .consumeAsCancel
        }
        let modifier = TriggerKeys.modifierFlag(for: trigger)
        if mode == .hold && pointerEvents.contains(type) && flags.contains(modifier) {
            return .stripModifier(modifier)
        }
        return .pass
    }
}

/// When the gesture recognizer needs its 50 ms tick: every timed transition happens while the key is
/// down, while recording, or within a second of a release.
public enum GestureTicking {
    public static let interval: TimeInterval = 0.05
    public static let afterRelease: TimeInterval = 1

    public static func needsTicks(triggerDown: Bool, recording: Bool, lastRelease: TimeInterval?,
                                  now: TimeInterval) -> Bool {
        if triggerDown || recording { return true }
        guard let lastRelease else { return false }
        return now - lastRelease < afterRelease
    }
}
