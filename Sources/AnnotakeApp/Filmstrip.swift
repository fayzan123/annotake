import AppKit
import AnnotakeCore
import AnnotakeExport
import Carbon.HIToolbox

/// Which frames the filmstrip will remove on close, and the current frame, which the keys act on (spec §3.4).
/// The last frame can't be removed.
struct FilmstripSelection {
    private let frameIndices: [Int]
    private(set) var removed: Set<Int> = []
    /// The current frame's position in the strip.
    private(set) var current = 0

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

    /// Moves the current frame, stopping at the ends.
    mutating func moveCurrent(by offset: Int) {
        moveCurrent(to: current + offset)
    }

    mutating func moveCurrent(to position: Int) {
        guard !frameIndices.isEmpty else { return }
        current = min(max(position, 0), frameIndices.count - 1)
    }

    /// Removes the current frame, or restores it.
    mutating func toggleCurrent() {
        guard frameIndices.indices.contains(current) else { return }
        toggle(frameIndices[current])
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
/// a frame can be dragged out on its own. A ring marks the current frame, which the keys move and remove.
final class FilmstripStripView: NSView, NSDraggingSource {
    static let frameHeight: CGFloat = 200
    static let captionHeight: CGFloat = 22
    static let spacing: CGFloat = 12
    static let closeSize: CGFloat = 22
    static let captionFont = NSFont.systemFont(ofSize: 11)
    /// Room around the frames for the ring.
    static let ringInset: CGFloat = 5
    /// The ring's line runs this far outside its frame.
    static let ringOffset: CGFloat = 3.5
    static let ringWidth: CGFloat = 2.5
    static let height = ringInset + frameHeight + captionHeight

    var tiles: [FilmstripTile] = [] {
        didSet { resize() }
    }

    var selection = FilmstripSelection(frameIndices: []) {
        didSet {
            needsDisplay = true
            onSelectionChange()
        }
    }

    var hovered: Int? {
        didSet { needsDisplay = true }
    }

    var onSelectionChange: () -> Void = {}
    /// A click on a frame, or Space: show the current frame full screen.
    var onShowFrame: () -> Void = {}
    private var downPoint: CGPoint?
    private var dragStarted = false

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func tileRects() -> [CGRect] {
        var x = Self.ringInset
        return tiles.map { tile in
            let width = (Self.frameHeight * tile.aspect).rounded()
            defer { x += width + Self.spacing }
            return CGRect(x: x, y: Self.ringInset, width: width, height: Self.frameHeight)
        }
    }

    private func resize() {
        let width = (tileRects().last?.maxX ?? 0) + Self.ringInset
        setFrameSize(CGSize(width: width, height: Self.height))
        needsDisplay = true
    }

    func closeRect(for rect: CGRect) -> CGRect {
        CGRect(x: rect.maxX - Self.closeSize - 6, y: rect.minY + 6, width: Self.closeSize, height: Self.closeSize)
    }

    func restoreRect(for rect: CGRect) -> CGRect {
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

    /// ✕ removes a frame and Restore brings it back; a click anywhere else on a frame shows it full screen.
    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        guard let downPoint, !dragStarted, let position = tile(at: downPoint) else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard ClickOrDrag.isClick(from: downPoint, to: point) else { return }
        selection.moveCurrent(to: position)
        let rect = tileRects()[position]
        let frameIndex = tiles[position].frameIndex
        let button = selection.removed.contains(frameIndex) ? restoreRect(for: rect)
            : selection.canRemove(frameIndex) ? closeRect(for: rect) : nil
        if let button, button.insetBy(dx: -4, dy: -4).contains(point) {
            selection.toggle(frameIndex)
        } else {
            onShowFrame()
        }
    }

    /// Space shows the current frame full screen; the frame keys are below. Return and Esc go on to the panel.
    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Space {
            onShowFrame()
        } else if !handleFrameKey(event) {
            super.keyDown(with: event)
        }
    }

    /// The keys the strip and full screen share: ← and → move the current frame, and ⌫ removes it or restores it.
    /// False for any other key.
    func handleFrameKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_LeftArrow:
            moveCurrent(by: -1)
        case kVK_RightArrow:
            moveCurrent(by: 1)
        case kVK_Delete, kVK_ForwardDelete:
            // Held down, it would flip the frame back and forth.
            if !event.isARepeat { selection.toggleCurrent() }
        default:
            return false
        }
        return true
    }

    /// Moves the ring and scrolls it into view, with a little room on the side it moved to.
    func moveCurrent(by offset: Int) {
        selection.moveCurrent(by: offset)
        let rects = tileRects()
        guard rects.indices.contains(selection.current) else { return }
        scrollToVisible(rects[selection.current].insetBy(dx: -(Self.ringInset + Self.spacing), dy: 0).intersection(bounds))
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func draw(_ dirtyRect: NSRect) {
        let dirty = dirtyRect.insetBy(dx: -Self.ringInset, dy: -Self.ringInset)
        for (position, rect) in tileRects().enumerated() where rect.intersects(dirty) {
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
            if position == selection.current {
                let radius = 6 + Self.ringOffset
                let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -Self.ringOffset, dy: -Self.ringOffset),
                                        xRadius: radius, yRadius: radius)
                ring.lineWidth = Self.ringWidth
                NSColor.controlAccentColor.setStroke()
                ring.stroke()
            }

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

/// The filmstrip's content: a header with the capture's name, how many frames will be removed, and a ✕, then the
/// scrolling strip.
final class FilmstripView: NSView {
    static let padding: CGFloat = 16
    static let headerHeight: CGFloat = 28
    /// Room under the captions for the scroller, so it never covers them.
    static let scrollerHeight = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    static let height = padding * 2 + headerHeight + FilmstripStripView.frameHeight + FilmstripStripView.captionHeight
        + scrollerHeight
    static let background = NSColor(white: 0.1, alpha: 0.96)
    static let hint = "Click a frame or press Space to see it full screen · ← → pick a frame · ⌫ removes or restores · "
        + "Return applies · drag a frame out on its own"

    let strip = FilmstripStripView(frame: .zero)
    let scrollView = FilmstripScrollView(frame: .zero)
    var title = "" {
        didSet { needsDisplay = true }
    }

    var onClose: () -> Void = {}

    /// The title, then how many frames will be removed, e.g. `… · 20 frames · 3 to remove`.
    var heading: String {
        let count = strip.selection.removed.count
        return count == 0 ? title : "\(title) · \(count) to remove"
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        // The scroller style follows System Settings: always shown while a mouse is plugged in.
        scrollView.autohidesScrollers = true
        scrollView.contentView = FlippedClipView()
        scrollView.drawsBackground = false
        scrollView.documentView = strip
        addSubview(scrollView)
        strip.onSelectionChange = { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    private var closeRect: CGRect {
        CGRect(x: bounds.maxX - Self.padding - 20, y: Self.padding + 2, width: 20, height: 20)
    }

    /// The strip reaches past the padding by the ring's room, so the frames line up with the title.
    override func layout() {
        super.layout()
        let inset = Self.padding - FilmstripStripView.ringInset
        scrollView.frame = CGRect(x: inset, y: Self.padding + Self.headerHeight - FilmstripStripView.ringInset,
                                  width: bounds.width - 2 * inset,
                                  height: FilmstripStripView.height + Self.scrollerHeight)
    }

    override func mouseUp(with event: NSEvent) {
        if closeRect.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil)) { onClose() }
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        let headingAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                                .foregroundColor: NSColor.white]
        (heading as NSString).draw(at: CGPoint(x: Self.padding, y: Self.padding + 2), withAttributes: headingAttributes)
        let hintAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
                                                             .foregroundColor: NSColor(white: 0.6, alpha: 1)]
        // Truncated, so it never runs under the ✕ on a narrow screen.
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let hintX = Self.padding + (heading as NSString).size(withAttributes: headingAttributes).width + 12
        (Self.hint as NSString).draw(in: CGRect(x: hintX, y: Self.padding + 4, width: max(closeRect.minX - 12 - hintX, 0),
                                                height: 16),
                                     withAttributes: hintAttributes.merging([.paragraphStyle: style]) { $1 })

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

/// Keeps the strip at the top, with the scroller's room below it.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// A mouse wheel only turns up and down, and the strip only scrolls sideways, so the wheel scrolls it sideways.
final class FilmstripScrollView: NSScrollView {
    /// How far one notch of the wheel moves the strip.
    static let wheelStep: CGFloat = 40

    override func scrollWheel(with event: NSEvent) {
        guard !event.hasPreciseScrollingDeltas, event.scrollingDeltaX == 0, let documentView else {
            return super.scrollWheel(with: event)
        }
        let end = max(documentView.frame.width - contentView.bounds.width, 0)
        let x = min(max(contentView.bounds.minX - event.scrollingDeltaY * Self.wheelStep, 0), end)
        contentView.scroll(to: CGPoint(x: x, y: contentView.bounds.minY))
        reflectScrolledClipView(contentView)
    }
}

/// A panel that can become key without activating the app, so keys reach it. Return and Esc close it, which
/// applies the removals.
final class FilmstripPanel: NSPanel {
    var onClose: () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onClose()
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter:
            onClose()
        default:
            super.keyDown(with: event)
        }
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
    /// The current frame full screen, over the filmstrip.
    private var viewer: FrameViewerPanel?
    private var capture: FinishedCapture?
    private var cardID: Int?
    private var closing = false
    /// A trim started: its card shows "Saving…" until `onTrimmed`.
    var onTrimStarted: (Int) -> Void = { _ in }
    /// A trim finished, or failed and left the capture as it was; its card shows the frames.
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
        view.strip.onShowFrame = { [weak self] in self?.showFullScreen() }

        guard let screen = cards.currentScreen else { return }
        let visible = screen.visibleFrame
        let width = min(Self.maxWidth, visible.width * Self.screenFraction)
        let bottom = min((cards.columnTop ?? visible.minY + CardStack.inset) + Self.gapAboveCards,
                         visible.maxY - FilmstripView.height)
        let frame = CGRect(x: visible.maxX - CardStack.inset - width, y: bottom, width: width, height: FilmstripView.height)

        let panel = Self.makePanel(view, frame: frame)
        panel.delegate = self
        panel.onClose = { [weak self] in self?.close() }
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.view = view
        self.capture = capture
        self.cardID = cardID
    }

    /// The filmstrip's panel, with the strip taking the keys.
    static func makePanel(_ view: FilmstripView, frame: CGRect) -> FilmstripPanel {
        let panel = FilmstripPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless],
                                   backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = view
        panel.initialFirstResponder = view.strip
        panel.makeFirstResponder(view.strip)
        return panel
    }

    /// Full screen's panel, over the filmstrip and the cards, with the viewer taking the keys.
    static func makeViewerPanel(_ view: FrameViewerView, frame: CGRect) -> FrameViewerPanel {
        let panel = FrameViewerPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless],
                                     backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = view
        panel.initialFirstResponder = view
        panel.makeFirstResponder(view)
        return panel
    }

    /// Shows the current frame full screen, on the filmstrip's screen.
    private func showFullScreen() {
        guard viewer == nil, let panel, let view, let screen = panel.screen ?? NSScreen.main else { return }
        let viewerView = FrameViewerView(strip: view.strip)
        viewerView.onBack = { [weak self] in self?.closeFullScreen() }
        viewerView.onDone = { [weak self] in self?.close() }
        let viewer = Self.makeViewerPanel(viewerView, frame: screen.frame)
        viewer.delegate = self
        // Set before it takes the keys, so the filmstrip doesn't take that for a click outside.
        self.viewer = viewer
        viewer.makeKeyAndOrderFront(nil)
    }

    /// Back to the filmstrip, its ring on the frame full screen showed last.
    private func closeFullScreen() {
        guard let viewer else { return }
        viewer.delegate = nil
        viewer.orderOut(nil)
        self.viewer = nil
        panel?.makeKeyAndOrderFront(nil)
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
        // Full screen taking the keys from the filmstrip.
        if viewer != nil, notification.object as? NSWindow === panel { return }
        // A click outside, or a switch to another app while full screen.
        close()
    }

    func close() {
        guard !closing, let panel, let view, let capture, let cardID else { return }
        closing = true
        defer { closing = false }
        let removed = view.strip.selection.removed
        if let viewer {
            viewer.delegate = nil
            viewer.orderOut(nil)
            self.viewer = nil
        }
        panel.delegate = nil
        panel.orderOut(nil)
        self.panel = nil
        self.view = nil
        self.capture = nil
        guard !removed.isEmpty else { return }
        let folder = capture.folder
        log("filmstrip: removing \(removed.count) frame(s)")
        onTrimStarted(cardID)
        Task { [weak self] in
            let trimmed = await Task.detached {
                Result { try CaptureExporter.remove(frameIndices: removed, from: folder) }
            }.value
            switch trimmed {
            case .success(let trimmed):
                self?.onTrimmed(trimmed, cardID)
            case .failure(let error):
                log("filmstrip trim failed: \(error)")
                // The re-renders are staged first, so a failed trim leaves the capture as it was.
                self?.onTrimmed(capture, cardID)
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
