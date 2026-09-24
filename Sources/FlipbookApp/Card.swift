import AppKit
import FlipbookCore
import FlipbookExport

/// Where cards sit (spec §3.4): the newest in the bottom-right corner, older ones stacked upward.
/// At most four show; a fifth pushes the oldest out, and that one stays in Recent Captures.
struct CardStack {
    static let maxVisible = 4
    static let inset: CGFloat = 20
    static let gap: CGFloat = 10

    /// Newest first.
    private(set) var ids: [Int] = []

    /// Adds the newest card and returns the ids pushed out.
    mutating func push(_ id: Int) -> [Int] {
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        guard ids.count > Self.maxVisible else { return [] }
        let pushedOut = Array(ids[Self.maxVisible...])
        ids.removeLast(ids.count - Self.maxVisible)
        return pushedOut
    }

    mutating func remove(_ id: Int) {
        ids.removeAll { $0 == id }
    }

    /// Each card's frame in Cocoa coordinates.
    func frames(in visibleFrame: CGRect, cardSize: CGSize) -> [Int: CGRect] {
        var frames: [Int: CGRect] = [:]
        for (position, id) in ids.enumerated() {
            frames[id] = CGRect(x: visibleFrame.maxX - Self.inset - cardSize.width,
                                y: visibleFrame.minY + Self.inset + CGFloat(position) * (cardSize.height + Self.gap),
                                width: cardSize.width, height: cardSize.height)
        }
        return frames
    }
}

/// After a drop the card fades out over 5 s instead of vanishing, so it can be dragged again: drop targets
/// report success even when they keep only some frames. Hovering holds it; leaving restarts the 5 s.
struct CardFade {
    static let duration: TimeInterval = 5

    private var fadeStart: TimeInterval?
    private var hovering = false

    mutating func dropped(at t: TimeInterval) {
        fadeStart = t
    }

    mutating func hover(_ inside: Bool, at t: TimeInterval) {
        hovering = inside
        if !inside, fadeStart != nil { fadeStart = t }
    }

    /// 1 until a drop, then linear to 0 over 5 s; 1 while hovered.
    func opacity(at t: TimeInterval) -> Double {
        guard let fadeStart, !hovering else { return 1 }
        return max(0, 1 - (t - fadeStart) / Self.duration)
    }

    func isDone(at t: TimeInterval) -> Bool {
        guard let fadeStart, !hovering else { return false }
        return t - fadeStart >= Self.duration
    }

    var isFading: Bool { fadeStart != nil }
}

/// A press that moves less than 4 pt is a click; more is a drag.
enum ClickOrDrag {
    static let threshold: CGFloat = 4

    static func isClick(from: CGPoint, to: CGPoint) -> Bool {
        hypot(to.x - from.x, to.y - from.y) < threshold
    }
}

// MARK: - The card view

/// One capture's card, drawn by hand so snapshots match the screen.
final class CardView: NSView, NSDraggingSource {
    enum State {
        case saving(duration: TimeInterval)
        case ready(FinishedCapture, thumbnails: [NSImage])
        case failed(folder: URL)
    }

    static let size = CGSize(width: 240, height: 150)
    static let cornerRadius: CGFloat = 14
    static let background = NSColor(white: 0.1, alpha: 0.94)
    static let thumbnailArea = CGRect(x: 16, y: 18, width: 208, height: 82)
    /// Each card behind the front one is inset and raised by this much.
    static let stackStep = CGSize(width: 7, height: 5)
    static let closeRect = CGRect(x: 8, y: 8, width: 20, height: 20)
    static let buttonRect = CGRect(x: 16, y: 112, width: 104, height: 24)
    /// A two-finger swipe right this far dismisses the card.
    static let swipeDistance: CGFloat = 40
    static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let subtitleFont = NSFont.systemFont(ofSize: 11)

    var state: State {
        didSet { needsDisplay = true }
    }

    var hovering = false {
        didSet { needsDisplay = true }
    }

    var onClick: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var onDropped: () -> Void = {}

