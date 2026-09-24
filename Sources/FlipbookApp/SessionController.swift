import AppKit
import FlipbookCapture
import FlipbookCore
import FlipbookExport
import FlipbookInput
@preconcurrency import ScreenCaptureKit

/// Runs SessionMachine's effects (design §7): starts and stops the recording engine, shows the pill,
/// plays the sounds, and hands finished captures to the cards. Main thread; InputMonitor's `recorded`
/// is the one entry point that runs on the input thread.
@MainActor
final class SessionController: InputMonitorDelegate {
    static let bundleID = "com.fayzanmalik.flipbook"
    static let elapsedInterval: TimeInterval = 1
    /// A target fallback note replaces the recording text for this long.
    static let noteDuration: TimeInterval = 3
    /// The Accessibility "Pointer size" setting, which scales the cursor box.
    static let cursorSizeDomain = "com.apple.universalaccess"
    static let cursorSizeKey = "mouseDriverCursorSize"

    /// One recording, from its start to its finished capture.
    final class Recording {
        let mode: RecordingMode
        let startedAt: TimeInterval
        var captureID: Int?
        var pipeline: RecordingPipeline?
        var screen: NSScreen?
        var candidates = 0
        /// Stopped or discarded.
        var ended = false
        var discarded = false

        init(mode: RecordingMode, startedAt: TimeInterval) {
            self.mode = mode
            self.startedAt = startedAt
        }
    }

    let settingsStore: SettingsStore
    private let contentCache: ShareableContentCache
    private let pill: PillPanel
    private let ax = AXClient()
    private let flags: WebAccessibilityFlagSetter
    private let context: ContextTracker
    private var machine: SessionMachine
    var inputMonitor: InputMonitor?
    var statusMenu: StatusMenu?
    var cards: CardController?

    private var current: Recording?
    /// Between stopEngine and showCard, which names its capture.
    private var stopped: Recording?
    private var captures: [Int: Recording] = [:]
    private var finishedCaptures: [Int: FinishedCapture] = [:]
    private var elapsedTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var noteUntil: TimeInterval = 0
    /// The current recording's input sink, read on the input thread.
    nonisolated let bridge = Locked<InputBridge?>(nil)

    init(settingsStore: SettingsStore, contentCache: ShareableContentCache, pill: PillPanel) {
        self.settingsStore = settingsStore
        self.contentCache = contentCache
        self.pill = pill
        flags = WebAccessibilityFlagSetter(ax: ax)
        context = ContextTracker(ax: ax, ownBundleID: Self.bundleID)
        machine = SessionMachine(sounds: settingsStore.settings.sounds)
    }

    var isRecording: Bool { machine.state != .idle }

    // MARK: - InputMonitorDelegate

    nonisolated func gesture(_ event: GestureEvent, at time: TimeInterval) {
        MainActor.assumeIsolated {
            handle(.gesture(event), at: time)
        }
    }

    nonisolated func recorded(_ input: RecordedInput, at time: TimeInterval) {
        bridge.value?.recorded(input, at: time)
    }

    // MARK: - Inputs

    /// The menu's Start/Stop Recording: a hands-free recording.
    func toggleFromMenu() {
        if machine.state == .idle {
            handle(.menuStart)
            if machine.state != .idle { inputMonitor?.handsFreeStartedElsewhere() }
        } else {
            handle(.menuStop)
        }
    }

    func handle(_ input: SessionMachine.Input, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if case .idle = machine.state { machine.sounds = settingsStore.settings.sounds }
        for effect in machine.handle(input, at: time) {
            run(effect, at: time)
        }
        statusMenu?.setRecording(isVisiblyRecording)
    }

    /// A hold is silent until its reveal, so a Right ⌘ shortcut never flashes the icon.
    private var isVisiblyRecording: Bool {
        if case .recording(_, revealed: true, _) = machine.state { return true }
        return false
    }

    private func run(_ effect: SessionMachine.Effect, at time: TimeInterval) {
        switch effect {
        case .startEngine(let mode):
            startEngine(mode, at: time)
        case .stopEngine:
            stopEngine()
        case .discardEngine:
            discardEngine()
        case .showPill:
            noteUntil = 0
            pill.place(on: current?.screen)
            pill.showRecording(pillText(at: time))
        case .hidePill:
            pill.hide()
        case .showMessage(let message):
            showMessage(message, at: time)
        case .playStart:
            Sounds.playStart()
        case .playStop:
            Sounds.playStop()
        case .showCard(let id):
            guard let recording = stopped else { return }
            stopped = nil
            recording.captureID = id
            captures[id] = recording
            log("capture \(id) saving")
            // The card appears at once, on the screen the cursor is on.
            cards?.showSaving(id: id, duration: time - recording.startedAt,
                              on: Self.screen(containing: Self.cursorLocation()))
        case .completeCard(let id):
            log("capture \(id) ready")
            if let capture = finishedCaptures.removeValue(forKey: id) {
                cards?.show(capture, id: id)
            }
            captures[id] = nil
        case .failCard(let id):
            log("capture \(id) failed")
            cards?.fail(id: id, folder: settingsStore.settings.saveLocation)
            captures[id] = nil
        case .resetGestures:
            inputMonitor?.recordingEnded()
        }
    }

