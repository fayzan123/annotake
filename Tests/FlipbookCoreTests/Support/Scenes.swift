import FlipbookCore
import Foundation

/// Reusable synthetic sessions.
enum Scenes {
    /// Open a dialog, tick a checkbox, type an email, press Return; the dialog closes and a banner shows.
    static func clickFlow() -> RawSession {
        var scene = SceneBuilder()
        let open = ElementLabel(role: "button", label: "Open")
        let remember = ElementLabel(role: "checkbox", label: "Remember me")
        let email = ElementLabel(role: "text field", label: "Email")
        let openPoint = PixelPoint(x: 100, y: 100)
        let rememberPoint = PixelPoint(x: 300, y: 200)

        let frames = [
            scene.frame(at: 0.0),
            scene.frame(at: 1.3, set: .tiles(0..<12)),                  // a dialog
            scene.frame(at: 2.7, set: [100: 90]),                       // checkbox ticked
            scene.frame(at: 4.0, set: [150: 60]),
            scene.frame(at: 4.2, set: [151: 60]),
            scene.frame(at: 4.4, set: [152: 60]),
            scene.frame(at: 6.2, set: Dictionary.tiles(0..<12, value: 200)    // dialog closes
                .merging(.tiles(200..<206, value: 30)) { $1 }),          // banner
        ]
        let events = [
            InputEvent(time: 1.0, kind: .mouseDown(point: openPoint, target: open, button: .left, clickCount: 1)),
            InputEvent(time: 1.05, kind: .mouseUp(point: openPoint)),
            InputEvent(time: 2.5, kind: .mouseDown(point: rememberPoint, target: remember, button: .left, clickCount: 1)),
            InputEvent(time: 2.55, kind: .mouseUp(point: rememberPoint)),
            InputEvent(time: 4.0, kind: .keyTyped(field: email)),
            InputEvent(time: 4.1, kind: .keyTyped(field: email)),
            InputEvent(time: 4.2, kind: .keyTyped(field: email)),
            InputEvent(time: 4.3, kind: .keyTyped(field: email)),
            InputEvent(time: 4.4, kind: .keyTyped(field: email)),
            InputEvent(time: 6.0, kind: .keyReturn),
        ]
        return RawSession(geometry: scene.geometry, initialContext: FrameContext(app: "TestApp", window: "Main"),
                          frames: frames, events: events, stopTime: 8.0)
    }
}

/// A frame or an event of a raw session.
enum SessionItem: Equatable {
    case frame(FrameSample)
    case event(InputEvent)

    var time: TimeInterval {
        switch self {
        case .frame(let frame): frame.time
        case .event(let event): event.time
        }
    }
}

extension RawSession {
    /// Frames and events in time order; at equal times, frames go first.
    var mergedItems: [SessionItem] {
        let frames = self.frames.enumerated().map { (time: $1.time, order: $0, item: SessionItem.frame($1)) }
        let events = self.events.enumerated().map {
            (time: $1.time, order: self.frames.count + $0, item: SessionItem.event($1))
        }
        return (frames + events).sorted { ($0.time, $0.order) < ($1.time, $1.order) }.map(\.item)
    }
}

extension PickResult {
    /// Each frame's caption summary, numbered by position.
    var summaries: [String] {
        frames.enumerated().map { offset, frame in
            Captions.summary(for: frame, number: offset + 1, total: frames.count)
        }
    }
}
