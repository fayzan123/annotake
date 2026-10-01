import Foundation

/// One captured frame, reduced to what the picker needs. Core never sees pixels.
public struct FrameSample: Sendable, Equatable {
    /// The capture's monotonically increasing frame number.
    public let index: Int
    /// Seconds since recording start.
    public let time: TimeInterval
    public let signature: FrameSignature
    /// Changed regions reported by the capture, in output pixels.
    public let dirtyRects: [PixelRect]
    /// Cursor bounds in output pixels, nil when the cursor is off the target.
    public let cursor: PixelRect?

    public init(index: Int, time: TimeInterval, signature: FrameSignature, dirtyRects: [PixelRect], cursor: PixelRect?) {
        self.index = index
        self.time = time
        self.signature = signature
        self.dirtyRects = dirtyRects
        self.cursor = cursor
    }
}

/// The app and window title a frame's caption names on line 2.
public struct FrameContext: Sendable, Hashable, Codable {
    public var app: String
    public var window: String?

    public init(app: String, window: String?) {
        self.app = app
        self.window = window
    }
}

/// Which window line 2 names (spec §4.2).
public enum ContextSource: String, Sendable, Codable {
    /// The frontmost app and window: screen recordings. A switch changes the context.
    case focus
    /// The recorded window, whatever has focus: window recordings. A switch is still an action, but only
    /// the recorded window's `titleChanged` changes the context.
    case recordedWindow
}

/// An Accessibility label for a clicked element or a text field.
public struct ElementLabel: Sendable, Hashable, Codable {
    /// Already human-readable, e.g. "button".
    public var role: String
    public var label: String

    public init(role: String, label: String) {
        self.role = role
        self.label = label
    }
}

public enum MouseButton: String, Sendable, Codable {
    case left, right, other
}

/// Input as the picker sees it. Keystrokes appear only as kinds, never as the typed text.
public enum InputEventKind: Sendable, Equatable, Codable {
    case mouseDown(point: PixelPoint, target: ElementLabel?, button: MouseButton, clickCount: Int)
    case mouseUp(point: PixelPoint)
    /// A printable key; never the character.
    case keyTyped(field: ElementLabel?)
    case keyReturn
    case keyEscape
    /// e.g. "⌘S"
    case shortcut(String)
    case scroll(fractionOfViewport: Double)
    /// The frontmost app or window changed.
    case switched(FrameContext)
    /// Same window, new title: context only, not an action.
    case titleChanged(window: String?)
}

public struct InputEvent: Sendable, Equatable, Codable {
    public let time: TimeInterval
    public let kind: InputEventKind

    public init(time: TimeInterval, kind: InputEventKind) {
        self.time = time
        self.kind = kind
    }
}

/// What the user did on a frame, as captions describe it.
public enum StepAction: Sendable, Equatable, Codable {
    case clicked(target: ElementLabel?, at: PixelPoint, button: MouseButton, clickCount: Int)
    case typed(field: ElementLabel?)
    case pressedReturn
    case pressedEscape
    case pressedShortcut(String)
    case switched(to: FrameContext)
    case scrolled
}

public enum KeepReason: String, Sendable, Codable {
    case start, beforeAction, click, commit, switchApp, typing, scroll, visual, stop
}

/// A candidate frame: the screen, plus what the user did on it.
public struct KeptFrame: Sendable, Equatable {
    public let sample: FrameSample
    public let context: FrameContext
    public var actions: [StepAction]
    public let reason: KeepReason

    public var frameIndex: Int { sample.index }
    public var time: TimeInterval { sample.time }

    public init(sample: FrameSample, context: FrameContext, actions: [StepAction], reason: KeepReason) {
        self.sample = sample
        self.context = context
        self.actions = actions
        self.reason = reason
    }
}

/// A frame in the final result, without its signature.
public struct PickedFrame: Sendable, Equatable, Codable {
    public let frameIndex: Int
    public let time: TimeInterval
    public let context: FrameContext
    public var actions: [StepAction]
    public let reason: KeepReason

    public init(_ kept: KeptFrame) {
        self.init(frameIndex: kept.frameIndex, time: kept.time, context: kept.context,
                  actions: kept.actions, reason: kept.reason)
    }

    public init(frameIndex: Int, time: TimeInterval, context: FrameContext, actions: [StepAction], reason: KeepReason) {
        self.frameIndex = frameIndex
        self.time = time
        self.context = context
        self.actions = actions
        self.reason = reason
    }

    /// The point of every click, in order, for numbered click markers.
    public var clickPoints: [PixelPoint] {
        actions.compactMap { action in
            if case .clicked(_, let point, _, _) = action { return point }
            return nil
        }
    }
}

public struct PickResult: Sendable, Equatable, Codable {
    public let frames: [PickedFrame]
    public let candidateCount: Int
    public let duration: TimeInterval

    public init(frames: [PickedFrame], candidateCount: Int, duration: TimeInterval) {
        self.frames = frames
        self.candidateCount = candidateCount
        self.duration = duration
    }
}

/// What the capture layer must do with frame pixels.
public enum PickerOutput: Sendable, Equatable {
    /// Save this frame's full-size pixels now; it is the latest ingested frame.
    case persist(frameIndex: Int)
    /// These candidates were dropped; their saved pixels may be deleted.
    case discard(frameIndices: [Int])
}