    // MARK: - The engine

    private func startEngine(_ mode: RecordingMode, at time: TimeInterval) {
        let recording = Recording(mode: mode, startedAt: time)
        recording.screen = Self.screen(containing: Self.cursorLocation())
        current = recording
        pill.place(on: recording.screen)
        startElapsedTimer()
        log("recording starting (\(mode == .hold ? "hold" : "hands-free"))")
        Task { await startCapture(recording) }
    }

    private func startCapture(_ recording: Recording) async {
        let settings = settingsStore.settings
        do {
            let (snapshot, content) = try await contentCache.current()
            guard !recording.discarded else { return }
            guard let resolved = TargetResolver.resolve(Self.setting(settings.recordTarget),
                                                        cursor: Self.cursorLocation(), in: snapshot) else {
                throw CaptureError.contentUnavailable
            }
            let plan = FilterPlan.make(ownBundleID: Self.bundleID, snapshot: snapshot,
                                       statusItemWindowNumber: statusMenu?.windowNumber,
                                       statusItemFrame: statusMenu?.globalFrame)
            log("status item in frames: \(plan.statusItem); excluding \(plan.excludedBundleIDs.count) app(s), "
                + "\(plan.exceptingWindowIDs.count) window exception(s)")
            let target = try Self.engineTarget(resolved.target, plan: plan, content: content)
            let output = RecordingPipeline.outputSize(sourcePixels: target.sourcePixels, settings: settings)
            let mapping = TargetMapping(screenRect: target.screenRect, output: output)
            let cursorScale = max(1, UserDefaults(suiteName: Self.cursorSizeDomain)?.double(forKey: Self.cursorSizeKey) ?? 1)
            let pipeline = RecordingPipeline(
                configuration: .init(
                    settings: settings, mapping: mapping,
                    geometry: CaptureGeometry(outputWidth: output.width, outputHeight: output.height,
                                              pixelsPerPoint: mapping.pixelsPerPoint),
                    store: CaptureStore(root: settings.saveLocation), initialContext: context.initialContext(),
                    targetDescription: target.description, showsCursor: true,
                    cursorHotspot: { CGEvent(source: nil)?.location }, cursorScale: cursorScale),
                filter: target.filter)
            pipeline.onCandidateCount = { [weak self] count in self?.candidatesChanged(count, for: recording) }
            pipeline.onFinished = { [weak self] result in self?.finished(recording, result) }
            pipeline.onStreamEnded = { [weak self] _ in self?.streamEnded(recording) }
            recording.pipeline = pipeline
            recording.screen = Self.screen(containing: CGPoint(x: target.screenRect.midX, y: target.screenRect.midY))
                ?? recording.screen
            if !recording.ended {
                pill.place(on: recording.screen)
                connectInputs(to: pipeline)
            }
            try await pipeline.start()
            log("recording started: \(output.width)×\(output.height), \(target.kind)")
            if recording.discarded {
                pipeline.discard()
            } else if recording.ended {
                pipeline.stop()
            } else if recording === current {
                handle(.engineStarted(note: resolved.note))
            }
        } catch {
            log("recording couldn't start: \(error)")
            if recording === current { disconnectInputs() }
            if let id = recording.captureID {
                handle(.exported(captureID: id, success: false))
            } else if recording === current {
                handle(.engineFailed(Self.failure(error)))
                current = nil
                stopElapsedTimer()
            }
        }
    }

    private func stopEngine() {
        guard let recording = current else { return }
        current = nil
        stopped = recording
        recording.ended = true
        recording.pipeline?.stop()
        disconnectInputs()
        stopElapsedTimer()
    }

    private func discardEngine() {
        guard let recording = current else { return }
        current = nil
        recording.ended = true
        recording.discarded = true
        recording.pipeline?.discard()
        disconnectInputs()
        stopElapsedTimer()
        log("recording discarded")
    }

