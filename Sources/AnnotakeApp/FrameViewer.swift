import AppKit
import Carbon.HIToolbox

/// The current frame full screen (spec §3.4), because the strip's frames are too small to read: as large as fits on
/// a dark backdrop, with its caption above it. It shows and edits the strip's selection, so ← and → move the strip's
/// ring and ⌫ removes from it. Esc, Space, ✕ or a click on the backdrop go back to the filmstrip; Return applies the
/// removals.
final class FrameViewerView: NSView {
    /// Room at each side, for ‹ and ›.
    static let sideRoom: CGFloat = 80
    /// Room above the frame, for its caption and ✕.
    static let topRoom: CGFloat = 64
    /// Room below it, for the hint.
    static let bottomRoom: CGFloat = 48
    static let buttonSize: CGFloat = 44
    static let closeSize: CGFloat = 28
    static let backdrop = NSColor(white: 0, alpha: 0.9)
    static let hint = "← → flip through the frames · ⌫ removes or restores · Return applies · Esc goes back"

    let strip: FilmstripStripView
    var onBack: () -> Void = {}
    var onDone: () -> Void = {}
    /// Full-size frames by position: the current one and its neighbours, so flipping never waits on the disk.
    private var images: [Int: NSImage] = [:]
    private var loading: Set<Int> = []
    private var downPoint: CGPoint?

