import ApplicationServices
import CoreGraphics
import FlipbookCore
import Foundation

/// Accessibility lookups on their own thread with its own run loop (design §3.2), so a slow or hung app
/// never stalls input or the UI. A 0.25 s messaging timeout bounds each call.
public final class AXClient: @unchecked Sendable {
    public static let messagingTimeout: Float = 0.25

    private let systemWide = AXUIElementCreateSystemWide()
    /// The AX thread's run loop; ContextTracker adds its observers to it.
    private(set) var runLoop: CFRunLoop?

    public init() {
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            let keepAlive = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
            CFRunLoopAddTimer(runLoop, keepAlive, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.fayzanmalik.flipbook.accessibility"
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
    }

    /// Runs the work on the AX thread.
    public func perform(_ work: @escaping @Sendable () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    /// The label of the element under a global point, by M0's rules.
    public func label(at globalPoint: CGPoint) async -> ElementLabel? {
        await run { [self] in
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(systemWide, Float(globalPoint.x), Float(globalPoint.y), &hit) == .success,
                  let hit else { return nil }
            return LabelResolver.label(atHit: AXElementNode(hit))
        }
    }

    /// The label of the focused text field; never its value.
    public func focusedFieldLabel() async -> ElementLabel? {
        await run { [self] in
            guard let focused = AXElementNode.element(systemWide, kAXFocusedUIElementAttribute) else { return nil }
            return LabelResolver.fieldLabel(focused: AXElementNode(focused))
        }
    }

    /// The app's focused window title, normalized.
    public func focusedWindowTitle(pid: pid_t) async -> String? {
        await run {
            Self.windowTitle(pid: pid)
        }
    }

    /// On the AX thread only.
    static func windowTitle(pid: pid_t) -> String? {
        guard let window = AXElementNode.element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else {
            return nil
        }
        let title = LabelResolver.normalize(AXElementNode(window).title)
        return title.isEmpty ? nil : title
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            perform { continuation.resume(returning: work()) }
        }
    }
}

/// An AXNode over a live element. Each attribute is read when asked for, on the AX thread.
struct AXElementNode: AXNode {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    var role: String { string(kAXRoleAttribute) }
    var subrole: String { string(kAXSubroleAttribute) }
    var roleDescription: String { string(kAXRoleDescriptionAttribute) }
    var title: String { string(kAXTitleAttribute) }
    var descriptionText: String { string(kAXDescriptionAttribute) }
    var placeholder: String { string(kAXPlaceholderValueAttribute) }
    /// Never read on a secure text field, whatever the caller asks.
    var value: String { subrole == LabelResolver.secureSubrole ? "" : string(kAXValueAttribute) }
    var titleElement: AXNode? { Self.element(element, kAXTitleUIElementAttribute).map(AXElementNode.init) }
    var parent: AXNode? { Self.element(element, kAXParentAttribute).map(AXElementNode.init) }

    var children: [AXNode] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AnyObject] else { return [] }
        return array.compactMap { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return AXElementNode(item as! AXUIElement)
        }
    }

    private func string(_ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
