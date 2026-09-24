import AppKit
import ApplicationServices

// Spike B: Accessibility labels at the click point. Throwaway.

let axSpike = AXSpike()

final class AXSpike {
    private(set) var isOn = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let systemWide = AXUIElementCreateSystemWide()

    func toggle() { isOn ? stop() : start() }

    private func start() {
        log("AX spike: AXIsProcessTrusted = \(AXIsProcessTrusted())")
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                eventsOfInterest: 1 << CGEventMask(CGEventType.leftMouseDown.rawValue),
                                callback: { _, type, event, _ in
                                    axSpike.handle(type, event)
                                    return Unmanaged.passUnretained(event)
                                }, userInfo: nil)
        log("AX spike tap created: \(tap != nil ? "yes" : "no")")
        if let tap {
            source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        isOn = true
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        isOn = false
        log("AX spike OFF")
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("AX spike tap disabled (\(type.rawValue)) → re-enabled")
            return
        }
        let point = event.location
        // Do the AX work after the callback returns.
        DispatchQueue.main.async { self.lookup(at: point) }
    }

    private func lookup(at point: CGPoint) {
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        var element: AXUIElement?
        let t0 = DispatchTime.now()
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
        let pointText = "(\(Int(point.x)), \(Int(point.y)))"
        guard err == .success, let hit = element else {
            log("AX click \(pointText) app=\(frontApp) → no element (AXError \(err.rawValue)) in \(fmt(ms)) ms")
            return
        }

        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? frontApp
        let window = focusedWindowTitle(pid: pid)

        // Plan: walk at most 3 parents when title and description are empty.
        // Diagnostic: keep walking to 8 and report the depth where a label first appears.
        let hitInfo = attributes(of: hit)
        var el = hit
        var info = hitInfo
        var depth = 0
        var chain = [hitInfo.role]
        while info.title.isEmpty && info.desc.isEmpty && depth < 8, let parent = parentOf(el) {
            el = parent
            info = attributes(of: el)
            depth += 1
            chain.append(info.role)
        }
        let found = !(info.title.isEmpty && info.desc.isEmpty)
        let label = [info.title, info.desc, info.value, info.help].first { !$0.isEmpty } ?? ""
        let secure = hitInfo.subrole == "AXSecureTextField" ? " [secure]" : ""
        let head = "AX click \(pointText) app=\"\(app)\" window=\"\(window.prefix(60))\""
        let hitPart = " hit=\(hitInfo.role)/\(hitInfo.subrole) hitValue=\"\(hitInfo.value)\"\(secure)"
        let labelPart = " label=\"\(label)\" roleDesc=\"\(info.roleDesc)\" labelDepth=\(found ? String(depth) : "none")"
        let tail = " chain=\(chain.joined(separator: ">")) lookup=\(fmt(ms)) ms"
        log(head + hitPart + labelPart + tail)
    }

    private struct Info {
        var role = "", subrole = "", roleDesc = "", title = "", desc = "", help = "", value = ""
    }

    private func attributes(of el: AXUIElement) -> Info {
        var i = Info()
        i.role = string(el, kAXRoleAttribute)
        i.subrole = string(el, kAXSubroleAttribute)
        i.roleDesc = string(el, kAXRoleDescriptionAttribute)
        i.title = string(el, kAXTitleAttribute)
        i.desc = string(el, kAXDescriptionAttribute)
        i.help = string(el, kAXHelpAttribute)
        // Never read the value of a secure text field.
        if i.subrole != "AXSecureTextField" {
            i.value = String(string(el, kAXValueAttribute).prefix(60))
        }
        return i
    }

    private func string(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let v else { return "" }
        if let s = v as? String { return s.replacingOccurrences(of: "\n", with: " ") }
        return ""
    }

    private func parentOf(_ el: AXUIElement) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private func focusedWindowTitle(pid: pid_t) -> String {
        let appEl = AXUIElementCreateApplication(pid)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &w) == .success,
              let w, CFGetTypeID(w) == AXUIElementGetTypeID() else { return "" }
        return string(w as! AXUIElement, kAXTitleAttribute)
    }

    private func fmt(_ ms: Double) -> String { String(format: "%.1f", ms) }

    // MARK: Enable AX in Chrome/Electron

    func enableWebAX() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let name = app.localizedName ?? "?"
            let el = AXUIElementCreateApplication(app.processIdentifier)
            if app.bundleIdentifier == "com.google.Chrome" {
                let err = AXUIElementSetAttributeValue(el, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                log("set AXEnhancedUserInterface on \(name): AXError \(err.rawValue)")
            } else if isElectron(app) {
                let err = AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                log("set AXManualAccessibility on \(name) (Electron): AXError \(err.rawValue)")
            }
        }
    }

    private func isElectron(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL else { return false }
        let fw = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: fw.path)
    }
}