    private var downPoint: CGPoint?
    private var dragStarted = false
    private var swipe: CGFloat = 0

    init(state: State) {
        self.state = state
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        appearance = NSAppearance(named: .darkAqua)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        onHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        onHover(false)
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint, !dragStarted, case .ready(let capture, let thumbnails) = state else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard !ClickOrDrag.isClick(from: downPoint, to: point) else { return }
        dragStarted = true
        // Every frame, in order, as a PNG file (M0's proven payload).
        let image = thumbnails.first
        let items = capture.frameURLs.enumerated().map { position, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(position, 10)) * 3
            item.setDraggingFrame(Self.thumbnailArea.offsetBy(dx: offset, dy: offset), contents: image)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        guard let downPoint, !dragStarted else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard ClickOrDrag.isClick(from: downPoint, to: point) else { return }
        if hovering && Self.closeRect.insetBy(dx: -4, dy: -4).contains(point) {
            onDismiss()
        } else if case .failed(let folder) = state {
            if Self.buttonRect.contains(point) { NSWorkspace.shared.open(folder) }
        } else {
            onClick()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began { swipe = 0 }
        // The fingers' direction, whatever the natural-scrolling setting.
        swipe += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        if swipe > Self.swipeDistance {
            swipe = 0
            onDismiss()
        }
        if event.phase == .ended || event.phase == .cancelled { swipe = 0 }
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { onDropped() }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        Self.background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()

        switch state {
        case .saving(let duration):
            drawPlaceholders()
            drawText(title: Captions.timestamp(duration), subtitle: "Saving…")
            drawSpinner(at: CGPoint(x: bounds.maxX - 28, y: 124))
        case let .ready(capture, thumbnails):
            drawThumbnails(thumbnails)
            let count = capture.manifest.result.frames.count
            let frames = count == 1 ? "1 frame" : "\(count) frames"
            drawText(title: "\(frames) · \(Captions.timestamp(capture.manifest.result.duration))",
                     subtitle: "Drag into a chat · click to review")
        case .failed:
            drawText(title: "Couldn't save the capture", subtitle: nil, titleY: 20)
            let explanation = "The disk may be full, or the captures folder can't be written to." as NSString
            explanation.draw(in: CGRect(x: 16, y: 44, width: bounds.width - 32, height: 44),
                             withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                                              .foregroundColor: NSColor(white: 0.72, alpha: 1)])
            drawButton("Show Folder", in: Self.buttonRect)
        }
        if hovering { drawCloseButton() }
    }

    private func frontRect(_ depth: Int) -> CGRect {
        let step = CGFloat(depth)
        return CGRect(x: Self.thumbnailArea.minX + step * Self.stackStep.width,
                      y: Self.thumbnailArea.minY - step * Self.stackStep.height,
                      width: Self.thumbnailArea.width - 2 * step * Self.stackStep.width,
                      height: Self.thumbnailArea.height)
    }

    private func drawPlaceholders() {
        for depth in (0..<3).reversed() {
            NSColor(white: 0.22 + 0.06 * CGFloat(2 - depth), alpha: 1).setFill()
            NSBezierPath(roundedRect: frontRect(depth), xRadius: 6, yRadius: 6).fill()
        }
    }

