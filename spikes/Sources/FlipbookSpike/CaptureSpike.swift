import AppKit
import CoreImage
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

// Spike C: capture start latency, idle frames, dirty rects, exclusion. Throwaway.

let captureSpike = CaptureSpike()

final class CaptureSpike: NSObject, SCStreamOutput, SCStreamDelegate {
    private var pill: NSPanel?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "capture-spike")
    private var running = false
    private var run = 0

    // Touched only on `queue` while a run is live.
    private var startCall = DispatchTime.now()
    private var firstCompleteMs: Double?
    private var counts = [Int: Int]()
    private var frameIndex = 0
    private var latest: CVPixelBuffer?
    private var saved = 0
    private var saveTimer: DispatchSourceTimer?
    private let ci = CIContext()
    private let framesDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/flipbook-spike-frames")

    // MARK: pill

    func showPill() {
        let size = NSSize(width: 320, height: 34)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .systemRed
        let label = NSTextField(labelWithString: "PILL — must not appear in frames")
        label.font = .boldSystemFont(ofSize: 15)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 7, width: size.width, height: 20)
        panel.contentView?.addSubview(label)
        pill = panel
        placePill(on: NSScreen.main)
        panel.orderFrontRegardless()
        log("pill panel shown")
    }

    private func placePill(on screen: NSScreen?) {
        guard let pill, let screen else { return }
        let f = screen.visibleFrame
        pill.setFrameOrigin(NSPoint(x: f.midX - pill.frame.width / 2, y: f.minY + 24))
    }

    // MARK: run

    func start() {
        guard !running else { log("capture already running"); return }
        running = true
        run += 1
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
        // Put the pill on the recorded screen so exclusion is actually tested there.
        placePill(on: screen)
        log("capture run \(run): screen \"\(screen.localizedName)\" displayID=\(displayID) "
            + "frame=\(screen.frame) backingScale=\(screen.backingScaleFactor)")
        Task { await self.capture(displayID: displayID) }
    }

    private func capture(displayID: CGDirectDisplayID) async {
        let t0 = DispatchTime.now()
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            log("SCShareableContent failed after \(since(t0)) ms: \(error)")
            running = false
            return
        }
        log("SCShareableContent in \(since(t0)) ms: \(content.displays.count) displays, "
            + "\(content.applications.count) apps, \(content.windows.count) windows")

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            log("no SCDisplay for \(displayID)")
            running = false
            return
        }

        let ownID = Bundle.main.bundleIdentifier ?? ""
        let ncID = "com.apple.notificationcenterui"
        var excluded = content.applications.filter { $0.bundleIdentifier == ownID || $0.bundleIdentifier == ncID }
        if !excluded.contains(where: { $0.bundleIdentifier == ncID }) {
            // With onScreenWindowsOnly: true, Notification Center may be missing while no banner is showing.
            log("\(ncID) NOT in on-screen-only content; querying all windows")
            let t1 = DispatchTime.now()
            if let all = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
                log("SCShareableContent (all windows) in \(since(t1)) ms")
                excluded += all.applications.filter { $0.bundleIdentifier == ncID }
            }
        }
        log("excluding apps: \(excluded.map { $0.bundleIdentifier })")
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])

        let mode = CGDisplayCopyDisplayMode(displayID)
        let pw = mode?.pixelWidth ?? display.width
        let ph = mode?.pixelHeight ?? display.height
        let s = 1920.0 / Double(max(pw, ph))
        let cfg = SCStreamConfiguration()
        cfg.width = Int((Double(pw) * s).rounded()) & ~1
        cfg.height = Int((Double(ph) * s).rounded()) & ~1
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = true
        cfg.queueDepth = 6
        log("display \(display.width)×\(display.height) pt, \(pw)×\(ph) px → output \(cfg.width)×\(cfg.height)")

        queue.sync {
            firstCompleteMs = nil
            counts = [:]
            frameIndex = 0
            latest = nil
            saved = 0
        }
        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

        let stream = SCStream(filter: filter, configuration: cfg, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            queue.sync { startCall = .now() }
            try await stream.startCapture()
            log("startCapture() returned after \(since(startCall)) ms")
        } catch {
            log("startCapture failed: \(error)")
            running = false
            return
        }
        self.stream = stream

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.saveLatest() }
        timer.resume()
        saveTimer = timer

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.postNotification() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { Task { await self.finish() } }
    }

    private func finish() async {
        saveTimer?.cancel()
        saveTimer = nil
        do { try await stream?.stopCapture() } catch { log("stopCapture error: \(error)") }
        stream = nil
        queue.sync {
            let complete = counts[SCFrameStatus.complete.rawValue] ?? 0
            let idle = counts[SCFrameStatus.idle.rawValue] ?? 0
            let other = counts.filter { $0.key != SCFrameStatus.complete.rawValue && $0.key != SCFrameStatus.idle.rawValue }
            let latency = firstCompleteMs.map { String(format: "%.1f ms", $0) } ?? "none"
            log("SUMMARY run \(run): complete=\(complete) idle=\(idle) other=\(other) "
                + "startLatency=\(latency) saved=\(saved) PNGs in \(framesDir.path)")
        }
        running = false
    }

    private func postNotification() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"spike\" with title \"Flipbook\""]
        do { try p.run(); log("notification posted (t≈3 s)") } catch { log("osascript failed: \(error)") }
    }

    // MARK: SCStreamOutput / SCStreamDelegate (on `queue`)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let info = array.first,
              let raw = info[.status] as? Int else { return }
        counts[raw, default: 0] += 1
        frameIndex += 1
        var line = "frame \(frameIndex) t=\(since(startCall)) ms status=\(raw)"

        if raw == SCFrameStatus.complete.rawValue {
            if firstCompleteMs == nil {
                firstCompleteMs = Double(DispatchTime.now().uptimeNanoseconds - startCall.uptimeNanoseconds) / 1e6
                log("FIRST COMPLETE FRAME after \(String(format: "%.1f", firstCompleteMs!)) ms")
            }
            if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                latest = pb
                if frameIndex <= 3 {
                    line += " buffer=\(CVPixelBufferGetWidth(pb))×\(CVPixelBufferGetHeight(pb))"
                }
            }
            let rects = (info[.dirtyRects] as? [Any] ?? []).compactMap { CGRect(dictionaryRepresentation: $0 as! CFDictionary) }
            let area = rects.reduce(0) { $0 + $1.width * $1.height }
            line += " dirty=\(rects.count) area=\(Int(area))"
            if !rects.isEmpty {
                let xs = rects.map(\.minX), ys = rects.map(\.minY), ws = rects.map(\.width), hs = rects.map(\.height)
                line += " x[\(r(xs.min()!))…\(r(xs.max()!))] y[\(r(ys.min()!))…\(r(ys.max()!))]"
                    + " w[\(r(ws.min()!))…\(r(ws.max()!))] h[\(r(hs.min()!))…\(r(hs.max()!))]"
            }
            if rects.count <= 4 {
                line += " rects=" + rects.map { "(\(r($0.minX)),\(r($0.minY)) \(r($0.width))×\(r($0.height)))" }.joined(separator: " ")
            }
            if let cr = info[.contentRect], let rect = CGRect(dictionaryRepresentation: cr as! CFDictionary) {
                line += " contentRect=(\(r(rect.minX)),\(r(rect.minY)) \(r(rect.width))×\(r(rect.height)))"
            }
            line += " contentScale=\(info[.contentScale] ?? "nil") scaleFactor=\(info[.scaleFactor] ?? "nil")"
        }
        log(line)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log("stream stopped with error: \(error)")
    }

    private func saveLatest() {
        guard let pb = latest else { log("save tick: no complete frame yet"); return }
        let image = CIImage(cvPixelBuffer: pb)
        guard let cg = ci.createCGImage(image, from: image.extent) else { return }
        saved += 1
        let url = framesDir.appendingPathComponent(String(format: "run%d-%02d.png", run, saved))
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }

    // MARK: helpers

    private func since(_ t: DispatchTime) -> String {
        String(format: "%.1f", Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e6)
    }

    private func r(_ v: CGFloat) -> String { String(Int(v.rounded())) }
}
