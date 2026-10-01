import CoreGraphics
import CoreVideo
import AnnotakeCapture
import AnnotakeCore
import AnnotakeExport
import AnnotakeInput
import Foundation
@preconcurrency import ScreenCaptureKit
import Synchronization

enum PipelineError: Error, Equatable {
    /// The stream never delivered a frame: the Mac was asleep or locked, or the recording stopped at once.
    case noFrames
}

/// Timings and counts for one recording, for the log and the self-test.
struct PipelineStats: Sendable, Equatable, Codable {
    var completeFrames = 0, idleFrames = 0
    /// start() → first complete frame.
    var firstFrameLatency: TimeInterval?
    var signatureMillisecondsAverage = 0.0, signatureMillisecondsMax = 0.0
    var exportMilliseconds: Double?, stopToReadyMilliseconds: Double?
}

/// One recording: capture → LiveSession → writer → export (spec §6.1).
///
/// All state lives on `queue`, a serial "recording" queue. ScreenCaptureKit delivers frames there, and
/// every other entry point hops to it, so frames and input are stamped in the order they reach it.
/// PNGs are encoded on `writer`; the export runs off both queues.
final class RecordingPipeline: @unchecked Sendable {
    typealias SlotToken = Int

    struct Configuration {
        var settings: Settings
        /// Updated from each frame's screenRect in window mode.
        var mapping: TargetMapping
        var geometry: CaptureGeometry
        var store: CaptureStore
        var initialContext: FrameContext
        /// Window recordings: the recorded window, which line 2 names whatever has focus (spec §4.2).
        /// Nil for screens.
        var recordedWindowID: CGWindowID?
        /// For steps.md: "Screen: <name>" / "Window: <app> — <title>".
        var targetDescription: String
        var showsCursor: Bool
        /// Global points; nil when unknown.
        var cursorHotspot: @Sendable () -> CGPoint?
        var cursorScale: Double
    }

    static let sessionFolderName = "session"
    static let logInterval: TimeInterval = 1
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Time zero for every stamp, in `ProcessInfo.systemUptime` seconds.
    let startUptime: TimeInterval
    private let configuration: Configuration
    private let contextSource: ContextSource
    private let filter: SCContentFilter
    private let followsWindow: Bool
    private let queue = DispatchQueue(label: "com.fayzanmalik.annotake.recording", qos: .userInteractive)
    private let writer = DispatchQueue(label: "com.fayzanmalik.annotake.writer", qos: .userInitiated)
    private let stream = CaptureStream()
    private let tokens = Mutex(0)
    private let mappingNow: Mutex<TargetMapping>

    // Confined to `queue`.
    private var live: LiveSession
    private var pixels = PixelStore<CVPixelBuffer>()
    private var pending: PendingCapture?
    private var rawSession: RawSessionWriter?
    private var timer: DispatchSourceTimer?
    private var slots: [SlotToken: LiveSession.Slot] = [:]
    private var stopRequested = false
    private var finishing = false
    private var discarded = false
    private var stopUptime: TimeInterval?
    private let startDate = Date()
    private var currentStats = PipelineStats()
    private var signatureMillisecondsTotal = 0.0
    private var reportedCandidates = 0
    private var logWindow = LogWindow()
    private var windowTitle: RecordedWindowTitle

    var onCandidateCount: (@MainActor @Sendable (Int) -> Void)?
    var onFinished: (@MainActor @Sendable (Result<FinishedCapture, Error>) -> Void)?
    /// The stream stopped by itself before `stop()`: the window closed, the display went away or slept.
    var onStreamEnded: (@MainActor @Sendable (CaptureError?) -> Void)?

    init(configuration: Configuration, filter: SCContentFilter) {
        self.configuration = configuration
        self.filter = filter
        followsWindow = filter.style == .window
        mappingNow = Mutex(configuration.mapping)
        var config = PickerConfig()
        config.maxFrames = configuration.settings.maxFrames
        contextSource = configuration.recordedWindowID == nil ? .focus : .recordedWindow
        live = LiveSession(geometry: configuration.geometry, config: config, initialContext: configuration.initialContext,
                           contextSource: contextSource)
        windowTitle = RecordedWindowTitle(configuration.initialContext.window)
        startUptime = ProcessInfo.processInfo.systemUptime
    }

