import Foundation

public struct GestureConfig: Sendable, Equatable, Codable {
    public var holdThreshold: TimeInterval = 0.25
    /// Spec §3.1: the pill and start sound appear here; a key before this was a shortcut.
    public var holdReveal: TimeInterval = 0.80
    public var doubleTapWindow: TimeInterval = 0.30

    public init() {}
}

public enum TriggerInput: Sendable, Equatable {
    case triggerDown(at: TimeInterval)
    case triggerUp(at: TimeInterval)
    /// Any other key, including other modifiers.
    case otherKeyDown(at: TimeInterval, isEscape: Bool)
    case mouseDown(at: TimeInterval)

    var time: TimeInterval {
        switch self {
        case .triggerDown(let time), .triggerUp(let time), .otherKeyDown(let time, _), .mouseDown(let time):
            time
        }
    }
}

public enum GestureEvent: Sendable, Equatable {
    case startHold, revealHold, discardHold, stopHold, startHandsFree, stopHandsFree, cancel
}

public enum RecordingMode: Sendable, Equatable {
    case hold, handsFree
}

/// Turns trigger-key, other-key and mouse input into recording gestures (spec §3.1):
/// hold, double-tap on and off, trigger + Esc to cancel, and "that was a shortcut".
public struct GestureRecognizer: Sendable {
    private enum Phase: Equatable {
        case idle
        case pressed(downAt: TimeInterval)
        /// Waiting for the trigger to come up before anything else counts.
        case waitForRelease
        case tapped(upAt: TimeInterval)
        case hold(downAt: TimeInterval, revealed: Bool, clicked: Bool)
        case handsFreeDown(used: Bool, downAt: TimeInterval, fromStart: Bool)
        case handsFreeUp
        case handsFreeTapped(upAt: TimeInterval)
    }

    private let config: GestureConfig
    private var phase = Phase.idle
    public private(set) var recording: RecordingMode?

    public init(config: GestureConfig = GestureConfig()) {
        self.config = config
    }

    /// Advances time to the input's time, then handles the input.
    public mutating func handle(_ input: TriggerInput) -> [GestureEvent] {
        var events = advance(to: input.time)

        switch phase {
        case .idle:
            if case .triggerDown(let t) = input {
                phase = .pressed(downAt: t)
            }

        case .pressed:
            switch input {
            case .triggerUp(let t):
                phase = .tapped(upAt: t)
            case .otherKeyDown, .mouseDown:
                phase = .waitForRelease   // It was a shortcut.
            case .triggerDown:
                break
            }

        case .waitForRelease:
            if case .triggerUp = input {
                phase = .idle
            }

        case .tapped:
            switch input {
            case .triggerDown(let t):
                phase = .handsFreeDown(used: false, downAt: t, fromStart: true)
                recording = .handsFree
                events.append(.startHandsFree)
            case .otherKeyDown, .mouseDown:
                phase = .idle
            case .triggerUp:
                break
            }

        case let .hold(downAt, revealed, clicked):
            switch input {
            case .triggerUp:
                // Revealed or not; the session layer applies the 0.5 s accidental-hold rule.
                phase = .idle
                recording = nil
                events.append(.stopHold)
            case .otherKeyDown(_, isEscape: true):
                phase = .waitForRelease
                recording = nil
                events.append(.cancel)
            case .otherKeyDown(_, isEscape: false) where !revealed && !clicked:
                phase = .waitForRelease   // It was a shortcut, e.g. ⌘C.
                recording = nil
                events.append(.discardHold)
            case .mouseDown where !revealed:
                phase = .hold(downAt: downAt, revealed: false, clicked: true)
            case .otherKeyDown, .mouseDown, .triggerDown:
                break
            }

        case let .handsFreeDown(used, downAt, fromStart):
            switch input {
            case .triggerUp(let t):
                if !fromStart && !used && t - downAt < config.holdThreshold {
                    phase = .handsFreeTapped(upAt: t)
                } else {
                    phase = .handsFreeUp
                }
            case .otherKeyDown(_, isEscape: true):
                phase = .waitForRelease
                recording = nil
                events.append(.cancel)
            case .otherKeyDown, .mouseDown:
                phase = .handsFreeDown(used: true, downAt: downAt, fromStart: fromStart)
            case .triggerDown:
                break
            }

        case .handsFreeUp:
            // Plain Esc passes through to the recorded app.
            if case .triggerDown(let t) = input {
                phase = .handsFreeDown(used: false, downAt: t, fromStart: false)
            }

        case .handsFreeTapped:
            switch input {
            case .triggerDown:
                phase = .waitForRelease
                recording = nil
                events.append(.stopHandsFree)
            case .otherKeyDown, .mouseDown:
                phase = .handsFreeUp
            case .triggerUp:
                break
            }
        }
        return events
    }

    /// Call every 50 ms or less.
    public mutating func tick(now: TimeInterval) -> [GestureEvent] {
        advance(to: now)
    }

    /// The recording ended elsewhere (auto-stop, menu, error).
    public mutating func reset() {
        phase = .idle
        recording = nil
    }

    /// Applies every time-based transition that is due, in order.
    private mutating func advance(to now: TimeInterval) -> [GestureEvent] {
        var events: [GestureEvent] = []
        while true {
            switch phase {
            case .pressed(let downAt) where now - downAt >= config.holdThreshold:
                phase = .hold(downAt: downAt, revealed: false, clicked: false)
                recording = .hold
                events.append(.startHold)
            case let .hold(downAt, false, clicked) where now - downAt >= config.holdReveal:
                phase = .hold(downAt: downAt, revealed: true, clicked: clicked)
                events.append(.revealHold)
            case .tapped(let upAt) where now - upAt > config.doubleTapWindow:
                phase = .idle   // A single tap does nothing in v1.
            case .handsFreeTapped(let upAt) where now - upAt > config.doubleTapWindow:
                phase = .handsFreeUp
            default:
                return events
            }
        }
    }
}
