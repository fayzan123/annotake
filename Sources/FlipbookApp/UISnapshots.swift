import AppKit
import FlipbookCore
import FlipbookExport

/// `Flipbook --render-ui <dir>`: draws every panel and window state offscreen to PNGs, so a session can
/// look at the UI it builds. Needs no permissions.
enum UISnapshots {
    /// Snapshots are drawn at Retina scale.
    static let scale: CGFloat = 2

    @MainActor
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        write(pill(PillText.recording(mode: .hold, elapsed: 4, frames: 3, maxFrames: 20, trigger: .rightCommand)),
              to: directory, as: "pill-hold.png")
        write(pill(PillText.recording(mode: .handsFree, elapsed: 12, frames: 5, maxFrames: 20, trigger: .rightCommand)),
              to: directory, as: "pill-handsfree.png")
        write(pill(PillText.message(.screenRecordingNeeded), button: "Open Settings"),
              to: directory, as: "pill-message.png")

        write(CardView(state: .saving(duration: 21)), to: directory, as: "card-saving.png")
        let ready = CardView(state: .ready(sampleCapture(frames: 8, duration: 21), thumbnails: sampleThumbnails()))
        write(ready, to: directory, as: "card-ready.png")
        ready.hovering = true
        write(ready, to: directory, as: "card-ready-hover.png")
        write(CardView(state: .failed(folder: URL(fileURLWithPath: NSHomeDirectory()))), to: directory, as: "card-error.png")
    }

    /// A finished capture that exists only in memory, for drawing.
    static func sampleCapture(frames: Int, duration: TimeInterval) -> FinishedCapture {
        let context = FrameContext(app: "Safari", window: "Checkout")
        let picked = (0..<frames).map {
            PickedFrame(frameIndex: $0, time: Double($0) * duration / Double(frames), context: context, actions: [],
                        reason: .visual)
        }
        let manifest = CaptureManifest(name: "2026-09-24 at 14.05.12", target: "Screen: Built-in Retina Display",
                                       created: Date(), render: RenderOptions(captionStrip: true, clickMarkers: true),
                                       result: PickResult(frames: picked, candidateCount: frames, duration: duration),
                                       removed: [])
        return FinishedCapture(folder: URL(fileURLWithPath: NSTemporaryDirectory()), manifest: manifest)
    }

    /// Mock screenshots: a window with a toolbar, some content, and a caption strip.
    static func sampleThumbnails(count: Int = 3) -> [NSImage] {
        let accents: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple, .systemPink, .systemTeal]
        return (0..<count).map { index in
            NSImage(size: CGSize(width: 416, height: 315), flipped: true) { rect in
                NSColor(white: 0.96, alpha: 1).setFill()
                rect.fill()
                NSColor(white: 0.86, alpha: 1).setFill()
                CGRect(x: 0, y: 0, width: rect.width, height: 30).fill()
                accents[index % accents.count].setFill()
                NSBezierPath(roundedRect: CGRect(x: 24, y: 56, width: 150, height: 34), xRadius: 6, yRadius: 6).fill()
                NSColor(white: 0.8, alpha: 1).setFill()
                for row in 0..<5 {
                    CGRect(x: 24, y: 110 + CGFloat(row) * 24, width: 260 - CGFloat((row + index) % 3) * 50, height: 10).fill()
                }
                NSColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1).setFill()
                CGRect(x: 0, y: rect.height - 34, width: rect.width, height: 34).fill()
                NSColor.white.setFill()
                CGRect(x: 12, y: rect.height - 25, width: 180, height: 6).fill()
                return true
            }
        }
    }

    @MainActor
    private static func pill(_ text: String, button: String? = nil) -> NSView {
        let view = PillView(frame: .zero)
        view.text = text
        if let button { view.setButton(title: button, action: nil, target: nil) }
        view.frame = NSRect(origin: .zero, size: view.fittingSizeForContent)
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// The view's pixels as a PNG, at `scale`.
    @MainActor
    static func png(of view: NSView) -> Data? {
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor
    static func write(_ view: NSView, to directory: URL, as name: String) {
        guard let data = png(of: view) else { return }
        try? data.write(to: directory.appending(path: name), options: .atomic)
    }
}