    /// The output size for a source, following the frame-size and caption-strip settings (spec §4.2).
    static func outputSize(sourcePixels: CGSize, settings: Settings) -> OutputSize {
        OutputSizing.fit(sourcePixels: sourcePixels, longEdge: settings.longEdge,
                         stripRatio: settings.captionStrip ? CaptionLayout.maxHeightRatio : 0)
    }

    /// The current mapping from global points to output pixels. Safe from any thread.
    var mapping: TargetMapping { mappingNow.withLock { $0 } }

    var stats: PipelineStats { queue.sync { currentStats } }

    /// Creates the temp capture folder, starts the stream, and starts the 50 ms timer.
    /// Throws CaptureStoreError.saveLocationUnavailable or a CaptureError.
    func start() async throws {
        let pending = try configuration.store.begin()
        var rawSession: RawSessionWriter?
        if configuration.settings.saveRawSessions {
            do {
                rawSession = try RawSessionWriter(
                    directory: pending.rawDirectory.appending(path: Self.sessionFolderName),
                    geometry: configuration.geometry, initialContext: configuration.initialContext,
                    contextSource: contextSource)
            } catch {
                log("raw session unavailable: \(error)")
            }
        }
        let discardedAlready = queue.sync { () -> Bool in
            self.pending = pending
            self.rawSession = rawSession
            return discarded
        }
        if discardedAlready {
            pending.discard()
            return
        }
        do {
            try await stream.start(
                filter: filter, output: configuration.mapping.output, showsCursor: configuration.showsCursor,
                queue: queue,
                onFrame: { [weak self] frame in self?.received(frame) },
                onEnd: { [weak self] error in
                    guard let self else { return }
                    queue.async { self.streamEnded(error) }
                })
        } catch {
            queue.sync { discarded = true }
            pending.discard()
            throw error
        }
        let stopNow = queue.sync { () -> Bool in
            if !discarded { startTimer() }
            return discarded
        }
        if stopNow {
            await stream.stop()
            writer.async { pending.discard() }
        }
    }

    func submit(_ kind: InputEventKind) {
        queue.async { [self] in
            guard !stopRequested, !finishing, !discarded else { return }
            handle(live.receive(InputEvent(time: elapsed(), kind: kind)))
            finishIfDone()
        }
    }

    func reserve(_ placeholder: InputEventKind) -> SlotToken {
        let token = tokens.withLock { next in
            next += 1
            return next
        }
        queue.async { [self] in
            guard !stopRequested, !finishing, !discarded else { return }
            let (slot, outputs) = live.reserve(InputEvent(time: elapsed(), kind: placeholder))
            slots[token] = slot
            handle(outputs)
        }
        return token
    }

    func fill(_ token: SlotToken, with kind: InputEventKind) {
        queue.async { [self] in
            guard !finishing, !discarded, let slot = slots.removeValue(forKey: token) else { return }
            handle(live.fill(slot, with: kind, now: elapsed()))
            finishIfDone()
        }
    }

    /// Stops the recording at this moment. The stream keeps running until the picker settles.
    func stop() {
        queue.async { [self] in
            guard !stopRequested, !finishing, !discarded else { return }
            stopRequested = true
            stopUptime = ProcessInfo.processInfo.systemUptime
            handle(live.stop(at: elapsed()))
            finishIfDone()
        }
    }

    /// Stops the stream and deletes the pending capture.
    func discard() {
        queue.async { [self] in
            guard !discarded, !finishing else { return }
            discarded = true
            timer?.cancel()
            timer = nil
            pixels = PixelStore()
            rawSession = nil
            let pending = self.pending
            let writer = self.writer
            Task.detached { [stream] in
                await stream.stop()
                writer.async { pending?.discard() }
            }
        }
    }

    // MARK: - On `queue`

