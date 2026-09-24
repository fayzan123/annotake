import AppKit

// Spike D: a floating card that drags out 20 PNGs. Throwaway.

let dragSpike = DragSpike()

final class DragSpike {
    private var card: NSPanel?
    private let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("flipbook-drag")

    func show() {
        let files = makeImages()
        guard !files.isEmpty else { return }
        card?.orderOut(nil)

        let size = NSSize(width: 220, height: 140)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let f = screen.visibleFrame
        let panel = NSPanel(contentRect: NSRect(x: f.maxX - size.width - 20, y: f.minY + 20,
                                                width: size.width, height: size.height),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let view = CardView(frame: NSRect(origin: .zero, size: size), files: files)
        view.onDropped = { [weak panel] in panel?.orderOut(nil) }
        panel.contentView = view
        panel.orderFrontRegardless()
        card = panel
        log("drag card shown with \(files.count) PNGs from \(dir.path)")
    }

    private func makeImages() -> [URL] {
        try? FileManager.default.removeItem(at: dir)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            log("drag spike: cannot create \(dir.path): \(error)")
            return []
        }
        var urls: [URL] = []
        for n in 1...20 {
            let url = dir.appendingPathComponent(String(format: "%02d_0m%02ds.png", n, n - 1))
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1920, pixelsHigh: 1200,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor(calibratedHue: CGFloat(n) / 20, saturation: 0.35, brightness: 0.95, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 1920, height: 1200).fill()
            let text = "\(n)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 800),
                                                        .foregroundColor: NSColor.black]
            let ts = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (1920 - ts.width) / 2, y: (1200 - ts.height) / 2), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            do { try data.write(to: url); urls.append(url) } catch { log("write failed \(url.lastPathComponent): \(error)") }
        }
        return urls
    }
}

final class CardView: NSView, NSDraggingSource {
    let files: [URL]
    var onDropped: (() -> Void)?
    private var dragStarted = false
    private let thumb: NSImage?

    init(frame: NSRect, files: [URL]) {
        self.files = files
        self.thumb = NSImage(contentsOf: files[0])
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Stacked thumbnails.
        for i in (0..<3).reversed() {
            let r = NSRect(x: 16 + CGFloat(i) * 6, y: 40 - CGFloat(i) * 6, width: 112, height: 70)
            NSColor.black.withAlphaComponent(0.15).setFill()
            r.offsetBy(dx: 1, dy: -1).fill()
            thumb?.draw(in: r)
        }
        let title = "\(files.count) frames" as NSString
        title.draw(at: NSPoint(x: 150, y: 90), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 15),
                                                                .foregroundColor: NSColor.labelColor])
        ("drag me" as NSString).draw(at: NSPoint(x: 150, y: 68),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                                                      .foregroundColor: NSColor.secondaryLabelColor])
    }

    override func mouseDown(with event: NSEvent) { dragStarted = false }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted else { return }
        dragStarted = true
        let items: [NSDraggingItem] = files.enumerated().map { i, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(i, 10)) * 3
            item.setDraggingFrame(NSRect(x: 16 + offset, y: 40 - offset, width: 112, height: 70),
                                  contents: i == 0 ? thumb : NSImage(contentsOf: url))
            return item
        }
        log("drag began with \(items.count) items, first=\(files.first!.lastPathComponent)")
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        log("drag ended at \(Int(screenPoint.x)),\(Int(screenPoint.y)) operation=\(operation.rawValue) "
            + "(frontmost now: \(app))")
        if operation != [] { onDropped?() }
    }
}
