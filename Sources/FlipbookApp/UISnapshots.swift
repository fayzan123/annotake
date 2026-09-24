import AppKit

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
