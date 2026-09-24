import AppKit
import FlipbookCore

/// The pill's text (spec §3.2).
enum PillText {
    static func glyph(_ key: TriggerKey) -> String {
        switch key {
        case .rightCommand: "⌘"
        case .rightOption: "⌥"
        case .fn: "fn"
        }
    }

    /// e.g. `● 0:04 · 3 frames · release ⌘ to stop`. The count never promises more than the card will hold.
    static func recording(mode: RecordingMode, elapsed: TimeInterval, frames: Int, maxFrames: Int,
                          trigger: TriggerKey) -> String {
        let count = min(frames, maxFrames)
        let key = glyph(trigger)
        let hint = switch mode {
        case .hold: "release \(key) to stop"
        case .handsFree: "double-tap \(key) to stop · \(trigger == .fn ? "fn+Esc" : key + "Esc") cancels"
        }
        return "● \(Captions.timestamp(elapsed)) · \(count == 1 ? "1 frame" : "\(count) frames") · \(hint)"
    }

    static func message(_ message: SessionMachine.PillMessage) -> String {
        switch message {
        case .screenRecordingNeeded: "Screen Recording permission needed"
        case .couldNotStart: "Couldn't start recording — try again"
        case .cannotSave: "Can't save to the captures folder — check the save location"
        case .note(let text): text
        }
    }
}

/// A dark capsule with the pill's text, drawn by hand so offscreen snapshots match the screen.
final class PillView: NSView {
    static let height: CGFloat = 36
    static let horizontalPadding: CGFloat = 16
    static let buttonGap: CGFloat = 10
    /// The button's capsule reaches this far past its title.
    static let buttonInset = NSSize(width: 10, height: 4)
    static let buttonFill = NSColor(white: 1, alpha: 0.22)
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let background = NSColor(white: 0.08, alpha: 0.88)
    static let dot = NSColor.systemRed

    var text = "" {
        didSet { needsDisplay = true }
    }

    /// A button shown after the text, for messages like "Screen Recording permission needed".
    private(set) var button: NSButton?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // The capsule is always dark, so its controls are drawn for a dark background.
        appearance = NSAppearance(named: .darkAqua)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setButton(title: String?, action: Selector?, target: AnyObject?) {
        button?.removeFromSuperview()
        button = nil
        guard let title else { return }
        // Drawn by hand: the pill's panel never becomes key, and a system button would look inactive.
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        addSubview(button)
        self.button = button
    }

    /// The size that fits the text and the button.
    var fittingSizeForContent: NSSize {
        let textWidth = (text as NSString).size(withAttributes: [.font: Self.font]).width
        let buttonWidth = button.map { $0.fittingSize.width + Self.buttonGap + 2 * Self.buttonInset.width } ?? 0
        return NSSize(width: ceil(textWidth + buttonWidth + 2 * Self.horizontalPadding), height: Self.height)
    }

    override func layout() {
        super.layout()
        guard let button else { return }
        let size = button.fittingSize
        button.frame = NSRect(x: bounds.maxX - Self.horizontalPadding - Self.buttonInset.width - size.width,
                              y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        if let button {
            let capsule = button.frame.insetBy(dx: -Self.buttonInset.width, dy: -Self.buttonInset.height)
            Self.buttonFill.setFill()
            NSBezierPath(roundedRect: capsule, xRadius: capsule.height / 2, yRadius: capsule.height / 2).fill()
        }
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: Self.font, .foregroundColor: NSColor.white,
        ])
        if text.hasPrefix("●") {
            attributed.addAttribute(.foregroundColor, value: Self.dot, range: NSRange(location: 0, length: 1))
        }
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: Self.horizontalPadding, y: (bounds.height - size.height) / 2))
    }
}

/// The pill panel (spec §3.2): created at launch, bottom center of the recorded screen, on every Space
/// including full-screen apps. It ignores clicks while recording, and takes them only when a message
/// shows a button.
@MainActor
final class PillPanel {
    static let bottomInset: CGFloat = 24
    /// Messages without a recording under them hide after this long.
    static let messageDuration: TimeInterval = 5
    static let screenRecordingPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    let panel: NSPanel
    let view = PillView(frame: NSRect(x: 0, y: 0, width: 300, height: PillView.height))
    private var screen: NSScreen?
    private var hideTimer: Timer?
    private let buttonTarget = ButtonTarget()

    init() {
        panel = NSPanel(contentRect: view.frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered,
                        defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentView = view
    }

    /// The screen the pill sits on: the recorded one.
    func place(on screen: NSScreen?) {
        self.screen = screen
        reposition()
    }

    /// The recording text; clicks pass through to the app being recorded.
    func showRecording(_ text: String) {
        hideTimer?.invalidate()
        hideTimer = nil
        view.setButton(title: nil, action: nil, target: nil)
        panel.ignoresMouseEvents = true
        show(text)
    }

    /// A message; with `openSettings`, it offers a button and takes clicks.
    func showMessage(_ text: String, openSettings: Bool, hideAfter: TimeInterval? = messageDuration) {
        hideTimer?.invalidate()
        if openSettings {
            buttonTarget.action = { NSWorkspace.shared.open(Self.screenRecordingPane) }
            view.setButton(title: "Open Settings", action: #selector(ButtonTarget.run), target: buttonTarget)
        } else {
            view.setButton(title: nil, action: nil, target: nil)
        }
        panel.ignoresMouseEvents = !openSettings
        show(text)
        if let hideAfter {
            hideTimer = Timer.scheduledTimer(withTimeInterval: hideAfter, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    func update(_ text: String) {
        guard panel.isVisible else { return }
        view.text = text
        reposition()
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.orderOut(nil)
        panel.ignoresMouseEvents = true
    }

    var isShowingMessage: Bool { hideTimer != nil || view.button != nil }

    private func show(_ text: String) {
        view.text = text
        reposition()
        panel.orderFrontRegardless()
    }

    private func reposition() {
        let size = view.fittingSizeForContent
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + Self.bottomInset,
                              width: size.width, height: size.height), display: true)
        view.needsLayout = true
    }
}

/// An Objective-C target for a closure.
final class ButtonTarget: NSObject {
    var action: () -> Void = {}

    @objc func run() {
        action()
    }
}