    /// Input, context and the Chrome/Electron flags follow the recording while it runs.
    private func connectInputs(to pipeline: RecordingPipeline) {
        bridge.value = InputBridge(mapping: { pipeline.mapping }, pipeline: pipeline, labels: ax)
        context.begin(ContextTracker.Hooks(
            reserve: { pipeline.reserve($0) },
            fill: { pipeline.fill($0, with: $1) },
            submit: { pipeline.submit($0) }))
        flags.enableForRunningApps()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.flags.enable(for: app) }
            })
        }
    }

    private func disconnectInputs() {
        guard bridge.value != nil || !workspaceObservers.isEmpty else { return }
        bridge.value = nil
        context.end()
        flags.clearAll()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers = []
    }

    private func finished(_ recording: Recording, _ result: Result<FinishedCapture, Error>) {
        guard let id = recording.captureID else { return }
        switch result {
        case .success(let capture):
            finishedCaptures[id] = capture
            handle(.exported(captureID: id, success: true))
        case .failure(let error):
            log("capture \(id) couldn't be saved: \(error)")
            handle(.exported(captureID: id, success: false))
        }
    }

    private func streamEnded(_ recording: Recording) {
        guard recording === current else { return }
        handle(.streamEnded)
    }

    private func candidatesChanged(_ count: Int, for recording: Recording) {
        recording.candidates = count
        guard recording === current else { return }
        refreshPill()
    }

    // MARK: - The pill

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.onMainRunLoop(interval: Self.elapsedInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handle(.elapsed)
                self?.refreshPill()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func pillText(at time: TimeInterval) -> String {
        guard let recording = current else { return "" }
        let settings = settingsStore.settings
        return PillText.recording(mode: recording.mode, elapsed: time - recording.startedAt,
                                  frames: recording.candidates, maxFrames: settings.maxFrames,
                                  trigger: settings.triggerKey)
    }

    private func refreshPill() {
        guard case .recording(_, revealed: true, _) = machine.state else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= noteUntil else { return }
        if noteUntil > 0 {
            noteUntil = 0
            pill.showRecording(pillText(at: now))
        } else {
            pill.update(pillText(at: now))
        }
    }

    private func showMessage(_ message: SessionMachine.PillMessage, at time: TimeInterval) {
        let text = PillText.message(message)
        if case .note = message, machine.state != .idle {
            noteUntil = time + Self.noteDuration
            pill.place(on: current?.screen)
            pill.showMessage(text, openSettings: false, hideAfter: nil)
        } else {
            pill.place(on: current?.screen ?? Self.screen(containing: Self.cursorLocation()))
            pill.showMessage(text, openSettings: message == .screenRecordingNeeded)
        }
    }

    // MARK: - Targets

    private struct EngineTarget {
        var filter: SCContentFilter
        var sourcePixels: CGSize
        var screenRect: CGRect
        var description: String
        var kind: String
    }

    private static func engineTarget(_ target: ResolvedTarget, plan: FilterPlan,
                                     content: SCShareableContent) throws -> EngineTarget {
        switch target {
        case .display(let display):
            guard let scDisplay = content.displays.first(where: { $0.displayID == display.id }) else {
                throw CaptureError.targetGone
            }
            let excluded = content.applications.filter { plan.excludedBundleIDs.contains($0.bundleIdentifier) }
            let excepting = content.windows.filter { plan.exceptingWindowIDs.contains($0.windowID) }
            return EngineTarget(
                filter: SCContentFilter(display: scDisplay, excludingApplications: excluded, exceptingWindows: excepting),
                sourcePixels: display.pixelSize, screenRect: display.frame,
                description: "Screen: \(display.name)", kind: "screen")
        case .window(let window):
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else {
                throw CaptureError.targetGone
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let scale = CGFloat(filter.pointPixelScale)
            let title = LabelResolver.normalize(window.title ?? "")
            return EngineTarget(
                filter: filter,
                sourcePixels: CGSize(width: filter.contentRect.width * scale, height: filter.contentRect.height * scale),
                screenRect: window.frame,
                description: title.isEmpty ? "Window: \(window.ownerName)" : "Window: \(window.ownerName) — \(title)",
                kind: "window")
        }
    }

    private static func setting(_ target: Settings.RecordTarget) -> TargetResolver.Setting {
        switch target {
        case .cursorScreen: .cursorScreen
        case .screen(let uuid): .screen(uuid: uuid)
        case .window(let id, _): .window(id: CGWindowID(id))
        }
    }

    private static func failure(_ error: Error) -> SessionMachine.StartFailure {
        switch error {
        case CaptureError.permissionDenied: .screenRecordingPermission
        case CaptureStoreError.saveLocationUnavailable: .saveLocationUnavailable
        default: .contentUnavailable
        }
    }

    /// The pointer in global points, top-left origin.
    static func cursorLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// The screen containing a global point (top-left origin).
    static func screen(containing point: CGPoint) -> NSScreen? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let cocoa = CGPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.first { NSMouseInRect(cocoa, $0.frame, false) } ?? NSScreen.main
    }
}
