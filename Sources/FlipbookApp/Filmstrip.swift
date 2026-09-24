import AppKit
import FlipbookCore
import FlipbookExport

/// Which frames the filmstrip will remove on close (spec §3.4). The last frame can't be removed.
struct FilmstripSelection {
    private let frameIndices: [Int]
    private(set) var removed: Set<Int> = []

    init(frameIndices: [Int]) {
        self.frameIndices = frameIndices
    }

    /// False when it's the last frame not removed.
    func canRemove(_ frameIndex: Int) -> Bool {
        !removed.contains(frameIndex) && frameIndices.count - removed.count > 1
    }

    /// Removes the frame, or restores it. Removing is a no-op when it's the last one left.
    mutating func toggle(_ frameIndex: Int) {
        if removed.contains(frameIndex) {
            removed.remove(frameIndex)
        } else if canRemove(frameIndex) {
            removed.insert(frameIndex)
        }
    }
}

/// One frame in the strip.
struct FilmstripTile {
    let frameIndex: Int
    let url: URL
    let caption: String
    let image: NSImage?
    /// Width ÷ height of the rendered frame.
    let aspect: CGFloat
}

/// The row of frames, drawn by hand. ✕ on hover removes a frame, which then dims and offers Restore;
/// a frame can be dragged out on its own.
final class FilmstripStripView: NSView, NSDraggingSource {
    static let frameHeight: CGFloat = 200
    static let captionHeight: CGFloat = 22
    static let spacing: CGFloat = 12
    static let closeSize: CGFloat = 22
    static let captionFont = NSFont.systemFont(ofSize: 11)

    var tiles: [FilmstripTile] = [] {
        didSet { resize() }
    }

    var selection = FilmstripSelection(frameIndices: []) {
        didSet { needsDisplay = true }
    }

    var hovered: Int? {
        didSet { needsDisplay = true }
    }

    var onToggle: (Int) -> Void = { _ in }
    private var downPoint: CGPoint?
    private var dragStarted = false

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func tileRects() -> [CGRect] {
        var x: CGFloat = 0
        return tiles.map { tile in
            let width = (Self.frameHeight * tile.aspect).rounded()
            defer { x += width + Self.spacing }
            return CGRect(x: x, y: 0, width: width, height: Self.frameHeight)
        }
    }

    private func resize() {
        let width = (tileRects().last?.maxX ?? 0)
        setFrameSize(CGSize(width: max(width, 1), height: Self.frameHeight + Self.captionHeight))
        needsDisplay = true
    }

    private func closeRect(for rect: CGRect) -> CGRect {
        CGRect(x: rect.maxX - Self.closeSize - 6, y: rect.minY + 6, width: Self.closeSize, height: Self.closeSize)
    }

    private func restoreRect(for rect: CGRect) -> CGRect {
        CGRect(x: rect.midX - 40, y: rect.midY - 13, width: 80, height: 26)
    }

