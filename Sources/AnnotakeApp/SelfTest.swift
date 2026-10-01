import AppKit
import AnnotakeCapture
import AnnotakeCore
import AnnotakeExport
@preconcurrency import ScreenCaptureKit
import Synchronization

/// Where things are in the self-test window, in view points with a top-left origin.
enum SelfTestLayout {
    static let size = CGSize(width: 800, height: 500)
    static let title = "Annotake Self-Test"
    /// The window's title once the dialog has closed.
    static let savedTitle = "Annotake Self-Test — Saved"
    static let pointerStart = CGPoint(x: 400, y: 440)
    static let openButton = CGRect(x: 40, y: 40, width: 120, height: 36)
    static let dialog = CGRect(x: 180, y: 110, width: 340, height: 240)
    static let checkbox = CGRect(x: 210, y: 180, width: 20, height: 20)
    static let emailField = CGRect(x: 210, y: 240, width: 280, height: 32)
    static let banner = CGRect(x: 0, y: 0, width: 800, height: 36)
    static let list = CGRect(x: 560, y: 80, width: 220, height: 400)
    static let listRowHeight: CGFloat = 32
    /// How many rows the list moves when it scrolls.
    static let listShiftRows = 6

    /// Which screen the window goes on: the sharpest, and the first (the main one) on a tie. The script's picks
    /// hold on a Retina screen; on a 1× monitor the drawn pointer covers fewer tiles, and an extra frame is kept.
    static func preferredScreen(scales: [CGFloat]) -> Int? {
        guard let sharpest = scales.max() else { return nil }
        return scales.firstIndex(of: sharpest)
    }

    static var openCenter: CGPoint { CGPoint(x: openButton.midX, y: openButton.midY) }
    static var checkboxCenter: CGPoint { CGPoint(x: checkbox.midX, y: checkbox.midY) }
}

/// One timed step of the self-test's scene. Points in the input kinds are view points; `SelfTest.mapped`
/// turns them into output pixels for whichever screen the step is played on.
struct SelfTestStep: Sendable {
    enum Change: Sendable {
        case pointer(CGPoint)
        case showDialog
        case tickCheckbox
        case typeText(String)
        case closeDialogShowBanner
        case shiftList
        /// Renames the window; the recording follows its title for line 2.
        case retitle(String)
    }

    enum Input: Sendable {
        case reserveThenFill(InputEventKind, placeholder: InputEventKind, delay: TimeInterval)
        case submit(InputEventKind)
        case stop
    }

    var time: TimeInterval
    var change: Change?
    var input: Input?

    init(time: TimeInterval, change: Change? = nil, input: Input? = nil) {
        self.time = time
        self.change = change
        self.input = input
    }
}

/// `Annotake --selftest <dir>` (spec §8): records the app's own scripted window through the real
/// ScreenCaptureKit → picker → export path. Capturing its own window needs no permission.
enum SelfTest {
    static let initialContext = FrameContext(app: "Annotake", window: SelfTestLayout.title)
    static let targetDescription = "Window: Annotake — \(SelfTestLayout.title)"
    static let open = ElementLabel(role: "button", label: "Open")
    static let remember = ElementLabel(role: "checkbox", label: "Remember me")
    static let email = ElementLabel(role: "text field", label: "Email")

    // The checks.
    static let minimumFrames = 6
    static let firstFrameLimit: TimeInterval = 1
    static let signatureMillisecondsLimit = 8.0
    /// Under Rosetta (`make selftest-intel`) signature timings measure translation, not a Mac, so the limit
    /// is this many times looser there.
    static let translatedSignatureAllowance = 2.0
    static let stopToReadyMillisecondsLimit = 1500.0
    /// The window is shown, then left to settle before the recording starts.
    static let settleBeforeStart: TimeInterval = 0.6
    /// Gives up if the capture hasn't finished this long after the script's stop.
    static let finishTimeout: TimeInterval = 20