    private func elapsed() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime - startUptime
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: LiveSession.tickInterval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard !finishing, !discarded else { return }
        let now = elapsed()
        handle(live.advance(to: now))
        if now - logWindow.start >= Self.logInterval {
            log(logWindow.flush(at: now, idleFrames: stream.idleFrames))
        }
        finishIfDone()
    }

    private func received(_ captured: CapturedFrame) {
        guard !finishing, !discarded else { return }
        let now = elapsed()
        currentStats.completeFrames += 1
        if currentStats.firstFrameLatency == nil { currentStats.firstFrameLatency = now }
        var mapping = configuration.mapping
        if followsWindow, let screenRect = captured.screenRect, screenRect.width > 0, screenRect.height > 0 {
            mapping = mappingNow.withLock { current in
                current.screenRect = screenRect
                return current
            }
        }
        let cursor = configuration.cursorHotspot().flatMap {
            mapping.cursorRect(hotspot: $0, cursorScale: configuration.cursorScale)
        }

        let began = ProcessInfo.processInfo.systemUptime
        let signature = SignatureExtractor.signature(of: captured.pixelBuffer, geometry: configuration.geometry)
        let milliseconds = (ProcessInfo.processInfo.systemUptime - began) * 1000
        signatureMillisecondsTotal += milliseconds
        currentStats.signatureMillisecondsAverage = signatureMillisecondsTotal / Double(currentStats.completeFrames)
        currentStats.signatureMillisecondsMax = max(currentStats.signatureMillisecondsMax, milliseconds)
        logWindow.note(signature, dirtyRects: captured.dirtyRects)

        pixels.put(captured.pixelBuffer, frameIndex: captured.index)
        // Read as the frame arrives, so the frame's line 2 has the title it shows.
        if let id = configuration.recordedWindowID,
           let change = windowTitle.change(read: WindowTitle.read(windowID: id)) {
            handle(live.receive(InputEvent(time: now, kind: change)))
        }
        handle(live.receive(FrameSample(index: captured.index, time: now, signature: signature,
                                        dirtyRects: captured.dirtyRects, cursor: cursor)))
        finishIfDone()
    }

    private func streamEnded(_ error: CaptureError?) {
        guard !finishing, !discarded, !stopRequested else { return }
        log("capture stream ended: \(error.map { "\($0)" } ?? "no error")")
        guard let callback = onStreamEnded else { return }
        DispatchQueue.main.async { callback(error) }
    }

    private func handle(_ outputs: [LiveSession.Output]) {
        for output in outputs {
            switch output {
            case .tookFrame(let frame):
                pixels.evict(below: frame.index)
                do {
                    try rawSession?.append(frame)
                } catch {
                    log("raw session write failed; no longer saving it: \(error)")
                    rawSession = nil
                }
            case .tookEvent(let event):
                rawSession?.append(event)
            case .persist(let frameIndex, _, _):
                persist(frameIndex)
            case .discard(let frameIndices, _):
                guard let pending else { continue }
                let urls = frameIndices.map(pending.rawFrameURL(frameIndex:))
                writer.async {
                    for url in urls { try? FileManager.default.removeItem(at: url) }
                }
            }
        }
        let count = live.candidateCount
        if count != reportedCandidates {
            reportedCandidates = count
            if let callback = onCandidateCount {
                DispatchQueue.main.async { callback(count) }
            }
        }
    }

    /// Copies the frame's pixels now, before the stream reuses the buffer, and writes them on `writer`.
    private func persist(_ frameIndex: Int) {
        guard let pending, let buffer = pixels.buffer(frameIndex: frameIndex), let image = Self.image(copying: buffer) else {
            log("frame \(frameIndex) was kept, but its pixels are gone")
            return
        }
        let url = pending.rawFrameURL(frameIndex: frameIndex)
        writer.async {
            do {
                try PNGFile.write(image, to: url)
            } catch {
                log("writing a kept frame failed: \(error)")
            }
        }
    }

    private func finishIfDone() {
        guard live.isFinished, !finishing, !discarded else { return }
        finishing = true
        timer?.cancel()
        timer = nil
        let result = live.result()
        if let rawSession {
            do {
                try rawSession.finish(stopTime: live.stopTime ?? result.duration)
            } catch {
                log("finishing the raw session failed: \(error)")
            }
            self.rawSession = nil
        }
        pixels = PixelStore()
        currentStats.idleFrames = stream.idleFrames
        log(logWindow.flush(at: elapsed(), idleFrames: stream.idleFrames))
        log("picker finished: \(result.frames.count) frames from \(result.candidateCount) candidates, "
            + "\(currentStats.completeFrames) complete and \(currentStats.idleFrames) idle stream frames")
        guard let pending else { return }
        if result.frames.isEmpty {
            let writer = self.writer
            let callback = onFinished
            Task.detached { [stream] in
                await stream.stop()
                writer.async { pending.discard() }
                DispatchQueue.main.async { callback?(.failure(PipelineError.noFrames)) }
            }
            return
        }

        let stopUptime = self.stopUptime ?? ProcessInfo.processInfo.systemUptime
        let settings = configuration.settings
        let store = configuration.store
        let target = configuration.targetDescription
        let created = startDate
        let name = CaptureStore.folderName(for: created)
        let options = RenderOptions(captionStrip: settings.captionStrip, clickMarkers: settings.clickMarkers)
        let writer = self.writer
        let queue = self.queue
        let callback = onFinished
        Task.detached { [self, stream] in
            await stream.stop()
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                writer.async { done.resume() }
            }
            let exportBegan = ProcessInfo.processInfo.systemUptime
            let outcome = Result {
                try CaptureExporter.finish(pending, in: store, result: result, name: name, target: target,
                                           created: created, options: options)
            }
            let exportEnded = ProcessInfo.processInfo.systemUptime
            log("export \(outcome.isSuccess ? "finished" : "failed") in \(Int((exportEnded - exportBegan) * 1000)) ms, "
                + "\(Int((exportEnded - stopUptime) * 1000)) ms after stop")
            if case .failure(let error) = outcome { log("export error: \(error)") }
            queue.async {
                self.currentStats.exportMilliseconds = (exportEnded - exportBegan) * 1000
                self.currentStats.stopToReadyMilliseconds = (exportEnded - stopUptime) * 1000
                DispatchQueue.main.async { callback?(outcome) }
            }
        }
    }

    /// A BGRA sRGB copy of the buffer's pixels.
    private static func image(copying buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let provider = CGDataProvider(data: Data(bytes: base, count: bytesPerRow * height) as CFData) else {
            return nil
        }
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
        return CGImage(width: CVPixelBufferGetWidth(buffer), height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: sRGB, bitmapInfo: info, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// The recorded window's title in a window recording, whose line 2 names that window whatever has focus
/// (spec §4.2). The pipeline reads it by window ID as each frame arrives; a new title reaches the picker
/// as a `titleChanged` just before that frame. Titles never go in the log.
struct RecordedWindowTitle {
    private var current: String?

    /// `initial`: the normalized title the recording starts with.
    init(_ initial: String?) {
        current = initial
    }

    /// A `titleChanged` for a title just read, or nil when it's the same. A nil read means the window is
    /// gone, which keeps the last title.
    mutating func change(read: String?) -> InputEventKind? {
        guard let read else { return nil }
        let normalized = LabelResolver.normalize(read)
        let title = normalized.isEmpty ? nil : normalized
        guard title != current else { return nil }
        current = title
        return .titleChanged(window: title)
    }
}

/// Once a second while recording, the log gets one line of stream activity: complete and idle frames,
/// dirty area and the box around it, and how many frames really changed. Dirty area with no changed
/// frames shows regions that are reported dirty but look the same, like M0's bottom-center region on
/// macOS 26, and the box says where they are (Checkpoint 2). Boxes are in capture pixels, top-left origin.
struct LogWindow {
    private(set) var start: TimeInterval = 0
    private var complete = 0
    private var dirtyArea = 0
    private var dirtyBox: PixelRect?
    private var changed = 0
    private var idleAtStart = 0
    private var previous: FrameSignature?

    mutating func note(_ signature: FrameSignature, dirtyRects: [PixelRect]) {
        complete += 1
        for rect in dirtyRects where !rect.isEmpty {
            dirtyArea += rect.width * rect.height
            dirtyBox = dirtyBox.map { Self.union($0, rect) } ?? rect
        }
        if let previous, previous.tileCount == signature.tileCount,
           (0..<signature.tileCount).contains(where: {
               signature.differs(from: previous, tile: $0, threshold: PickerConfig().tileChangeThreshold)
           }) {
            changed += 1
        }
        previous = signature
    }

    /// The line for the window so far; the next window starts at `now`.
    mutating func flush(at now: TimeInterval, idleFrames: Int) -> String {
        var line = String(format: "stream %.0f–%.0f s: %d complete, %d idle, dirty %d px",
                          start, now, complete, idleFrames - idleAtStart, dirtyArea)
        if let box = dirtyBox {
            line += " in \(box.width)×\(box.height) at (\(box.x), \(box.y))"
        }
        line += ", \(changed) changed"
        start = now
        complete = 0
        dirtyArea = 0
        dirtyBox = nil
        changed = 0
        idleAtStart = idleFrames
        return line
    }

    private static func union(_ a: PixelRect, _ b: PixelRect) -> PixelRect {
        let minX = min(a.x, b.x), minY = min(a.y, b.y)
        return PixelRect(x: minX, y: minY, width: max(a.x + a.width, b.x + b.width) - minX,
                         height: max(a.y + a.height, b.y + b.height) - minY)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