    private func tile(at point: CGPoint) -> Int? {
        tileRects().firstIndex { $0.contains(point) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = tile(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint, !dragStarted, let position = tile(at: downPoint) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let tile = tiles[position]
        guard !ClickOrDrag.isClick(from: downPoint, to: point), !selection.removed.contains(tile.frameIndex) else { return }
        dragStarted = true
        let item = NSDraggingItem(pasteboardWriter: tile.url as NSURL)
        item.setDraggingFrame(tileRects()[position], contents: tile.image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        guard let downPoint, !dragStarted, let position = tile(at: downPoint) else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard ClickOrDrag.isClick(from: downPoint, to: point) else { return }
        let rect = tileRects()[position]
        let frameIndex = tiles[position].frameIndex
        let removed = selection.removed.contains(frameIndex)
        if removed || closeRect(for: rect).insetBy(dx: -4, dy: -4).contains(point) {
            onToggle(frameIndex)
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func draw(_ dirtyRect: NSRect) {
        for (position, rect) in tileRects().enumerated() where rect.intersects(dirtyRect.insetBy(dx: -1, dy: -1)) {
            let tile = tiles[position]
            let removed = selection.removed.contains(tile.frameIndex)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            if let image = tile.image {
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else {
                NSColor(white: 0.3, alpha: 1).setFill()
                rect.fill()
            }
            if removed {
                NSColor(white: 0.05, alpha: 0.72).setFill()
                rect.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 1, alpha: 0.15).setStroke()
            path.stroke()

            if removed {
                drawCapsule("Restore", in: restoreRect(for: rect))
            } else if hovered == position && selection.canRemove(tile.frameIndex) {
                drawClose(in: closeRect(for: rect))
            }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            (tile.caption as NSString).draw(
                in: CGRect(x: rect.minX, y: rect.maxY + 5, width: rect.width, height: Self.captionHeight - 5),
                withAttributes: [.font: Self.captionFont, .paragraphStyle: style,
                                 .foregroundColor: removed ? NSColor(white: 0.45, alpha: 1) : NSColor(white: 0.85, alpha: 1)])
        }
    }

    private func drawCapsule(_ title: String, in rect: CGRect) {
        NSColor(white: 1, alpha: 0.25).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                                 withAttributes: attributes)
    }

    private func drawClose(in rect: CGRect) {
        NSColor(white: 0.1, alpha: 0.85).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let inset = rect.insetBy(dx: 7, dy: 7)
        let cross = NSBezierPath()
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

/// The filmstrip's content: a header with the capture's name and a ✕, then the scrolling strip.
final class FilmstripView: NSView {
    static let padding: CGFloat = 16
    static let headerHeight: CGFloat = 28
    static let height = padding * 2 + headerHeight + FilmstripStripView.frameHeight + FilmstripStripView.captionHeight
    static let background = NSColor(white: 0.1, alpha: 0.96)

    let strip = FilmstripStripView(frame: .zero)
    let scrollView = NSScrollView(frame: .zero)
    var title = "" {
        didSet { needsDisplay = true }
    }

    var onClose: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = strip
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    private var closeRect: CGRect {
        CGRect(x: bounds.maxX - Self.padding - 20, y: Self.padding + 2, width: 20, height: 20)
    }

    override func layout() {
        super.layout()
        scrollView.frame = CGRect(x: Self.padding, y: Self.padding + Self.headerHeight,
                                  width: bounds.width - 2 * Self.padding,
                                  height: FilmstripStripView.frameHeight + FilmstripStripView.captionHeight)
    }

    override func mouseUp(with event: NSEvent) {
        if closeRect.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil)) { onClose() }
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        (title as NSString).draw(at: CGPoint(x: Self.padding, y: Self.padding + 2),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                  .foregroundColor: NSColor.white])
        let hint = "Hover a frame and click ✕ to remove it · drag a frame out on its own" as NSString
        let hintAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
                                                             .foregroundColor: NSColor(white: 0.6, alpha: 1)]
        let titleWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width
        hint.draw(at: CGPoint(x: Self.padding + titleWidth + 12, y: Self.padding + 4), withAttributes: hintAttributes)

        NSColor(white: 0.35, alpha: 1).setFill()
        NSBezierPath(ovalIn: closeRect).fill()
        let inset = closeRect.insetBy(dx: 6.5, dy: 6.5)
        let cross = NSBezierPath()
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

/// A panel that can become key without activating the app, so Esc reaches it.
final class FilmstripPanel: NSPanel {
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}

/// One filmstrip at a time (spec §3.4), above the card column. Closing it with removals trims the
/// capture in the background, then refreshes its card.
@MainActor
final class FilmstripController: NSObject, NSWindowDelegate {
    static let maxWidth: CGFloat = 1200
    static let screenFraction: CGFloat = 0.9
    static let gapAboveCards: CGFloat = 10
    /// Frames are loaded at this height, in pixels.
    static let thumbnailHeight: CGFloat = 400

    private var panel: FilmstripPanel?
    private var view: FilmstripView?
    private var capture: FinishedCapture?
    private var cardID: Int?
    private var closing = false
    /// A trim finished; its card shows the new frames.
    var onTrimmed: (FinishedCapture, Int) -> Void = { _, _ in }

    var openCardID: Int? { panel == nil ? nil : cardID }

    /// Opens the filmstrip for the capture, or closes it when it's already open for that card.
    func toggle(_ capture: FinishedCapture, cardID: Int, cards: CardController) {
        if panel != nil {
            let same = self.cardID == cardID
            close()
            if same { return }
        }
        open(capture, cardID: cardID, cards: cards)
    }

    private func open(_ capture: FinishedCapture, cardID: Int, cards: CardController) {
        let view = FilmstripView(frame: .zero)
        Self.configure(view, capture: capture)
        view.onClose = { [weak self] in self?.close() }
        view.strip.onToggle = { [weak view] frameIndex in view?.strip.selection.toggle(frameIndex) }

        guard let screen = cards.currentScreen else { return }
        let visible = screen.visibleFrame
        let width = min(Self.maxWidth, visible.width * Self.screenFraction)
        let bottom = min((cards.columnTop ?? visible.minY + CardStack.inset) + Self.gapAboveCards,
                         visible.maxY - FilmstripView.height)
        let frame = CGRect(x: visible.maxX - CardStack.inset - width, y: bottom, width: width, height: FilmstripView.height)

        let panel = FilmstripPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless],
                                   backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = view
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.view = view
        self.capture = capture
        self.cardID = cardID
    }

    /// Loads the capture's frames and captions into the view.
    static func configure(_ view: FilmstripView, capture: FinishedCapture) {
        let frames = capture.manifest.result.frames
        view.title = RecentCaptures.title(for: capture)
        view.strip.tiles = zip(frames, capture.frameURLs).enumerated().map { position, pair in
            let (frame, url) = pair
            let image = thumbnail(url)
            let aspect = image.map { $0.size.width / max($0.size.height, 1) } ?? 1.32
            return FilmstripTile(frameIndex: frame.frameIndex, url: url,
                                 caption: Captions.line1(for: frame, number: position + 1, total: frames.count),
                                 image: image, aspect: aspect)
        }
        view.strip.selection = FilmstripSelection(frameIndices: frames.map(\.frameIndex))
    }

    func windowDidResignKey(_ notification: Notification) {
        // A click outside.
        close()
    }

    func close() {
        guard !closing, let panel, let view, let capture, let cardID else { return }
        closing = true
        defer { closing = false }
        let removed = view.strip.selection.removed
        panel.delegate = nil
        panel.orderOut(nil)
        self.panel = nil
        self.view = nil
        self.capture = nil
        guard !removed.isEmpty else { return }
        let folder = capture.folder
        log("filmstrip: removing \(removed.count) frame(s)")
        Task { [weak self] in
            let trimmed = await Task.detached {
                Result { try CaptureExporter.remove(frameIndices: removed, from: folder) }
            }.value
            switch trimmed {
            case .success(let capture): self?.onTrimmed(capture, cardID)
            case .failure(let error): log("filmstrip trim failed: \(error)")
            }
        }
    }

    private static func thumbnail(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: thumbnailHeight * 2,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2))
    }
}
