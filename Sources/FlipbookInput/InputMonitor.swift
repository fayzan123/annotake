import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import FlipbookCore
import Foundation
import Synchronization

public protocol InputMonitorDelegate: AnyObject, Sendable {
    /// Delivered on the main thread.
    func gesture(_ event: GestureEvent, at time: TimeInterval)
    /// On the input thread, only while recording. Must return fast: a slow tap callback gets disabled.
    func recorded(_ input: RecordedInput, at time: TimeInterval)
}

/// Where the Input module's log lines go; the app points it at its log file. Never given keys,
/// labels or titles.
public enum InputLog {
    private static let handler = Locked<(@Sendable (String) -> Void)?>(nil)

    public static func setHandler(_ write: @escaping @Sendable (String) -> Void) {
        handler.value = write
    }

    static func write(_ line: String) {
        handler.value?(line)
    }
}

/// A value shared between threads, guarded by a lock.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    var value: Value {
        get { mutex.withLock { $0 } }
        set { mutex.withLock { $0 = newValue } }
    }
}

/// The trigger key, gestures and recorded input (design §5). Both event taps and the gesture recognizer
/// live on a dedicated input thread with its own run loop: the tap callbacks only classify and hand
/// off, because macOS disables a slow tap, and a busy main thread would delay every click on the Mac.
/// All state is confined to that thread.
public final class InputMonitor: @unchecked Sendable {
    static let trustWatchdogInterval: TimeInterval = 2
    static let listenEvents: [CGEventType] = [
        .flagsChanged, .keyDown, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp, .scrollWheel,
    ]
    static let activeEvents: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel, .keyDown,
    ]
    /// Which flag each modifier key sets, to tell a modifier going down from one coming up.
    static let modifierFlags: [Int64: CGEventFlags] = [
        Int64(kVK_Command): .maskCommand, Int64(kVK_RightCommand): .maskCommand,
        Int64(kVK_Shift): .maskShift, Int64(kVK_RightShift): .maskShift,
        Int64(kVK_Option): .maskAlternate, Int64(kVK_RightOption): .maskAlternate,
        Int64(kVK_Control): .maskControl, Int64(kVK_RightControl): .maskControl,
        Int64(kVK_CapsLock): .maskAlphaShift, Int64(kVK_Function): .maskSecondaryFn,
    ]

    private let layout: KeyboardLayout
    private weak var delegate: InputMonitorDelegate?
    /// CGPreflightListenEventAccess() at start: without Input Monitoring, the tap is created but no
    /// events arrive (M0).
    public private(set) var isListening = false

    // Confined to the input thread.
    private var trigger: TriggerKey
    private var gestures: GestureConfig
    private var recognizer: GestureRecognizer
    private var pendingConfiguration: (trigger: TriggerKey, gestures: GestureConfig)?
    private var triggerDown = false
    private var lastRelease: TimeInterval?
    private var recording: RecordingMode?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var listenTap: CFMachPort?
    private var activeTap: CFMachPort?
    private var activeSource: CFRunLoopSource?
    private var tickTimer: CFRunLoopTimer?
    private var watchdog: CFRunLoopTimer?

    public init(trigger: TriggerKey, gestures: GestureConfig, layout: KeyboardLayout, delegate: InputMonitorDelegate) {
        self.trigger = trigger
        self.gestures = gestures
        self.layout = layout
        self.delegate = delegate
        recognizer = GestureRecognizer(config: gestures)
    }

    /// Starts the input thread and the listen tap.
    public func start() {
        guard thread == nil else { return }
        isListening = CGPreflightListenEventAccess()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            createListenTap()
            // Keeps the run loop alive even if the tap couldn't be created.
            let keepAlive = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
            CFRunLoopAddTimer(runLoop, keepAlive, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.fayzanmalik.flipbook.input"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        self.thread = thread
    }

    /// A new trigger key or gesture timings, applied once nothing is being recorded or held.
    public func reconfigure(trigger: TriggerKey, gestures: GestureConfig) {
        perform { [self] in
            pendingConfiguration = (trigger, gestures)
            applyPendingConfigurationIfIdle()
        }
    }

    /// A recording ended some other way (the menu, auto-stop, an error): resets the recognizer and
    /// removes the active tap.
    public func recordingEnded() {
        perform { [self] in
            recognizer.reset()
            recording = nil
            removeActiveTap()
            applyPendingConfigurationIfIdle()
        }
    }

    /// A hands-free recording started from the menu. Input is recorded as usual, and a double-tap or
    /// trigger + Esc ends it, as if it had started with a double-tap.
    public func handsFreeStartedElsewhere() {
        perform { [self] in
            guard recording == nil else { return }
            let now = ProcessInfo.processInfo.systemUptime
            var handsFree = GestureRecognizer(config: gestures)
            for input in [TriggerInput.triggerDown(at: now), .triggerUp(at: now), .triggerDown(at: now), .triggerUp(at: now)] {
                _ = handsFree.handle(input)
            }
            recognizer = handsFree
            beginRecording(.handsFree)
            updateTicking(now)
        }
    }

    // MARK: - On the input thread

    private func perform(_ work: @escaping @Sendable () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    private static func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(0) { $0 | (1 << CGEventMask($1.rawValue)) }
    }

    private func createListenTap() {
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: Self.mask(Self.listenEvents),
            callback: { _, type, event, context in
                Unmanaged<InputMonitor>.fromOpaque(context!).takeUnretainedValue().listen(type, event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        InputLog.write("listen tap created: \(tap != nil ? "yes" : "no"); Input Monitoring: \(isListening)")
        guard let tap, let runLoop else { return }
        CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        listenTap = tap
    }

    private func listen(_ type: CGEventType, _ event: CGEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let listenTap { CGEvent.tapEnable(tap: listenTap, enable: true) }
            InputLog.write("listen tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabled")
        case .flagsChanged:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == TriggerKeys.keycode(for: trigger) {
                let down = TriggerKeys.isDown(trigger, flags: event.flags)
                if down && !triggerDown {
                    triggerDown = true
                    feed(.triggerDown(at: now), at: now)
                } else if !down && triggerDown {
                    triggerDown = false
                    lastRelease = now
                    feed(.triggerUp(at: now), at: now)
                }
            } else if let flag = Self.modifierFlags[keycode], event.flags.contains(flag) {
                feed(.otherKeyDown(at: now, isEscape: false), at: now)
            }
        case .keyDown:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            feed(.otherKeyDown(at: now, isEscape: keycode == ActiveTapPolicy.escape), at: now)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if recording != nil, let kind = KeyClassifier.classify(keycode: UInt16(keycode), flags: event.flags,
                                                                   isRepeat: isRepeat, layout: layout) {
                delegate?.recorded(.key(kind, keycode: UInt16(keycode)), at: now)
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            feed(.mouseDown(at: now), at: now)
            if recording != nil, let button = PointerClassifier.button(for: type) {
                let clicks = Int(event.getIntegerValueField(.mouseEventClickState))
                delegate?.recorded(.mouseDown(globalPoint: event.location, button: button, clickCount: clicks), at: now)
            }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if recording != nil {
                delegate?.recorded(.mouseUp(globalPoint: event.location), at: now)
            }
        case .scrollWheel:
            if recording != nil {
                delegate?.recorded(.scroll(globalPoint: event.location,
                                           pointDeltaX: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                                           pointDeltaY: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)),
                                   at: now)
            }
        default:
            break
        }
        updateTicking(now)
    }

    private func active(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let activeTap { CGEvent.tapEnable(tap: activeTap, enable: true) }
            InputLog.write("active tap was disabled; re-enabled")
            return Unmanaged.passUnretained(event)
        }
        guard let mode = recording else { return Unmanaged.passUnretained(event) }
        let decision = ActiveTapPolicy.decide(type: type, keycode: event.getIntegerValueField(.keyboardEventKeycode),
                                              flags: event.flags, mode: mode, triggerDown: triggerDown, trigger: trigger)
        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .stripModifier(let flag):
            event.flags.remove(flag)
            return Unmanaged.passUnretained(event)
        case .consumeAsCancel:
            let now = ProcessInfo.processInfo.systemUptime
            feed(.otherKeyDown(at: now, isEscape: true), at: now)
            updateTicking(now)
            return nil
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        deliver(recognizer.tick(now: now), at: now)
        updateTicking(now)
    }

    private func feed(_ input: TriggerInput, at now: TimeInterval) {
        deliver(recognizer.handle(input), at: now)
    }

    private func deliver(_ events: [GestureEvent], at time: TimeInterval) {
        for event in events {
            switch event {
            case .startHold: beginRecording(.hold)
            case .startHandsFree: beginRecording(.handsFree)
            case .stopHold, .stopHandsFree, .discardHold, .cancel: endRecording()
            case .revealHold: break
            }
            InputLog.write("gesture \(event)")
            if let delegate {
                DispatchQueue.main.async { delegate.gesture(event, at: time) }
            }
        }
        applyPendingConfigurationIfIdle()
    }

    /// The active tap is created the moment a recording starts, so no click slips through in between.
    private func beginRecording(_ mode: RecordingMode) {
        recording = mode
        guard AXIsProcessTrusted() else {
            InputLog.write("no Accessibility: recording without click cleanup or trigger + Esc")
            return
        }
        createActiveTap()
    }

    private func endRecording() {
        recording = nil
        // Not inside the active tap's own callback.
        perform { [self] in
            if recording == nil { removeActiveTap() }
        }
    }

    private func createActiveTap() {
        guard activeTap == nil, let runLoop else { return }
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: Self.mask(Self.activeEvents),
            callback: { _, type, event, context in
                Unmanaged<InputMonitor>.fromOpaque(context!).takeUnretainedValue().active(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        InputLog.write("active tap created: \(tap != nil ? "yes" : "no")")
        guard let tap else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        activeTap = tap
        activeSource = source
        // macOS can block every click until reboot if an active tap outlives its permission.
        let watchdog = CFRunLoopTimerCreateWithHandler(
            nil, CFAbsoluteTimeGetCurrent() + Self.trustWatchdogInterval, Self.trustWatchdogInterval, 0, 0) { [self] _ in
                guard activeTap != nil, !AXIsProcessTrusted() else { return }
                removeActiveTap()
                InputLog.write("Accessibility revoked; active tap removed")
            }
        CFRunLoopAddTimer(runLoop, watchdog, .commonModes)
        self.watchdog = watchdog
    }

    private func removeActiveTap() {
        if let watchdog { CFRunLoopTimerInvalidate(watchdog) }
        watchdog = nil
        guard let activeTap else { return }
        CGEvent.tapEnable(tap: activeTap, enable: false)
        if let activeSource, let runLoop { CFRunLoopRemoveSource(runLoop, activeSource, .commonModes) }
        CFMachPortInvalidate(activeTap)
        self.activeTap = nil
        activeSource = nil
        InputLog.write("active tap removed")
    }

    /// The 50 ms tick runs only while a timed gesture transition could be due.
    private func updateTicking(_ now: TimeInterval) {
        let needed = GestureTicking.needsTicks(triggerDown: triggerDown,
                                               recording: recording != nil || recognizer.recording != nil,
                                               lastRelease: lastRelease, now: now)
        if needed, tickTimer == nil, let runLoop {
            let timer = CFRunLoopTimerCreateWithHandler(
                nil, CFAbsoluteTimeGetCurrent() + GestureTicking.interval, GestureTicking.interval, 0, 0) { [self] _ in
                    tick()
                }
            CFRunLoopAddTimer(runLoop, timer, .commonModes)
            tickTimer = timer
        } else if !needed, let tickTimer {
            CFRunLoopTimerInvalidate(tickTimer)
            self.tickTimer = nil
        }
    }

    private func applyPendingConfigurationIfIdle() {
        guard let pending = pendingConfiguration, recording == nil, recognizer.recording == nil, !triggerDown else {
            return
        }
        trigger = pending.trigger
        gestures = pending.gestures
        recognizer = GestureRecognizer(config: pending.gestures)
        pendingConfiguration = nil
        InputLog.write("trigger key and gesture timings updated")
    }
}