    init(strip: FilmstripStripView) {
        self.strip = strip
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var position: Int { strip.selection.current }

    private var tile: FilmstripTile? {
        strip.tiles.indices.contains(position) ? strip.tiles[position] : nil
    }

    private var isRemoved: Bool {
        tile.map { strip.selection.removed.contains($0.frameIndex) } ?? false
    }

    // MARK: Layout

    /// The frame, as large as fits between the side buttons, the caption, and the hint.
    var imageRect: CGRect {
        let room = CGRect(x: Self.sideRoom, y: Self.topRoom, width: bounds.width - 2 * Self.sideRoom,
                          height: bounds.height - Self.topRoom - Self.bottomRoom)
        guard let aspect = tile?.aspect, aspect > 0, room.width > 0, room.height > 0 else { return room }
        let size = room.width / room.height > aspect
            ? CGSize(width: (room.height * aspect).rounded(), height: room.height)
            : CGSize(width: room.width, height: (room.width / aspect).rounded())
        return CGRect(x: (room.midX - size.width / 2).rounded(), y: (room.midY - size.height / 2).rounded(),
                      width: size.width, height: size.height)
    }

    var previousRect: CGRect {
        CGRect(x: (Self.sideRoom - Self.buttonSize) / 2, y: bounds.midY - Self.buttonSize / 2,
               width: Self.buttonSize, height: Self.buttonSize)
    }

    var nextRect: CGRect {
        CGRect(x: bounds.maxX - (Self.sideRoom + Self.buttonSize) / 2, y: bounds.midY - Self.buttonSize / 2,
               width: Self.buttonSize, height: Self.buttonSize)
    }

    var closeRect: CGRect {
        CGRect(x: bounds.maxX - (Self.sideRoom + Self.closeSize) / 2, y: (Self.topRoom - Self.closeSize) / 2,
               width: Self.closeSize, height: Self.closeSize)
    }

    /// The Restore button on a removed frame.
    var restoreRect: CGRect {
        CGRect(x: imageRect.midX - 60, y: imageRect.midY - 18, width: 120, height: 36)
    }

    // MARK: Input

    override func keyDown(with event: NSEvent) {
        if strip.handleFrameKey(event) {
            frameChanged()
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape, kVK_Space:
            onBack()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onDone()
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        guard let downPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard ClickOrDrag.isClick(from: downPoint, to: point) else { return }
        if closeRect.insetBy(dx: -6, dy: -6).contains(point) {
            onBack()
        } else if previousRect.contains(point) {
            strip.moveCurrent(by: -1)
            frameChanged()
        } else if nextRect.contains(point) {
            strip.moveCurrent(by: 1)
            frameChanged()
        } else if isRemoved && restoreRect.contains(point) {
            strip.selection.toggleCurrent()
            frameChanged()
        } else if !imageRect.contains(point) {
            onBack()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { loadImages() }
    }

    /// Redraws, and loads the full-size frames around the current one.
    private func frameChanged() {
        needsDisplay = true
        loadImages()
    }

    // MARK: Full-size frames

    /// Keeps the current frame and its neighbours at full size, loading any that are missing off the main thread.
    /// Until a frame is loaded, its strip thumbnail stands in.
    private func loadImages() {
        let wanted = Set((position - 1)...(position + 1)).filter { strip.tiles.indices.contains($0) }
        images = images.filter { wanted.contains($0.key) }
        let maxPixels = max(bounds.width, bounds.height) * (window?.backingScaleFactor ?? 2)
        for index in wanted where images[index] == nil && !loading.contains(index) {
            loading.insert(index)
            let url = strip.tiles[index].url
            Task { [weak self] in
                let image = await Task.detached { FrameViewerView.fullImage(url, maxPixels: maxPixels) }.value
                guard let self else { return }
                loading.remove(index)
                guard let image, abs(index - position) <= 1 else { return }
                images[index] = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
                if index == position { needsDisplay = true }
            }
        }
    }

    /// A frame decoded now, at most `maxPixels` on its long side.
    nonisolated static func fullImage(_ url: URL, maxPixels: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        Self.backdrop.setFill()
        bounds.fill()
        guard let tile else { return }

        let rect = imageRect
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let image = images[position] ?? tile.image {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                       hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
        } else {
            NSColor(white: 0.2, alpha: 1).setFill()
            rect.fill()
        }
        if isRemoved {
            NSColor(white: 0, alpha: 0.65).setFill()
            rect.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 1, alpha: 0.15).setStroke()
        path.stroke()
        if isRemoved { drawCapsule("Restore", in: restoreRect) }

        drawCaption(tile.caption)
        drawSideButton(in: previousRect, pointingLeft: true, enabled: position > 0)
        drawSideButton(in: nextRect, pointingLeft: false, enabled: position < strip.tiles.count - 1)
        drawClose()
        let hintAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
                                                             .foregroundColor: NSColor(white: 0.6, alpha: 1)]
        let hintSize = (Self.hint as NSString).size(withAttributes: hintAttributes)
        (Self.hint as NSString).draw(at: CGPoint(x: bounds.midX - hintSize.width / 2,
                                                 y: bounds.maxY - (Self.bottomRoom + hintSize.height) / 2),
                                     withAttributes: hintAttributes)
    }

    /// e.g. `3/20 · 0:06 · Pressed Return`, then whether it's removed and how many will be.
    private func drawCaption(_ caption: String) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: style,
        ]
        let statusAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.6, alpha: 1), .paragraphStyle: style,
        ]
        let count = strip.selection.removed.count
        let status = [isRemoved ? "Removed" : nil, count > 0 ? "\(count) to remove" : nil]
            .compactMap { $0 }.joined(separator: " · ")
        let available = closeRect.minX - 16 - Self.sideRoom
        let captionWidth = min((caption as NSString).size(withAttributes: captionAttributes).width.rounded(.up), available)
        let captionHeight = (caption as NSString).size(withAttributes: captionAttributes).height
        let y = (Self.topRoom - captionHeight) / 2
        (caption as NSString).draw(in: CGRect(x: Self.sideRoom, y: y, width: captionWidth, height: captionHeight),
                                   withAttributes: captionAttributes)
        guard !status.isEmpty else { return }
        let statusX = Self.sideRoom + captionWidth + 12
        let statusHeight = (status as NSString).size(withAttributes: statusAttributes).height
        (status as NSString).draw(in: CGRect(x: statusX, y: (Self.topRoom - statusHeight) / 2 + 1,
                                             width: max(closeRect.minX - 16 - statusX, 0), height: statusHeight),
                                  withAttributes: statusAttributes)
    }

    private func drawSideButton(in rect: CGRect, pointingLeft: Bool, enabled: Bool) {
        NSColor(white: 1, alpha: enabled ? 0.14 : 0.05).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let chevron = NSBezierPath()
        let tip = pointingLeft ? rect.midX - 5 : rect.midX + 5
        let back = pointingLeft ? rect.midX + 3 : rect.midX - 3
        chevron.move(to: CGPoint(x: back, y: rect.midY - 9))
        chevron.line(to: CGPoint(x: tip, y: rect.midY))
        chevron.line(to: CGPoint(x: back, y: rect.midY + 9))
        chevron.lineWidth = 2.2
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        NSColor(white: 1, alpha: enabled ? 0.9 : 0.25).setStroke()
        chevron.stroke()
    }

    private func drawClose() {
        let rect = closeRect
        NSColor(white: 1, alpha: 0.14).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let inset = rect.insetBy(dx: 9, dy: 9)
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: inset.minX, y: inset.minY))
        cross.line(to: CGPoint(x: inset.maxX, y: inset.maxY))
        cross.move(to: CGPoint(x: inset.maxX, y: inset.minY))
        cross.line(to: CGPoint(x: inset.minX, y: inset.maxY))
        cross.lineWidth = 1.8
        cross.lineCapStyle = .round
        NSColor.white.setStroke()
        cross.stroke()
    }

    private func drawCapsule(_ title: String, in rect: CGRect) {
        NSColor(white: 1, alpha: 0.25).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                                 withAttributes: attributes)
    }
}

/// Full screen's panel: it takes the keys without activating the app, over the filmstrip and the cards.
final class FrameViewerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