    /// Follows Core's `Scenes.clickFlow()` up to the typing, then adds a later Return, the dialog closing
    /// as the window is renamed, and one scroll. Both the live run and SelfTestExpectationTests read it.
    static let script: [SelfTestStep] = [
        SelfTestStep(time: 0.0, change: .pointer(SelfTestLayout.pointerStart)),
        SelfTestStep(time: 0.9, change: .pointer(SelfTestLayout.openCenter)),
        SelfTestStep(time: 1.0, input: .reserveThenFill(click(SelfTestLayout.openCenter, on: open),
                                                        placeholder: click(SelfTestLayout.openCenter, on: nil),
                                                        delay: 0.03)),
        SelfTestStep(time: 1.05, input: .submit(.mouseUp(point: point(SelfTestLayout.openCenter)))),
        SelfTestStep(time: 1.3, change: .showDialog),
        SelfTestStep(time: 2.3, change: .pointer(SelfTestLayout.checkboxCenter)),
        SelfTestStep(time: 2.5, input: .reserveThenFill(click(SelfTestLayout.checkboxCenter, on: remember),
                                                        placeholder: click(SelfTestLayout.checkboxCenter, on: nil),
                                                        delay: 0.06)),
        SelfTestStep(time: 2.55, input: .submit(.mouseUp(point: point(SelfTestLayout.checkboxCenter)))),
        SelfTestStep(time: 2.7, change: .tickCheckbox),
        SelfTestStep(time: 4.0, change: .typeText("me"),
                     input: .reserveThenFill(.keyTyped(field: email), placeholder: .keyTyped(field: nil), delay: 0.04)),
        SelfTestStep(time: 4.1, input: .submit(.keyTyped(field: email))),
        SelfTestStep(time: 4.2, change: .typeText("me@exa"), input: .submit(.keyTyped(field: email))),
        SelfTestStep(time: 4.3, input: .submit(.keyTyped(field: email))),
        SelfTestStep(time: 4.4, change: .typeText("me@example.com"), input: .submit(.keyTyped(field: email))),
        // After the typing pause has settled at about 6.0, so the two never race.
        SelfTestStep(time: 6.5, input: .submit(.keyReturn)),
        SelfTestStep(time: 6.7, change: .closeDialogShowBanner),
        SelfTestStep(time: 6.7, change: .retitle(SelfTestLayout.savedTitle)),
        SelfTestStep(time: 7.5, input: .submit(.scroll(fractionOfViewport: 0.9))),
        SelfTestStep(time: 7.55, change: .shiftList),
        SelfTestStep(time: 9.0, input: .stop),
    ]

    static let expectedCaptions = [
        #"Clicked button "Open""#,
        #"Clicked checkbox "Remember me""#,
        #"Typed in field "Email""#,
        "Pressed Return",
        "Scrolled",
        "End",
    ]

    /// Each frame's line 2: the recorded window, with the title it has at that step.
    static let expectedContexts = [
        "Annotake — Annotake Self-Test",
        "Annotake — Annotake Self-Test",
        "Annotake — Annotake Self-Test",
        "Annotake — Annotake Self-Test",
        "Annotake — Annotake Self-Test — Saved",
        "Annotake — Annotake Self-Test — Saved",
    ]

    static func signatureLimit(translated: Bool) -> Double {
        signatureMillisecondsLimit * (translated ? translatedSignatureAllowance : 1)
    }

    static func architectureName(arm64: Bool, translated: Bool) -> String {
        arm64 ? "arm64" : translated ? "x86_64 (Rosetta)" : "x86_64"
    }

