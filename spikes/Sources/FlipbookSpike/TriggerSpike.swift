import AppKit
import ApplicationServices
import Carbon

// Spike A: Right ⌘ gestures, click cleanup, Esc consumption, permission probes.
// Throwaway. The real gesture logic is GestureRecognizer in M1.

let triggerSpike = TriggerSpike()

private let kRightCommand: Int64 = 54
private let kEsc: Int64 = 53
private let rightCmdDeviceBit: UInt64 = 0x10  // NX_DEVICERCMDKEYMASK
private let holdThreshold: TimeInterval = 0.25
private let doubleTapWindow: TimeInterval = 0.30

private func mask(_ types: [CGEventType]) -> CGEventMask {
    types.reduce(0) { $0 | (1 << CGEventMask($1.rawValue)) }
}

private func typeName(_ type: CGEventType) -> String {
    switch type {
    case .leftMouseDown: return "leftMouseDown"
    case .leftMouseUp: return "leftMouseUp"
    case .leftMouseDragged: return "leftMouseDragged"
    case .rightMouseDown: return "rightMouseDown"
    case .rightMouseUp: return "rightMouseUp"
    case .otherMouseDown: return "otherMouseDown"
    case .scrollWheel: return "scrollWheel"
    default: return "type \(type.rawValue)"
    }
}

final class TriggerSpike {
    enum Mode { case idle, hold, handsFree }

    private(set) var isOn = false
    private var listenTap: CFMachPort?
    private var listenSource: CFRunLoopSource?
    private var activeTap: CFMachPort?
    private var activeSource: CFRunLoopSource?
    private var watchdog: Timer?

    private(set) var mode = Mode.idle {
        didSet { spikeMenu.statusItem.button?.title = mode == .idle ? "FB" : "FB ●" }
    }
    private(set) var rcmdDown = false
    private var pressAt = Date.distantPast
    private var chord = false
    private var holdStartedThisPress = false
    private var pressUsedForDoubleTap = false
    private var lastTapRelease: Date?
    private var holdWork: DispatchWorkItem?
    private var singleTapWork: DispatchWorkItem?

    // MARK: toggle

