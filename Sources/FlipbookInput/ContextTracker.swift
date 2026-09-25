import AppKit
import ApplicationServices
import FlipbookCore

/// When a typed key needs a fresh look at the focused field's label: the first key of a run, the first
/// after a click, Tab or switch, and the first after a pause.
public struct FieldLookupRule: Sendable {
    public static let pause: TimeInterval = 1.2

    private var lastKey: TimeInterval?

    public init() {}

    public mutating func needsLookup(forKeyAt time: TimeInterval) -> Bool {
        defer { lastKey = time }
        guard let lastKey else { return true }
        return time - lastKey >= Self.pause
    }

    /// On a click, Tab, or a switch.
    public mutating func invalidate() {
        lastKey = nil
    }
}

/// The frontmost app and window during a recording (design §5, "Context"): app activations come from
/// NSWorkspace on the main thread; window and title changes come from an AX observer on the AX thread,
/// which moves to each newly activated app. In window recordings, line 2 names the recorded window, whose
/// title the recording pipeline follows, so switches are all this reports. Titles go only into captions,
/// never into the log.
public final class ContextTracker: @unchecked Sendable {
    public struct Hooks: Sendable {
        /// Reserves a slot for an event whose label is still being looked up; returns its token.
        public var reserve: @Sendable (InputEventKind) -> Int
        public var fill: @Sendable (Int, InputEventKind) -> Void
        public var submit: @Sendable (InputEventKind) -> Void

        public init(reserve: @escaping @Sendable (InputEventKind) -> Int,
                    fill: @escaping @Sendable (Int, InputEventKind) -> Void,
                    submit: @escaping @Sendable (InputEventKind) -> Void) {
            self.reserve = reserve
            self.fill = fill
            self.submit = submit
        }
    }

    private let ax: AXClient
    private let ownBundleID: String

    // Main thread.
    private var hooks: Hooks?
    private var activationObserver: NSObjectProtocol?

    // AX thread.
    private var observer: AXObserver?
    private var observedApp: AXUIElement?
    private var observedName = ""
    private var observedTitle: String?
    private var observerHooks: Hooks?
    /// False in window recordings, where the focused window's title changes aren't the context.
    private var followsTitles = true

    public init(ax: AXClient, ownBundleID: String) {
        self.ax = ax
        self.ownBundleID = ownBundleID
    }

    /// The frontmost app's name. Its window title follows through `begin`'s first slot.
    public func initialContext() -> FrameContext {
        FrameContext(app: NSWorkspace.shared.frontmostApplication?.localizedName ?? "", window: nil)
    }

    /// Starts following activations and window changes. Following focus, it also reserves a title slot at
    /// once, so the first frame already has the window title, and follows title changes. Call on the main
    /// thread.
    public func begin(_ hooks: Hooks, source: ContextSource) {
        self.hooks = hooks
        let front = NSWorkspace.shared.frontmostApplication
        let pid = front?.processIdentifier
        let name = front?.localizedName ?? ""
        let followsTitles = source == .focus
        let token = followsTitles ? hooks.reserve(.titleChanged(window: nil)) : nil
        ax.perform { [self] in
            self.followsTitles = followsTitles
            let title = pid.flatMap(AXClient.windowTitle(pid:))
            if let token { hooks.fill(token, .titleChanged(window: title)) }
            if let pid { observe(pid: pid, name: name, title: title, hooks: hooks) }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier != ownBundleID else { return }
                activated(pid: app.processIdentifier, name: app.localizedName ?? "")
            }
    }

    /// Call on the main thread.
    public func end() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        hooks = nil
        ax.perform { [self] in
            removeObserver()
            observerHooks = nil
        }
    }

    private func activated(pid: pid_t, name: String) {
        guard let hooks else { return }
        let token = hooks.reserve(.switched(FrameContext(app: name, window: nil)))
        ax.perform { [self] in
            let title = AXClient.windowTitle(pid: pid)
            hooks.fill(token, .switched(FrameContext(app: name, window: title)))
            observe(pid: pid, name: name, title: title, hooks: hooks)
        }
    }

    // MARK: - On the AX thread

    private func observe(pid: pid_t, name: String, title: String?, hooks: Hooks) {
        removeObserver()
        observedName = name
        observedTitle = title
        observerHooks = hooks
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, context in
            guard let context else { return }
            Unmanaged<ContextTracker>.fromOpaque(context).takeUnretainedValue()
                .changed(notification as String, element: element)
        }
        guard let runLoop = ax.runLoop, AXObserverCreate(pid, callback, &created) == .success,
              let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, context)
        if followsTitles {
            AXObserverAddNotification(observer, app, kAXTitleChangedNotification as CFString, context)
        }
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = observer
        observedApp = app
    }

    private func removeObserver() {
        guard let observer else { return }
        if let observedApp {
            AXObserverRemoveNotification(observer, observedApp, kAXFocusedWindowChangedNotification as CFString)
            AXObserverRemoveNotification(observer, observedApp, kAXTitleChangedNotification as CFString)
        }
        if let runLoop = ax.runLoop {
            CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .commonModes)
        }
        self.observer = nil
        observedApp = nil
    }

    private func changed(_ notification: String, element: AXUIElement) {
        guard let hooks = observerHooks, let app = observedApp else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        let title = AXClient.windowTitle(pid: pid)
        if notification == kAXFocusedWindowChangedNotification as String {
            observedTitle = title
            hooks.submit(.switched(FrameContext(app: observedName, window: title)))
        } else if title != observedTitle {
            // Title changes arrive for any element in the app; only the focused window's title counts.
            observedTitle = title
            hooks.submit(.titleChanged(window: title))
        }
    }
}