    /// True when this process is an x86_64 binary running under Rosetta.
    static var isTranslated: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
    }

    static var architecture: String {
        #if arch(arm64)
        architectureName(arm64: true, translated: false)
        #else
        architectureName(arm64: false, translated: isTranslated)
        #endif
    }

    /// The kind with its points moved through `transform`.
    static func mapped(_ kind: InputEventKind, _ transform: (CGPoint) -> PixelPoint) -> InputEventKind {
        switch kind {
        case let .mouseDown(point, target, button, clickCount):
            .mouseDown(point: transform(CGPoint(x: point.x, y: point.y)), target: target, button: button,
                       clickCount: clickCount)
        case .mouseUp(let point):
            .mouseUp(point: transform(CGPoint(x: point.x, y: point.y)))
        default:
            kind
        }
    }

    private static func point(_ point: CGPoint) -> PixelPoint {
        PixelPoint(x: point.x, y: point.y)
    }

    private static func click(_ at: CGPoint, on target: ElementLabel?) -> InputEventKind {
        .mouseDown(point: point(at), target: target, button: .left, clickCount: 1)
    }

    // MARK: - The live run

    /// Plays the script in a window, records it, checks the result, and writes `selftest.json` and
    /// `selftest.txt` into the directory. Returns the process exit code.
    @MainActor
    static func run(outputDirectory: URL) async -> Int32 {
        var report = SelfTestReport()
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try await record(into: outputDirectory, report: &report)
        } catch {
            report.failures.append("error: \(error)")
        }
        report.passed = report.failures.isEmpty
        report.write(to: outputDirectory)
        log("self-test \(report.passed ? "passed" : "failed")")
        return report.passed ? 0 : 1
    }

    @MainActor
    private static func record(into directory: URL, report: inout SelfTestReport) async throws {
        let scene = SelfTestWindow()
        scene.show()
        try await Task.sleep(for: .seconds(settleBeforeStart))

        let content = try await ShareableContentCache.ownProcess().content
        guard let window = content.windows.first(where: { $0.windowID == CGWindowID(scene.windowNumber) }) else {
            report.failures.append("the self-test window isn't in this process's shareable content")
            return
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        var settings = Settings()
        settings.saveRawSessions = true
        let scale = CGFloat(filter.pointPixelScale)
        let output = RecordingPipeline.outputSize(
            sourcePixels: CGSize(width: filter.contentRect.width * scale, height: filter.contentRect.height * scale),
            settings: settings)
        let mapping = TargetMapping(screenRect: window.frame, output: output)
        report.outputSize = "\(output.width)×\(output.height)"
        let hotspot = scene.hotspot
        let pipeline = RecordingPipeline(
            configuration: .init(
                settings: settings, mapping: mapping,
                geometry: CaptureGeometry(outputWidth: output.width, outputHeight: output.height,
                                          pixelsPerPoint: mapping.pixelsPerPoint),
                store: CaptureStore(root: directory.appending(path: "captures")),
                initialContext: initialContext, recordedWindowID: window.windowID,
                targetDescription: targetDescription, showsCursor: false,
                cursorHotspot: { hotspot.value }, cursorScale: 1),
            filter: filter)
        let finish = FinishSignal()
        pipeline.onFinished = { finish.deliver($0) }

        try await pipeline.start()
        play(script, on: scene, into: pipeline, mapping: mapping)
        let stopTime = script.last { if case .stop? = $0.input { true } else { false } }?.time ?? 0
        let deadline = pipeline.startUptime + stopTime + finishTimeout
        let outcome = await finish.wait(until: deadline)
        scene.close()

        let stats = pipeline.stats
        report.stats = stats
        guard stats.completeFrames > 0 else {
            report.failures.insert("no frames — is the Mac asleep or locked?", at: 0)
            return
        }
        guard let outcome else {
            report.failures.append("the capture didn't finish within \(Int(finishTimeout)) s of stopping")
            return
        }
        check(try outcome.get(), stats: stats, report: &report)
    }

    /// Schedules each step's scene change and input at its time from the recording's start.
    @MainActor
    private static func play(_ script: [SelfTestStep], on scene: SelfTestWindow, into pipeline: RecordingPipeline,
                             mapping: TargetMapping) {
        func pixels(_ point: CGPoint) -> PixelPoint {
            mapping.outputPoint(scene.globalPoint(point)) ?? PixelPoint(x: 0, y: 0)
        }
        func at(_ time: TimeInterval, _ work: @escaping @MainActor @Sendable () -> Void) {
            let deadline = DispatchTime(uptimeNanoseconds: UInt64((pipeline.startUptime + time) * 1_000_000_000))
            DispatchQueue.main.asyncAfter(deadline: deadline) { MainActor.assumeIsolated { work() } }
        }
        for step in script {
            if let change = step.change {
                at(step.time) { scene.apply(change) }
            }
            switch step.input {
            case let .reserveThenFill(kind, placeholder, delay)?:
                let filled = mapped(kind, pixels), unlabeled = mapped(placeholder, pixels)
                let token = Locked<RecordingPipeline.SlotToken?>(nil)
                at(step.time) { token.value = pipeline.reserve(unlabeled) }
                at(step.time + delay) {
                    if let reserved = token.value { pipeline.fill(reserved, with: filled) }
                }
            case .submit(let kind)?:
                let event = mapped(kind, pixels)
                at(step.time) { pipeline.submit(event) }
            case .stop?:
                at(step.time) { pipeline.stop() }
            case nil:
                break
            }
        }
    }

    private static func check(_ finished: FinishedCapture, stats: PipelineStats, report: inout SelfTestReport) {
        let frames = finished.manifest.result.frames
        report.capture = finished.folder.path
        report.captions = frames.enumerated().map { Captions.summary(for: $1, number: $0 + 1, total: frames.count) }
        report.contexts = frames.map { Captions.line2(for: $0.context) }
        report.frameIndices = frames.map(\.frameIndex)

        if stats.completeFrames < minimumFrames {
            report.failures.append("only \(stats.completeFrames) complete frames, expected at least \(minimumFrames)")
        }
        if let latency = stats.firstFrameLatency, latency > firstFrameLimit {
            report.failures.append(String(format: "the first frame took %.2f s", latency))
        }
        if stats.signatureMillisecondsAverage >= signatureLimit(translated: isTranslated) {
            report.failures.append(String(format: "signatures took %.1f ms on average", stats.signatureMillisecondsAverage))
        }
        if report.captions != expectedCaptions {
            report.failures.append("picked captions \(report.captions), expected \(expectedCaptions)")
        }
        if report.contexts != expectedContexts {
            report.failures.append("line 2 reads \(report.contexts), expected \(expectedContexts)")
        }
        if let ready = stats.stopToReadyMilliseconds, ready > stopToReadyMillisecondsLimit {
            report.failures.append(String(format: "stop to a finished capture took %.0f ms", ready))
        }

        let folder = finished.folder
        let raw = folder.appending(path: CaptureStore.rawFolderName)
        let required = finished.frameURLs + [
            folder.appending(path: "steps.md"),
            folder.appending(path: CaptureStore.markerName),
            raw.appending(path: "capture.json"),
            raw.appending(path: RecordingPipeline.sessionFolderName).appending(path: "session.json"),
        ]
        for url in required where !FileManager.default.fileExists(atPath: url.path) {
            report.failures.append("missing \(url.path)")
        }
        report.files = ((try? FileManager.default.subpathsOfDirectory(atPath: folder.path)) ?? []).sorted()
        for url in finished.frameURLs {
            guard let size = pngSize(url) else { continue }
            report.frameSizes.append("\(url.lastPathComponent) \(size.width)×\(size.height)")
            if size.width > OutputSizing.maxSide || size.height > OutputSizing.maxSide {
                report.failures.append("\(url.lastPathComponent) is \(size.width)×\(size.height)")
            }
        }

        do {
            let session = try RawSessionIO.read(from: raw.appending(path: RecordingPipeline.sessionFolderName))
            let replayed = SessionReplayer.run(session).result.frames
            report.replayedFrameIndices = replayed.map(\.frameIndex)
            if report.replayedFrameIndices != report.frameIndices {
                report.failures.append("replaying the raw session picked \(report.replayedFrameIndices), "
                                       + "live picked \(report.frameIndices)")
            }
            if replayed.map(\.context) != frames.map(\.context) {
                report.failures.append("replaying the raw session gave line 2s "
                                       + "\(replayed.map { Captions.line2(for: $0.context) }), live \(report.contexts)")
            }
        } catch {
            report.failures.append("the raw session doesn't read back: \(error)")
        }
    }

    private static func pngSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}