    func toggle() { isOn ? stop() : start() }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        log("AXIsProcessTrustedWithOptions(prompt) = \(AXIsProcessTrustedWithOptions(opts))")
    }

    private func start() {
        let listen = CGPreflightListenEventAccess()
        log("probe CGPreflightListenEventAccess = \(listen)")
        log("probe CGPreflightPostEventAccess = \(CGPreflightPostEventAccess())")
        log("probe AXIsProcessTrusted = \(AXIsProcessTrusted())")
        if !listen {
            log("CGRequestListenEventAccess() = \(CGRequestListenEventAccess())")
        }

        let events = mask([.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown])
        listenTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                      eventsOfInterest: events,
                                      callback: { _, type, event, _ in
                                          triggerSpike.handleListen(type, event)
                                          return Unmanaged.passUnretained(event)
                                      }, userInfo: nil)
        log("tap created: \(listenTap != nil ? "yes" : "no")")
        if let tap = listenTap {
            listenSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), listenSource, .commonModes)
        }
        isOn = true
        log("trigger spike ON")
    }

    private func stop() {
        endRecording(reason: "spike turned off")
        if let tap = listenTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), listenSource, .commonModes)
            CFMachPortInvalidate(tap)
        }
        listenTap = nil
        listenSource = nil
        isOn = false
        log("trigger spike OFF")
    }

    // MARK: listen-only tap: gestures

    private func handleListen(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = listenTap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("listen tap disabled (\(type.rawValue)) → re-enabled")
        case .flagsChanged:
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if keycode == kRightCommand {
                let down = event.flags.rawValue & rightCmdDeviceBit != 0
                if down && !rcmdDown { rightCmdPressed() } else if !down && rcmdDown { rightCmdReleased() }
            } else {
                otherInput("modifier keycode \(keycode)")
            }
        case .keyDown:
            // Log the key class only, never the content.
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            let secure = IsSecureEventInputEnabled() ? "yes" : "no"
            log("\(keycode == kEsc ? "keyDown Esc" : "keyDown") (secure input: \(secure))")
            // Right ⌘ + Esc during a recording is a cancel, not a chord.
            if keycode == kEsc && rcmdDown && mode != .idle { return }
            otherInput("keyDown")
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if mode != .idle {
                let cmd = event.flags.contains(.maskCommand)
                log("\(typeName(type)) seen by listen tap, ⌘ flag: \(cmd ? "yes" : "no")")
            }
            otherInput(typeName(type))
        default:
            break
        }
    }

    private func rightCmdPressed() {
        log("Right ⌘ down (secure input: \(IsSecureEventInputEnabled() ? "yes" : "no"))")
        rcmdDown = true
        pressAt = Date()
        chord = false
        holdStartedThisPress = false
        pressUsedForDoubleTap = false

        if let last = lastTapRelease, Date().timeIntervalSince(last) <= doubleTapWindow {
            singleTapWork?.cancel()
            lastTapRelease = nil
            pressUsedForDoubleTap = true
            switch mode {
            case .idle:
                mode = .handsFree
                log("HANDS-FREE START")
                beginRecording()
            case .handsFree:
                log("HANDS-FREE STOP")
                endRecording(reason: "hands-free stop")
            case .hold:
                break
            }
            return
        }

        if mode == .idle {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.rcmdDown, !self.chord, self.mode == .idle else { return }
                self.holdStartedThisPress = true
                self.mode = .hold
                log("HOLD START")
                self.beginRecording()
            }
            holdWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: work)
        }
    }

    private func rightCmdReleased() {
        rcmdDown = false
        holdWork?.cancel()
        let held = Date().timeIntervalSince(pressAt)

        if mode == .hold && holdStartedThisPress {
            log("HOLD STOP")
            endRecording(reason: "hold released")
            return
        }
        if chord || pressUsedForDoubleTap || held >= holdThreshold { return }

        // A tap. It becomes a double-tap if another press follows within the window.
        lastTapRelease = Date()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastTapRelease = nil
            log("SINGLE TAP (ignored)")
        }
        singleTapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
    }

    private func otherInput(_ what: String) {
        // Any other input breaks a pending double-tap.
        if !rcmdDown {
            if lastTapRelease != nil {
                singleTapWork?.cancel()
                lastTapRelease = nil
            }
            return
        }
        if chord || holdStartedThisPress { return }
        chord = true
        holdWork?.cancel()
        log("CHORD (\(what))")
    }

    // MARK: active tap: click cleanup and Esc

    private func beginRecording() {
        let events = mask([.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
                           .scrollWheel, .keyDown])
        activeTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: events,
                                      callback: { _, type, event, _ in
                                          triggerSpike.handleActive(type, event)
                                      }, userInfo: nil)
        log("active tap created: \(activeTap != nil ? "yes" : "no")")
        guard let tap = activeTap else { return }
        activeSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), activeSource, .commonModes)

        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.activeTap != nil else { return }
            if !AXIsProcessTrusted() {
                self.removeActiveTap()
                log("ACCESSIBILITY REVOKED — active tap removed")
            }
        }
    }

    private func handleActive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = activeTap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("active tap disabled (\(type.rawValue)) → re-enabled")
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == kEsc && rcmdDown {
                log("CANCEL (Esc consumed)")
                // Tear down outside the callback.
                DispatchQueue.main.async { self.endRecording(reason: "cancel") }
                return nil
            }
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .scrollWheel:
            if mode == .hold && event.flags.contains(.maskCommand) {
                event.flags.remove(.maskCommand)
                if type == .leftMouseDown || type == .rightMouseDown {
                    log("stripped ⌘ from \(typeName(type))")
                }
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func endRecording(reason: String) {
        if mode != .idle { log("recording ended: \(reason)") }
        mode = .idle
        removeActiveTap()
    }

    private func removeActiveTap() {
        watchdog?.invalidate()
        watchdog = nil
        guard let tap = activeTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), activeSource, .commonModes)
        CFMachPortInvalidate(tap)
        activeTap = nil
        activeSource = nil
        log("active tap removed")
    }

}
