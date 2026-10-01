import Foundation

/// Caption text, timestamps and file names (spec §4.2–4.4).
public enum Captions {
    public static func text(for action: StepAction) -> String {
        switch action {
        case let .clicked(target, point, button, clickCount):
            let verb = button == .right ? "Right-clicked" : clickCount >= 2 ? "Double-clicked" : "Clicked"
            let role = target?.role ?? ""
            let label = target?.label ?? ""
            if role.isEmpty && label.isEmpty {
                return "\(verb) at (\(Int(point.x.rounded())), \(Int(point.y.rounded())))"
            }
            if role.isEmpty { return "\(verb) \"\(label)\"" }
            if label.isEmpty { return "\(verb) \(role)" }
            return "\(verb) \(role) \"\(label)\""
        case .typed(let field):
            if let label = field?.label, !label.isEmpty { return "Typed in field \"\(label)\"" }
            return "Typed"
        case .pressedReturn:
            return "Pressed Return"
        case .pressedEscape:
            return "Pressed Esc"
        case .pressedShortcut(let shortcut):
            return "Pressed \(shortcut)"
        case .switched(let context):
            return "Switched to \(line2(for: context))"
        case .scrolled:
            return "Scrolled"
        }
    }

    /// The frame's actions joined with " → ", or Start / End / Screen changed when it has none.
    public static func summary(for frame: PickedFrame, number: Int, total: Int) -> String {
        if !frame.actions.isEmpty {
            return frame.actions.map(text(for:)).joined(separator: " → ")
        }
        if number == 1 { return "Start" }
        if number == total { return "End" }
        return "Screen changed"
    }

    /// e.g. `3/8 · 0:07 · Clicked button "Save"`
    public static func line1(for frame: PickedFrame, number: Int, total: Int) -> String {
        "\(number)/\(total) · \(timestamp(frame.time)) · \(summary(for: frame, number: number, total: total))"
    }

    /// e.g. `Google Chrome — Dayforce · Timesheets`, or the app alone when there is no window title.
    public static func line2(for context: FrameContext) -> String {
        guard let window = context.window, !window.isEmpty else { return context.app }
        return "\(context.app) — \(window)"
    }

    /// Whole seconds as "m:ss", rounded down.
    public static func timestamp(_ seconds: TimeInterval) -> String {
        let whole = wholeSeconds(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// e.g. `03_0m07s.png`
    public static func fileName(number: Int, time: TimeInterval) -> String {
        let whole = wholeSeconds(time)
        return String(format: "%02d_%dm%02ds.png", number, whole / 60, whole % 60)
    }

    private static func wholeSeconds(_ seconds: TimeInterval) -> Int {
        Int(max(seconds, 0).rounded(.down))
    }
}