/// Hands the pipeline's result to whoever waits for it, or nil once the deadline passes.
private final class FinishSignal: Sendable {
    private let state = Mutex<(result: Result<FinishedCapture, Error>?, waiter: CheckedContinuation<Result<FinishedCapture, Error>?, Never>?)>((nil, nil))

    func deliver(_ result: Result<FinishedCapture, Error>) {
        let waiter = state.withLock { state -> CheckedContinuation<Result<FinishedCapture, Error>?, Never>? in
            guard state.result == nil else { return nil }
            state.result = result
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(returning: result)
    }

    func wait(until deadline: TimeInterval) async -> Result<FinishedCapture, Error>? {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Result<FinishedCapture, Error>?? in
                if let result = state.result { return .some(result) }
                state.waiter = continuation
                return .none
            }
            if let ready {
                continuation.resume(returning: ready)
                return
            }
            let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
                let waiter = state.withLock { state -> CheckedContinuation<Result<FinishedCapture, Error>?, Never>? in
                    defer { state.waiter = nil }
                    return state.waiter
                }
                waiter?.resume(returning: nil)
            }
        }
    }
}

/// What the self-test found; `selftest.json` holds all of it, and `selftest.txt` starts with the verdict.
private struct SelfTestReport: Encodable {
    var passed = false
    var failures: [String] = []
    var architecture = SelfTest.architecture
    var stats = PipelineStats()
    var outputSize = ""
    var captions: [String] = []
    var expectedCaptions = SelfTest.expectedCaptions
    var contexts: [String] = []
    var expectedContexts = SelfTest.expectedContexts
    var frameIndices: [Int] = []
    var replayedFrameIndices: [Int] = []
    var capture: String?
    var files: [String] = []
    var frameSizes: [String] = []