    private func drawThumbnails(_ thumbnails: [NSImage]) {
        let shown = Array(thumbnails.prefix(3))
        for depth in (0..<3).reversed() {
            let rect = frontRect(depth)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            guard depth < shown.count else {
                NSColor(white: 0.25, alpha: 1).setFill()
                path.fill()
                continue
            }
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            drawAspectFill(shown[depth], in: rect)
            if depth > 0 {
                NSColor(white: 0, alpha: 0.25 * CGFloat(depth)).setFill()
                rect.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 1, alpha: 0.18).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    /// Fills the rect with the top of the image, cropped at the sides or bottom.
    private func drawAspectFill(_ image: NSImage, in rect: CGRect) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.minY, width: drawn.width, height: drawn.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func drawText(title: String, subtitle: String?, titleY: CGFloat = 108) {
        (title as NSString).draw(at: CGPoint(x: 16, y: titleY),
                                 withAttributes: [.font: Self.titleFont, .foregroundColor: NSColor.white])
        guard let subtitle else { return }
        (subtitle as NSString).draw(at: CGPoint(x: 16, y: titleY + 19),
                                    withAttributes: [.font: Self.subtitleFont,
                                                     .foregroundColor: NSColor(white: 0.68, alpha: 1)])
    }

    private func drawButton(_ title: String, in rect: CGRect) {
        NSColor(white: 1, alpha: 0.2).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                                 withAttributes: attributes)
    }

    /// A static activity mark; it turns while saving.
    var spinnerPhase: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    private func drawSpinner(at center: CGPoint) {
        let spokes = 8
        for spoke in 0..<spokes {
            let angle = (CGFloat(spoke) / CGFloat(spokes) + spinnerPhase) * 2 * .pi
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let path = NSBezierPath()
            path.move(to: CGPoint(x: center.x + direction.x * 4, y: center.y + direction.y * 4))
            path.line(to: CGPoint(x: center.x + direction.x * 8, y: center.y + direction.y * 8))
            path.lineWidth = 2
            path.lineCapStyle = .round
            NSColor(white: 1, alpha: 0.25 + 0.75 * CGFloat(spoke) / CGFloat(spokes)).setStroke()
            path.stroke()
        }
    }

    private func drawCloseButton() {
        let rect = Self.closeRect
        NSColor(white: 0.35, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let cross = NSBezierPath()
        let inset = rect.insetBy(dx: 6.5, dy: 6.5)
        cross.move(to: CGPoint(x: inset.minX, y: inset.minY))
        cross.line(to: CGPoint(x: inset.maxX, y: inset.maxY))
        cross.move(to: CGPoint(x: inset.maxX, y: inset.minY))
        cross.line(to: CGPoint(x: inset.minX, y: inset.maxY))
        cross.lineWidth = 1.6
        cross.lineCapStyle = .round
        NSColor.white.setStroke()
        cross.stroke()
    }
}

// MARK: - Cards on screen

/// The cards (spec §3.4): one non-activating panel per capture, stacked in the corner of the screen the
/// cursor was on when the recording stopped. They never take focus, and accept the first click.
@MainActor
final class CardController {
    static let fadeStep: TimeInterval = 1.0 / 30
    static let spinnerStep: TimeInterval = 0.08
    /// Thumbnails are loaded this wide, in points.
    static let thumbnailWidth: CGFloat = 416

    private final class Card {
        let panel: NSPanel
        let view: CardView
        var fade = CardFade()
        var capture: FinishedCapture?

        init(panel: NSPanel, view: CardView) {
            self.panel = panel
            self.view = view
        }
    }

    private var stack = CardStack()
    private var cards: [Int: Card] = [:]
    /// The card showing each capture folder, so reopening one brings its card forward.
    private var cardByFolder: [String: Int] = [:]
    /// Cards reopened from Recent Captures count down from here, apart from live captures' ids.
    private var nextReopenedID = -1
    private var screen: NSScreen?
    private var timer: Timer?
    /// A click on a ready card: its filmstrip.
    var onOpen: (FinishedCapture, Int) -> Void = { capture, _ in
        NSWorkspace.shared.activateFileViewerSelecting([capture.folder])
    }

    func showSaving(id: Int, duration: TimeInterval, on screen: NSScreen?) {
        let view = CardView(state: .saving(duration: duration))
        let card = Card(panel: Self.makePanel(view), view: view)
        wire(card, id: id)
        cards[id] = card
        if let screen { self.screen = screen }
        for pushedOut in stack.push(id) {
            close(pushedOut)
        }
        layout()
        card.panel.orderFrontRegardless()
        startTimer()
    }

    func show(_ capture: FinishedCapture, id: Int) {
        let card: Card
        if let existing = cards[id] {
            card = existing
        } else {
            let view = CardView(state: .saving(duration: capture.manifest.result.duration))
            card = Card(panel: Self.makePanel(view), view: view)
            wire(card, id: id)
            cards[id] = card
            for pushedOut in stack.push(id) { close(pushedOut) }
            layout()
            card.panel.orderFrontRegardless()
        }
        card.capture = capture
        card.view.state = .ready(capture, thumbnails: Self.thumbnails(for: capture))
        cardByFolder[capture.folder.path] = id
    }

    func fail(id: Int, folder: URL) {
        guard let card = cards[id] else { return }
        card.view.state = .failed(folder: folder)
    }

    /// Brings a capture's card back, on top of the stack (Recent Captures).
    func reopen(_ capture: FinishedCapture, on screen: NSScreen?) {
        if let screen { self.screen = screen }
        if let id = cardByFolder[capture.folder.path], let card = cards[id] {
            for pushedOut in stack.push(id) { close(pushedOut) }
            layout()
            card.panel.orderFrontRegardless()
            return
        }
        let id = nextReopenedID
        nextReopenedID -= 1
        show(capture, id: id)
    }

    /// Updates a card after a filmstrip trim.
    func update(_ capture: FinishedCapture, id: Int) {
        guard let card = cards[id] else { return }
        card.capture = capture
        card.view.state = .ready(capture, thumbnails: Self.thumbnails(for: capture))
    }

    func panelFrame(of id: Int) -> CGRect? {
        cards[id]?.panel.frame
    }

    /// The top of the card column, for placing the filmstrip above it.
    var columnTop: CGFloat? {
        stack.ids.compactMap { cards[$0]?.panel.frame.maxY }.max()
    }

    var currentScreen: NSScreen? { screen ?? NSScreen.main }

    private func wire(_ card: Card, id: Int) {
        card.view.onDismiss = { [weak self] in self?.close(id) }
        card.view.onClick = { [weak self, weak card] in
            guard let capture = card?.capture else { return }
            self?.onOpen(capture, id)
        }
        card.view.onHover = { [weak self, weak card] inside in
            card?.fade.hover(inside, at: ProcessInfo.processInfo.systemUptime)
            card?.panel.alphaValue = 1
            self?.startTimer()
        }
        card.view.onDropped = { [weak self, weak card] in
            card?.fade.dropped(at: ProcessInfo.processInfo.systemUptime)
            self?.startTimer()
        }
    }

    private func close(_ id: Int) {
        guard let card = cards.removeValue(forKey: id) else { return }
        if let folder = card.capture?.folder.path, cardByFolder[folder] == id { cardByFolder[folder] = nil }
        card.panel.orderOut(nil)
        stack.remove(id)
        layout()
    }

    private func layout() {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        for (id, frame) in stack.frames(in: visible, cardSize: CardView.size) {
            cards[id]?.panel.setFrame(frame, display: true)
        }
    }

    /// Animates fades and spinners while any card needs it.
    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.fadeStep, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    private func step() {
        let now = ProcessInfo.processInfo.systemUptime
        var busy = false
        for (id, card) in cards {
            if case .saving = card.view.state {
                card.view.spinnerPhase = CGFloat(now.truncatingRemainder(dividingBy: 1))
                busy = true
            }
            guard card.fade.isFading else { continue }
            if card.fade.isDone(at: now) {
                close(id)
            } else {
                card.panel.alphaValue = card.fade.opacity(at: now)
                busy = true
            }
        }
        if !busy {
            timer?.invalidate()
            timer = nil
        }
    }

    private static func makePanel(_ view: CardView) -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: CardView.size),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = view
        return panel
    }

    /// The first three rendered frames, scaled down.
    static func thumbnails(for capture: FinishedCapture) -> [NSImage] {
        capture.frameURLs.prefix(3).compactMap { url in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: thumbnailWidth * 2,
                  ] as CFDictionary)
            else { return nil }
            return NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2))
        }
    }
}