    func write(to directory: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let json = try? encoder.encode(self) {
            try? json.write(to: directory.appending(path: "selftest.json"), options: .atomic)
        }
        var lines = [passed ? "PASSED" : "FAILED: " + (failures.first ?? "unknown")]
        lines += failures.dropFirst().map { "FAILED: " + $0 }
        lines.append("architecture: \(architecture)")
        lines.append("frames: \(stats.completeFrames) complete, \(stats.idleFrames) idle; output \(outputSize)")
        if let latency = stats.firstFrameLatency {
            lines.append(String(format: "first frame after %.0f ms", latency * 1000))
        }
        lines.append(String(format: "signatures: %.2f ms average, %.2f ms max",
                            stats.signatureMillisecondsAverage, stats.signatureMillisecondsMax))
        if let export = stats.exportMilliseconds, let ready = stats.stopToReadyMilliseconds {
            lines.append(String(format: "export %.0f ms; stop to a finished capture %.0f ms", export, ready))
        }
        lines.append("captions: " + captions.joined(separator: " | "))
        lines.append("line 2: " + contexts.joined(separator: " | "))
        lines.append("frame indices: \(frameIndices), replayed: \(replayedFrameIndices)")
        if let capture { lines.append("capture: \(capture)") }
        try? Data((lines.joined(separator: "\n") + "\n").utf8)
            .write(to: directory.appending(path: "selftest.txt"), options: .atomic)
    }
}

// MARK: - The scene

/// The window the self-test records: a normal window that draws the scene and its own pointer.
@MainActor
final class SelfTestWindow {
    /// The drawn pointer's hotspot in global points; read on the recording queue.
    let hotspot = Locked<CGPoint?>(nil)
    private let window: NSWindow
    private let view = SelfTestSceneView(frame: CGRect(origin: .zero, size: SelfTestLayout.size))

    init() {
        window = NSWindow(contentRect: CGRect(origin: .zero, size: SelfTestLayout.size), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.title = SelfTestLayout.title
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = view
    }

    var windowNumber: Int { window.windowNumber }

    func show() {
        let screens = NSScreen.screens
        if let index = SelfTestLayout.preferredScreen(scales: screens.map(\.backingScaleFactor)) {
            let visible = screens[index].visibleFrame
            window.setFrameOrigin(CGPoint(x: (visible.midX - window.frame.width / 2).rounded(),
                                          y: (visible.midY - window.frame.height / 2).rounded()))
        } else {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }

    /// A view point in global points, top-left origin (Quartz).
    func globalPoint(_ point: CGPoint) -> CGPoint {
        let onScreen = window.convertPoint(toScreen: view.convert(point, to: nil))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: onScreen.x, y: primaryHeight - onScreen.y)
    }

    func apply(_ change: SelfTestStep.Change) {
        switch change {
        case .pointer(let point):
            view.pointer = point
            hotspot.value = globalPoint(point)
        case .showDialog:
            view.dialogVisible = true
        case .tickCheckbox:
            view.checked = true
        case .typeText(let text):
            view.text = text
        case .closeDialogShowBanner:
            view.dialogVisible = false
            view.bannerVisible = true
        case .shiftList:
            view.listOffset += SelfTestLayout.listShiftRows
        case .retitle(let title):
            window.title = title
        }
        view.needsDisplay = true
    }
}

private final class SelfTestSceneView: NSView {
    var pointer = SelfTestLayout.pointerStart
    var dialogVisible = false
    var checked = false
    var text = ""
    var bannerVisible = false
    var listOffset = 0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.94, alpha: 1).setFill()
        bounds.fill()
        drawButton()
        drawList()
        if dialogVisible { drawDialog() }
        if bannerVisible { drawBanner() }
        drawPointer()
    }

    private func label(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .black, centered: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = centered ? .center : .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
        ]
        let height = (string as NSString).size(withAttributes: attributes).height
        (string as NSString).draw(in: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                                  withAttributes: attributes)
    }

    private func drawButton() {
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: SelfTestLayout.openButton, xRadius: 8, yRadius: 8).fill()
        label("Open", in: SelfTestLayout.openButton, size: 16, weight: .semibold, color: .white, centered: true)
    }

    private func drawList() {
        let list = SelfTestLayout.list
        NSColor.white.setFill()
        list.fill()
        let rows = Int(list.height / SelfTestLayout.listRowHeight)
        for row in 0..<rows {
            let rect = CGRect(x: list.minX, y: list.minY + CGFloat(row) * SelfTestLayout.listRowHeight,
                              width: list.width, height: SelfTestLayout.listRowHeight)
            let item = row + listOffset
            (item % 2 == 0 ? NSColor(white: 0.97, alpha: 1) : NSColor(calibratedRed: 0.9, green: 0.94, blue: 1, alpha: 1)).setFill()
            rect.fill()
            label("Item \(item + 1)", in: rect.insetBy(dx: 12, dy: 0), size: 15)
        }
    }

    private func drawDialog() {
        let dialog = SelfTestLayout.dialog
        NSColor(white: 0, alpha: 0.25).setFill()
        NSBezierPath(roundedRect: dialog.offsetBy(dx: 0, dy: 4), xRadius: 12, yRadius: 12).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: dialog, xRadius: 12, yRadius: 12).fill()
        label("Sign in", in: CGRect(x: dialog.minX + 30, y: dialog.minY + 20, width: 200, height: 30), size: 20,
              weight: .bold)

        let box = SelfTestLayout.checkbox
        NSColor(white: 0.55, alpha: 1).setStroke()
        let square = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        square.lineWidth = 1.5
        if checked {
            NSColor.systemBlue.setFill()
            square.fill()
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: box.minX + 4, y: box.midY))
            tick.line(to: CGPoint(x: box.minX + 8.5, y: box.maxY - 5))
            tick.line(to: CGPoint(x: box.maxX - 4, y: box.minY + 5))
            tick.lineWidth = 2.5
            NSColor.white.setStroke()
            tick.stroke()
        } else {
            square.stroke()
        }
        label("Remember me", in: CGRect(x: box.maxX + 10, y: box.minY, width: 200, height: box.height), size: 15)

        let field = SelfTestLayout.emailField
        NSColor.white.setFill()
        field.fill()
        NSColor(white: 0.7, alpha: 1).setStroke()
        NSBezierPath(rect: field).stroke()
        label(text.isEmpty ? "Email" : text, in: field.insetBy(dx: 10, dy: 0), size: 15,
              color: text.isEmpty ? NSColor(white: 0.6, alpha: 1) : .black)
    }

    private func drawBanner() {
        NSColor.systemGreen.setFill()
        SelfTestLayout.banner.fill()
        label("Saved", in: SelfTestLayout.banner, size: 16, weight: .semibold, color: .white, centered: true)
    }

    /// A small arrow with its tip at the hotspot.
    private func drawPointer() {
        let tip = pointer
        let arrow = NSBezierPath()
        let outline: [CGPoint] = [(0, 0), (0, 16), (4, 12.5), (7, 18.5), (9.5, 17.5), (6.5, 11.5), (11.5, 11.5)]
            .map { CGPoint(x: tip.x + $0.0, y: tip.y + $0.1) }
        arrow.move(to: outline[0])
        outline.dropFirst().forEach(arrow.line(to:))
        arrow.close()
        NSColor.black.setFill()
        arrow.fill()
        NSColor.white.setStroke()
        arrow.lineWidth = 1
        arrow.stroke()
    }
}
